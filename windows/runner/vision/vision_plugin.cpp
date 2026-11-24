#include "vision/vision_plugin.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

#include <filesystem>
#include <string>

namespace {

flutter::EncodableValue PointToList(const Point2f& pt) {
  if (!pt.valid) return flutter::EncodableValue();
  flutter::EncodableList list;
  list.reserve(2);
  list.push_back(flutter::EncodableValue(static_cast<double>(pt.x)));
  list.push_back(flutter::EncodableValue(static_cast<double>(pt.y)));
  return flutter::EncodableValue(list);
}

int GetIntArg(const flutter::EncodableMap& map, const char* key, int fallback) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return fallback;
  if (const auto* v32 = std::get_if<int32_t>(&it->second)) return *v32;
  if (const auto* v64 = std::get_if<int64_t>(&it->second)) {
    return static_cast<int>(*v64);
  }
  return fallback;
}

}  // namespace

VisionPlugin::VisionPlugin(HWND primary_hwnd,
                           flutter::BinaryMessenger* messenger,
                           FlutterDesktopTextureRegistrarRef texture_registrar)
    : primary_hwnd_(primary_hwnd), texture_registrar_(texture_registrar) {
  const size_t preview_bytes =
      static_cast<size_t>(MfCameraCapture::kPreviewWidth) *
      MfCameraCapture::kPreviewHeight * 4;
  front_rgba_.assign(preview_bytes, 0);
  render_rgba_.assign(preview_bytes, 0);

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "pagelit/vision",
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleMethodCall(call, std::move(result)); });

  event_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          messenger, "pagelit/vision_events",
          &flutter::StandardMethodCodec::GetInstance());

  auto handler = std::make_unique<
      flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      [this](const flutter::EncodableValue* /*arguments*/,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
                 events)
          -> std::unique_ptr<
              flutter::StreamHandlerError<flutter::EncodableValue>> {
        event_sink_ = std::move(events);
        return nullptr;
      },
      [this](const flutter::EncodableValue* /*arguments*/)
          -> std::unique_ptr<
              flutter::StreamHandlerError<flutter::EncodableValue>> {
        event_sink_.reset();
        return nullptr;
      });
  event_channel_->SetStreamHandler(std::move(handler));
}

VisionPlugin::~VisionPlugin() {
  StopInternal();
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }
}

const FlutterDesktopPixelBuffer* VisionPlugin::CopyPixelBufferCallback(
    size_t /*width*/, size_t /*height*/, void* user_data) {
  auto* self = static_cast<VisionPlugin*>(user_data);
  std::lock_guard<std::mutex> lock(self->preview_mutex_);
  self->render_rgba_ = self->front_rgba_;
  self->pixel_buffer_.buffer = self->render_rgba_.data();
  self->pixel_buffer_.width = MfCameraCapture::kPreviewWidth;
  self->pixel_buffer_.height = MfCameraCapture::kPreviewHeight;
  self->pixel_buffer_.release_callback = nullptr;
  self->pixel_buffer_.release_context = nullptr;
  return &self->pixel_buffer_;
}

std::wstring VisionPlugin::ResolveAssetModelPath(
    const wchar_t* relative_asset) {
  wchar_t exe_buf[MAX_PATH] = {};
  GetModuleFileNameW(nullptr, exe_buf, MAX_PATH);
  std::filesystem::path exe_dir = std::filesystem::path(exe_buf).parent_path();

  std::filesystem::path bundled =
      exe_dir / L"data" / L"flutter_assets" / relative_asset;
  if (std::filesystem::exists(bundled)) {
    return bundled.wstring();
  }
  return (std::filesystem::current_path() / relative_asset).wstring();
}

void VisionPlugin::StopInternal() {
  camera_.Stop();
  obs_pending_.store(false);
  if (texture_id_ >= 0 && texture_registrar_ != nullptr) {
    FlutterDesktopTextureRegistrarUnregisterExternalTexture(
        texture_registrar_, texture_id_, nullptr, nullptr);
    texture_id_ = -1;
  }
}

void VisionPlugin::OnCameraFrame(const MirroredRgbFrame& frame) {
  if (!frame.preview_rgba.empty()) {
    {
      std::lock_guard<std::mutex> lock(preview_mutex_);
      if (front_rgba_.size() == frame.preview_rgba.size()) {
        std::copy(frame.preview_rgba.begin(), frame.preview_rgba.end(),
                  front_rgba_.begin());
      } else {
        front_rgba_ = frame.preview_rgba;
      }
    }
    if (texture_id_ >= 0 && texture_registrar_ != nullptr) {
      FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable(
          texture_registrar_, texture_id_);
    }
  }

  VisionObservation obs = tracker_.ProcessFrame(frame);
  {
    std::lock_guard<std::mutex> lock(obs_mutex_);
    latest_obs_ = obs;
  }

  bool expected = false;
  if (obs_pending_.compare_exchange_strong(expected, true)) {
    if (primary_hwnd_ != nullptr) {
      PostMessageW(primary_hwnd_, kWmVisionObservationReady, 0, 0);
    }
  }
}

