#include "vision/mf_camera_capture.h"

#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>

#include <algorithm>
#include <chrono>

namespace {

std::string WideToUtf8(const wchar_t* wstr) {
  if (wstr == nullptr || wstr[0] == L'\0') return "";
  const int needed =
      WideCharToMultiByte(CP_UTF8, 0, wstr, -1, nullptr, 0, nullptr, nullptr);
  if (needed <= 1) return "";
  std::string out(static_cast<size_t>(needed - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, wstr, -1, &out[0], needed - 1, nullptr,
                      nullptr);
  return out;
}

template <typename T>
void SafeRelease(T** pp) {
  if (pp != nullptr && *pp != nullptr) {
    (*pp)->Release();
    *pp = nullptr;
  }
}

inline uint8_t ClampByte(int v) {
  return static_cast<uint8_t>(v < 0 ? 0 : (v > 255 ? 255 : v));
}

void YuvToRgbPixel(int y, int u, int v, uint8_t* r, uint8_t* g, uint8_t* b) {
  const int c = y - 16;
  const int d = u - 128;
  const int e = v - 128;
  *r = ClampByte((298 * c + 409 * e + 128) >> 8);
  *g = ClampByte((298 * c - 100 * d - 208 * e + 128) >> 8);
  *b = ClampByte((298 * c + 516 * d + 128) >> 8);
}

enum class ActiveSubtype { kRgb32, kNv12, kYuy2 };

// Selects the best 720p or 1080p native stream format for 2-3m far-field clarity.
void TrySelectOptimalNativeResolution(IMFSourceReader* reader) {
  DWORD best_index = 0;
  int best_score = -1;

  for (DWORD idx = 0;; ++idx) {
    IMFMediaType* native_type = nullptr;
    HRESULT hr = reader->GetNativeMediaType(
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), idx,
        &native_type);
    if (FAILED(hr) || native_type == nullptr) {
      break;
    }

    UINT32 w = 0;
    UINT32 h = 0;
    UINT32 fps_num = 30;
    UINT32 fps_den = 1;
    MFGetAttributeSize(native_type, MF_MT_FRAME_SIZE, &w, &h);
    MFGetAttributeRatio(native_type, MF_MT_FRAME_RATE, &fps_num, &fps_den);
    const double fps =
        fps_den > 0 ? static_cast<double>(fps_num) / fps_den : 30.0;

    int score = 0;
    if (w == 1280 && h == 720) {
      score += 1000;  // Ideal balance of sharp 3m hand detail & fast bandwidth
    } else if (w == 1920 && h == 1080) {
      score += 950;
    } else if (w >= 960 && w <= 1920) {
      score += 700;
    } else if (w >= 640) {
      score += 400;
    }

    if (fps >= 24.0 && fps <= 61.0) {
      score += 300;
    }

    if (score > best_score) {
      best_score = score;
      best_index = idx;
    }
    SafeRelease(&native_type);
  }

  if (best_score > 0) {
    IMFMediaType* chosen = nullptr;
    if (SUCCEEDED(reader->GetNativeMediaType(
            static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), best_index,
            &chosen)) &&
        chosen != nullptr) {
      reader->SetCurrentMediaType(
          static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), nullptr,
          chosen);
      SafeRelease(&chosen);
    }
  }
}

bool ConfigureOutputFormat(IMFSourceReader* reader, ActiveSubtype* subtype_out,
                           int* width_out, int* height_out, int* stride_out) {
  const GUID candidates[] = {MFVideoFormat_RGB32, MFVideoFormat_NV12,
                             MFVideoFormat_YUY2};
  const ActiveSubtype tags[] = {ActiveSubtype::kRgb32, ActiveSubtype::kNv12,
                                ActiveSubtype::kYuy2};

  for (size_t i = 0; i < 3; ++i) {
    IMFMediaType* out_type = nullptr;
    if (FAILED(MFCreateMediaType(&out_type))) continue;
    out_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    out_type->SetGUID(MF_MT_SUBTYPE, candidates[i]);

    HRESULT hr = reader->SetCurrentMediaType(
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), nullptr,
        out_type);
    SafeRelease(&out_type);

    if (SUCCEEDED(hr)) {
      IMFMediaType* actual = nullptr;
      if (SUCCEEDED(reader->GetCurrentMediaType(
              static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM),
              &actual)) &&
          actual != nullptr) {
        UINT32 w = 0;
        UINT32 h = 0;
        MFGetAttributeSize(actual, MF_MT_FRAME_SIZE, &w, &h);
        UINT32 raw_stride = 0;
        int stride = static_cast<int>(w * 4);
        if (SUCCEEDED(
                actual->GetUINT32(MF_MT_DEFAULT_STRIDE, &raw_stride))) {
          stride = static_cast<int>(static_cast<INT32>(raw_stride));
        } else {
          LONG calc_stride = 0;
          if (SUCCEEDED(MFGetStrideForBitmapInfoHeader(candidates[i].Data1, w,
                                                       &calc_stride))) {
            stride = static_cast<int>(calc_stride);
          }
        }
        SafeRelease(&actual);
        if (w > 0 && h > 0) {
          *subtype_out = tags[i];
          *width_out = static_cast<int>(w);
          *height_out = static_cast<int>(h);
          *stride_out = stride;
          return true;
        }
      }
    }
  }
  return false;
}

// Converts raw camera buffer into horizontally-mirrored RGB24 + 320x180 RGBA32,
// applying gentle low-light auto-gain when presenting in darkened rooms.
void ConvertAndMirrorFrame(const uint8_t* data, size_t byte_len, int width,
                           int height, int stride, ActiveSubtype subtype,
                           MirroredRgbFrame* out_frame) {
  out_frame->width = width;
  out_frame->height = height;
  out_frame->rgb.resize(static_cast<size_t>(width) * height * 3);

  const int abs_stride = stride < 0 ? -stride : stride;
  const bool bottom_up = (subtype == ActiveSubtype::kRgb32 && stride < 0);

  uint64_t luma_sum = 0;
  uint64_t sample_count = 0;

  if (subtype == ActiveSubtype::kRgb32) {
    const size_t min_bytes = static_cast<size_t>(abs_stride) * (height - 1) +
                             static_cast<size_t>(width) * 4;
    if (byte_len < min_bytes) return;

    for (int y = 0; y < height; ++y) {
      const int src_y = bottom_up ? (height - 1 - y) : y;
      const uint8_t* src_row = data + static_cast<size_t>(src_y) * abs_stride;
      uint8_t* dst_row = out_frame->rgb.data() + static_cast<size_t>(y) * width * 3;
      for (int x = 0; x < width; ++x) {
        const int mx = width - 1 - x;
        const uint8_t b = src_row[mx * 4 + 0];
        const uint8_t g = src_row[mx * 4 + 1];
        const uint8_t r = src_row[mx * 4 + 2];
        dst_row[x * 3 + 0] = r;
        dst_row[x * 3 + 1] = g;
        dst_row[x * 3 + 2] = b;
        if ((x & 7) == 0 && (y & 7) == 0) {
          luma_sum += (static_cast<uint32_t>(r) + g * 2u + b) >> 2;
          sample_count++;
        }
      }
    }
  } else if (subtype == ActiveSubtype::kNv12) {
    const size_t y_plane_bytes = static_cast<size_t>(abs_stride) * height;
    const size_t uv_plane_bytes =
        static_cast<size_t>(abs_stride) * (height / 2);
    if (byte_len < y_plane_bytes + uv_plane_bytes) return;
    const uint8_t* uv_base = data + y_plane_bytes;

    for (int y = 0; y < height; ++y) {
      const uint8_t* y_row = data + static_cast<size_t>(y) * abs_stride;
      const uint8_t* uv_row = uv_base + static_cast<size_t>(y / 2) * abs_stride;
      uint8_t* dst_row =
          out_frame->rgb.data() + static_cast<size_t>(y) * width * 3;
      for (int x = 0; x < width; ++x) {
        const int mx = width - 1 - x;
        const int yy = y_row[mx];
        const int uv_idx = (mx & ~1);
        const int uu = uv_row[uv_idx];
        const int vv = uv_row[uv_idx + 1];
        uint8_t r = 0, g = 0, b = 0;
        YuvToRgbPixel(yy, uu, vv, &r, &g, &b);
        dst_row[x * 3 + 0] = r;
        dst_row[x * 3 + 1] = g;
        dst_row[x * 3 + 2] = b;
        if ((x & 7) == 0 && (y & 7) == 0) {
          luma_sum += static_cast<uint32_t>(yy);
          sample_count++;
        }
      }
    }
  } else if (subtype == ActiveSubtype::kYuy2) {
    const size_t req_bytes = static_cast<size_t>(abs_stride) * height;
    if (byte_len < req_bytes) return;
    for (int y = 0; y < height; ++y) {
      const uint8_t* src_row = data + static_cast<size_t>(y) * abs_stride;
      uint8_t* dst_row =
          out_frame->rgb.data() + static_cast<size_t>(y) * width * 3;
      for (int x = 0; x < width; ++x) {
        const int mx = width - 1 - x;
        const int pair = (mx & ~1) * 2;
        const int yy = (mx & 1) == 0 ? src_row[pair + 0] : src_row[pair + 2];
        const int uu = src_row[pair + 1];
        const int vv = src_row[pair + 3];
        uint8_t r = 0, g = 0, b = 0;
        YuvToRgbPixel(yy, uu, vv, &r, &g, &b);
        dst_row[x * 3 + 0] = r;
        dst_row[x * 3 + 1] = g;
        dst_row[x * 3 + 2] = b;
        if ((x & 7) == 0 && (y & 7) == 0) {
          luma_sum += static_cast<uint32_t>(yy);
          sample_count++;
        }
      }
    }
  }

  // Adaptive dark-room boost when average luminance drops below 72/255
  if (sample_count > 0) {
    const double mean_luma = static_cast<double>(luma_sum) / sample_count;
    if (mean_luma > 4.0 && mean_luma < 72.0) {
      const int gain_q8 =
          std::min(512, static_cast<int>((90.0 / mean_luma) * 256.0));
      uint8_t lut[256];
      for (int i = 0; i < 256; ++i) {
        lut[i] = ClampByte((i * gain_q8) >> 8);
      }
      for (uint8_t& px : out_frame->rgb) {
        px = lut[px];
      }
    }
  }

  // Downsample to 320x180 RGBA32 for Flutter preview Texture
  out_frame->preview_rgba.resize(
      static_cast<size_t>(MfCameraCapture::kPreviewWidth) *
      MfCameraCapture::kPreviewHeight * 4);
  uint8_t* prev = out_frame->preview_rgba.data();
  for (int py = 0; py < MfCameraCapture::kPreviewHeight; ++py) {
    const int sy = (py * height) / MfCameraCapture::kPreviewHeight;
    const uint8_t* srow =
        out_frame->rgb.data() + static_cast<size_t>(sy) * width * 3;
    for (int px = 0; px < MfCameraCapture::kPreviewWidth; ++px) {
      const int sx = (px * width) / MfCameraCapture::kPreviewWidth;
      const size_t di =
          (static_cast<size_t>(py) * MfCameraCapture::kPreviewWidth + px) * 4;
      prev[di + 0] = srow[sx * 3 + 0];
      prev[di + 1] = srow[sx * 3 + 1];
      prev[di + 2] = srow[sx * 3 + 2];
      prev[di + 3] = 255;
    }
  }
}

}  // namespace