void VisionPlugin::DispatchPendingObservationOnUiThread() {
  obs_pending_.store(false);
  if (!event_sink_) return;

  VisionObservation obs;
  {
    std::lock_guard<std::mutex> lock(obs_mutex_);
    obs = latest_obs_;
  }

  flutter::EncodableMap map;
  map[flutter::EncodableValue("timestampMs")] =
      flutter::EncodableValue(obs.timestamp_ms);
  map[flutter::EncodableValue("personDetected")] =
      flutter::EncodableValue(obs.person_detected);
  map[flutter::EncodableValue("usingGpu")] =
      flutter::EncodableValue(obs.using_gpu);
  map[flutter::EncodableValue("fps")] = flutter::EncodableValue(obs.fps);
  map[flutter::EncodableValue("torsoScale")] =
      flutter::EncodableValue(static_cast<double>(obs.torso_scale));
  map[flutter::EncodableValue("openPalmScore")] =
      flutter::EncodableValue(static_cast<double>(obs.open_palm_score));

  if (obs.l_shoulder.valid) {
    map[flutter::EncodableValue("lShoulder")] = PointToList(obs.l_shoulder);
  }
  if (obs.r_shoulder.valid) {
    map[flutter::EncodableValue("rShoulder")] = PointToList(obs.r_shoulder);
  }
  if (obs.l_elbow.valid) {
    map[flutter::EncodableValue("lElbow")] = PointToList(obs.l_elbow);
  }
  if (obs.r_elbow.valid) {
    map[flutter::EncodableValue("rElbow")] = PointToList(obs.r_elbow);
  }
  if (obs.l_wrist.valid) {
    map[flutter::EncodableValue("lWrist")] = PointToList(obs.l_wrist);
  }
  if (obs.r_wrist.valid) {
    map[flutter::EncodableValue("rWrist")] = PointToList(obs.r_wrist);
  }
  if (obs.palm.valid) {
    map[flutter::EncodableValue("palm")] = PointToList(obs.palm);
  }

  if (obs.has_hand_landmarks) {
    flutter::EncodableList lm_flat;
    lm_flat.reserve(42);
    for (const auto& lm : obs.hand_landmarks) {
      lm_flat.push_back(flutter::EncodableValue(static_cast<double>(lm.x)));
      lm_flat.push_back(flutter::EncodableValue(static_cast<double>(lm.y)));
    }
    map[flutter::EncodableValue("handLandmarks")] =
        flutter::EncodableValue(lm_flat);
  }

  event_sink_->Success(flutter::EncodableValue(map));
}

void VisionPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "listCameras") {
    const auto cams = MfCameraCapture::ListDevices();
    flutter::EncodableList list;
    for (const auto& c : cams) {
      flutter::EncodableMap m;
      m[flutter::EncodableValue("index")] = flutter::EncodableValue(c.index);
      m[flutter::EncodableValue("id")] = flutter::EncodableValue(c.id);
      m[flutter::EncodableValue("name")] = flutter::EncodableValue(c.name);
      list.push_back(flutter::EncodableValue(m));
    }
    result->Success(flutter::EncodableValue(list));
    return;
  }

  if (method == "start") {
    int cam_index = 0;
    if (const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments())) {
      cam_index = GetIntArg(*args, "cameraIndex", 0);
    }

    StopInternal();

    if (!tracker_.IsInitialized()) {
      const std::wstring pose_path =
          ResolveAssetModelPath(L"assets\\models\\movenet_lightning.onnx");
      const std::wstring hand_path =
          ResolveAssetModelPath(L"assets\\models\\hand_landmark.onnx");
      std::string ort_err;
      if (!tracker_.Initialize(pose_path, hand_path, &ort_err)) {
        flutter::EncodableMap resp;
        resp[flutter::EncodableValue("ok")] = flutter::EncodableValue(false);
        resp[flutter::EncodableValue("error")] = flutter::EncodableValue(
            "ONNX vision init failed: " + ort_err);
        result->Success(flutter::EncodableValue(resp));
        return;
      }
    }

    if (texture_registrar_ != nullptr && texture_id_ < 0) {
      FlutterDesktopTextureInfo info = {};
      info.type = kFlutterDesktopPixelBufferTexture;
      info.pixel_buffer_config.callback = &VisionPlugin::CopyPixelBufferCallback;
      info.pixel_buffer_config.user_data = this;
      texture_id_ = FlutterDesktopTextureRegistrarRegisterExternalTexture(
          texture_registrar_, &info);
    }

    std::string cam_err;
    if (!camera_.Start(
            cam_index,
            [this](const MirroredRgbFrame& frame) { OnCameraFrame(frame); },
            &cam_err)) {
      StopInternal();
      flutter::EncodableMap resp;
      resp[flutter::EncodableValue("ok")] = flutter::EncodableValue(false);
      resp[flutter::EncodableValue("error")] =
          flutter::EncodableValue(cam_err);
      result->Success(flutter::EncodableValue(resp));
      return;
    }

    flutter::EncodableMap resp;
    resp[flutter::EncodableValue("ok")] = flutter::EncodableValue(true);
    resp[flutter::EncodableValue("textureId")] =
        flutter::EncodableValue(texture_id_);
    resp[flutter::EncodableValue("usingGpu")] =
        flutter::EncodableValue(tracker_.IsUsingGpu());
    result->Success(flutter::EncodableValue(resp));
    return;
  }

  if (method == "stop") {
    StopInternal();
    result->Success();
    return;
  }

  result->NotImplemented();
}