MfCameraCapture::MfCameraCapture() = default;

MfCameraCapture::~MfCameraCapture() { Stop(); }

std::vector<CameraDeviceDescriptor> MfCameraCapture::ListDevices() {
  std::vector<CameraDeviceDescriptor> out;
  const HRESULT mf_hr = MFStartup(MF_VERSION);
  if (FAILED(mf_hr)) return out;

  IMFAttributes* attrs = nullptr;
  IMFActivate** devices = nullptr;
  UINT32 count = 0;

  if (SUCCEEDED(MFCreateAttributes(&attrs, 1)) && attrs != nullptr) {
    attrs->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                   MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
    if (SUCCEEDED(MFEnumDeviceSources(attrs, &devices, &count))) {
      for (UINT32 i = 0; i < count; ++i) {
        WCHAR* friendly = nullptr;
        UINT32 friendly_len = 0;
        WCHAR* sym_link = nullptr;
        UINT32 sym_len = 0;
        devices[i]->GetAllocatedString(MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME,
                                       &friendly, &friendly_len);
        devices[i]->GetAllocatedString(
            MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK, &sym_link,
            &sym_len);

        CameraDeviceDescriptor desc;
        desc.index = static_cast<int>(i);
        desc.name = WideToUtf8(friendly);
        if (desc.name.empty()) {
          desc.name = "Camera " + std::to_string(i + 1);
        }
        desc.id = WideToUtf8(sym_link);
        if (desc.id.empty()) {
          desc.id = "cam_" + std::to_string(i);
        }
        out.push_back(desc);

        if (friendly) CoTaskMemFree(friendly);
        if (sym_link) CoTaskMemFree(sym_link);
        SafeRelease(&devices[i]);
      }
      if (devices) CoTaskMemFree(devices);
    }
    SafeRelease(&attrs);
  }

  MFShutdown();
  return out;
}

bool MfCameraCapture::Start(int camera_index, FrameCallback on_frame,
                            std::string* error_out) {
  Stop();
  on_frame_ = std::move(on_frame);
  stop_requested_.store(false);
  startup_state_.store(0);
  startup_error_.clear();

  worker_ = std::thread(&MfCameraCapture::WorkerLoop, this, camera_index);

  // Wait up to 4 seconds for camera initialization result
  for (int i = 0; i < 200 && startup_state_.load() == 0; ++i) {
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
  }

  if (startup_state_.load() != 1) {
    if (error_out != nullptr) {
      *error_out = startup_error_.empty() ? "Timed out opening webcam."
                                          : startup_error_;
    }
    Stop();
    return false;
  }
  return true;
}

void MfCameraCapture::Stop() {
  stop_requested_.store(true);
  if (worker_.joinable()) {
    worker_.join();
  }
  running_.store(false);
}

void MfCameraCapture::WorkerLoop(int camera_index) {
  const HRESULT co_hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const bool need_co_uninit = SUCCEEDED(co_hr);

  if (FAILED(MFStartup(MF_VERSION))) {
    startup_error_ = "Windows Media Foundation initialization failed.";
    startup_state_.store(-1);
    if (need_co_uninit) CoUninitialize();
    return;
  }

  IMFAttributes* enum_attrs = nullptr;
  IMFActivate** devices = nullptr;
  UINT32 count = 0;

  if (FAILED(MFCreateAttributes(&enum_attrs, 1)) ||
      FAILED(enum_attrs->SetGUID(
          MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
          MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID)) ||
      FAILED(MFEnumDeviceSources(enum_attrs, &devices, &count)) || count == 0) {
    SafeRelease(&enum_attrs);
    startup_error_ = "No webcam detected on this PC.";
    startup_state_.store(-1);
    MFShutdown();
    if (need_co_uninit) CoUninitialize();
    return;
  }

  const UINT32 chosen =
      (camera_index >= 0 && static_cast<UINT32>(camera_index) < count)
          ? static_cast<UINT32>(camera_index)
          : 0u;

  IMFMediaSource* source = nullptr;
  HRESULT hr = devices[chosen]->ActivateObject(IID_PPV_ARGS(&source));
  for (UINT32 i = 0; i < count; ++i) {
    SafeRelease(&devices[i]);
  }
  CoTaskMemFree(devices);
  SafeRelease(&enum_attrs);

  if (FAILED(hr) || source == nullptr) {
    startup_error_ =
        "Could not activate webcam (it may be in use by another app).";
    startup_state_.store(-1);
    MFShutdown();
    if (need_co_uninit) CoUninitialize();
    return;
  }

  IMFAttributes* reader_attrs = nullptr;
  MFCreateAttributes(&reader_attrs, 2);
  if (reader_attrs != nullptr) {
    reader_attrs->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);
    reader_attrs->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE);
  }

  IMFSourceReader* reader = nullptr;
  hr = MFCreateSourceReaderFromMediaSource(source, reader_attrs, &reader);
  SafeRelease(&reader_attrs);
  SafeRelease(&source);

  if (FAILED(hr) || reader == nullptr) {
    startup_error_ = "Failed to create MediaFoundation video reader.";
    startup_state_.store(-1);
    MFShutdown();
    if (need_co_uninit) CoUninitialize();
    return;
  }

  TrySelectOptimalNativeResolution(reader);

  ActiveSubtype subtype = ActiveSubtype::kRgb32;
  int width = 0;
  int height = 0;
  int stride = 0;
  if (!ConfigureOutputFormat(reader, &subtype, &width, &height, &stride)) {
    SafeRelease(&reader);
    startup_error_ = "Webcam video pixel format is unsupported.";
    startup_state_.store(-1);
    MFShutdown();
    if (need_co_uninit) CoUninitialize();
    return;
  }

  running_.store(true);
  startup_state_.store(1);

  MirroredRgbFrame reusable_frame;

  while (!stop_requested_.load()) {
    DWORD stream_idx = 0;
    DWORD flags = 0;
    LONGLONG ll_time = 0;
    IMFSample* sample = nullptr;

    hr = reader->ReadSample(
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), 0, &stream_idx,
        &flags, &ll_time, &sample);

    if (FAILED(hr) || (flags & MF_SOURCE_READERF_ERROR) != 0) {
      SafeRelease(&sample);
      break;
    }

    if (sample != nullptr) {
      IMFMediaBuffer* media_buf = nullptr;
      if (SUCCEEDED(sample->ConvertToContiguousBuffer(&media_buf)) &&
          media_buf != nullptr) {
        BYTE* raw_ptr = nullptr;
        DWORD max_len = 0;
        DWORD cur_len = 0;
        if (SUCCEEDED(media_buf->Lock(&raw_ptr, &max_len, &cur_len)) &&
            raw_ptr != nullptr && cur_len > 0) {
          const auto now_ms =
              std::chrono::duration_cast<std::chrono::milliseconds>(
                  std::chrono::steady_clock::now().time_since_epoch())
                  .count();
          reusable_frame.timestamp_ms = now_ms;
          ConvertAndMirrorFrame(raw_ptr, static_cast<size_t>(cur_len), width,
                                height, stride, subtype, &reusable_frame);
          media_buf->Unlock();

          if (on_frame_ && !reusable_frame.rgb.empty()) {
            on_frame_(reusable_frame);
          }
        }
        SafeRelease(&media_buf);
      }
      SafeRelease(&sample);
    } else {
      std::this_thread::sleep_for(std::chrono::milliseconds(4));
    }
  }

  SafeRelease(&reader);
  running_.store(false);
  MFShutdown();
  if (need_co_uninit) CoUninitialize();
}
