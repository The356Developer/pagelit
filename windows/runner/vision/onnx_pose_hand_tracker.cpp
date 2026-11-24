#include "vision/onnx_pose_hand_tracker.h"

#include <dml_provider_factory.h>

#include <algorithm>
#include <cmath>

namespace {

void IgnoreStatus(const OrtApi* ort, OrtStatus* status) {
  if (status != nullptr && ort != nullptr) {
    ort->ReleaseStatus(status);
  }
}

bool CheckStatus(const OrtApi* ort, OrtStatus* status, std::string* err_out) {
  if (status == nullptr) return true;
  if (err_out != nullptr) {
    const char* msg = ort->GetErrorMessage(status);
    *err_out = msg != nullptr ? msg : "ONNX Runtime error";
  }
  ort->ReleaseStatus(status);
  return false;
}

void BilinearSampleRgb(const uint8_t* rgb, int width, int height, float sx,
                       float sy, float* r_out, float* g_out, float* b_out) {
  if (sx < 0.0f || sy < 0.0f || sx > static_cast<float>(width - 1) ||
      sy > static_cast<float>(height - 1)) {
    *r_out = 0.0f;
    *g_out = 0.0f;
    *b_out = 0.0f;
    return;
  }
  const int x0 = static_cast<int>(sx);
  const int y0 = static_cast<int>(sy);
  const int x1 = std::min(x0 + 1, width - 1);
  const int y1 = std::min(y0 + 1, height - 1);
  const float fx = sx - static_cast<float>(x0);
  const float fy = sy - static_cast<float>(y0);

  const uint8_t* p00 =
      rgb + (static_cast<size_t>(y0) * width + x0) * 3;
  const uint8_t* p10 =
      rgb + (static_cast<size_t>(y0) * width + x1) * 3;
  const uint8_t* p01 =
      rgb + (static_cast<size_t>(y1) * width + x0) * 3;
  const uint8_t* p11 =
      rgb + (static_cast<size_t>(y1) * width + x1) * 3;

  const float w00 = (1.0f - fx) * (1.0f - fy);
  const float w10 = fx * (1.0f - fy);
  const float w01 = (1.0f - fx) * fy;
  const float w11 = fx * fy;

  *r_out = p00[0] * w00 + p10[0] * w10 + p01[0] * w01 + p11[0] * w11;
  *g_out = p00[1] * w00 + p10[1] * w10 + p01[1] * w01 + p11[1] * w11;
  *b_out = p00[2] * w00 + p10[2] * w10 + p01[2] * w01 + p11[2] * w11;
}

float Dist2D(const Point2f& a, const Point2f& b) {
  const float dx = a.x - b.x;
  const float dy = a.y - b.y;
  return std::sqrt(dx * dx + dy * dy);
}

}  // namespace

OnnxPoseHandTracker::OnnxPoseHandTracker() = default;

OnnxPoseHandTracker::~OnnxPoseHandTracker() { Shutdown(); }

void OnnxPoseHandTracker::Shutdown() {
  if (ort_ != nullptr) {
    if (pose_session_ != nullptr) {
      ort_->ReleaseSession(pose_session_);
      pose_session_ = nullptr;
    }
    if (hand_session_ != nullptr) {
      ort_->ReleaseSession(hand_session_);
      hand_session_ = nullptr;
    }
    if (cpu_mem_info_ != nullptr) {
      ort_->ReleaseMemoryInfo(cpu_mem_info_);
      cpu_mem_info_ = nullptr;
    }
    if (env_ != nullptr) {
      ort_->ReleaseEnv(env_);
      env_ = nullptr;
    }
  }
  initialized_ = false;
}

bool OnnxPoseHandTracker::CreateSessionWithDirectMlFallback(
    const std::wstring& model_path, OrtSession** session_out,
    bool* used_gpu_out, std::string* error_out) {
  *session_out = nullptr;
  *used_gpu_out = false;

  // Attempt 1: Hardware-accelerated DirectML GPU session
  {
    OrtSessionOptions* dml_opts = nullptr;
    if (CheckStatus(ort_, ort_->CreateSessionOptions(&dml_opts), nullptr) &&
        dml_opts != nullptr) {
      IgnoreStatus(ort_,
                   ort_->SetSessionGraphOptimizationLevel(dml_opts, ORT_ENABLE_ALL));
      // Required by DirectML Execution Provider:
      IgnoreStatus(ort_, ort_->DisableMemPattern(dml_opts));
      IgnoreStatus(ort_,
                   ort_->SetSessionExecutionMode(dml_opts, ORT_SEQUENTIAL));

      const OrtDmlApi* dml_api = nullptr;
      OrtStatus* ep_status = ort_->GetExecutionProviderApi(
          "DML", ORT_API_VERSION, reinterpret_cast<const void**>(&dml_api));
      if (ep_status == nullptr && dml_api != nullptr) {
        OrtStatus* append_st =
            dml_api->SessionOptionsAppendExecutionProvider_DML(dml_opts, 0);
        if (append_st == nullptr) {
          OrtStatus* create_st = ort_->CreateSession(
              env_, model_path.c_str(), dml_opts, session_out);
          if (create_st == nullptr && *session_out != nullptr) {
            *used_gpu_out = true;
            ort_->ReleaseSessionOptions(dml_opts);
            return true;
          }
          if (create_st != nullptr) ort_->ReleaseStatus(create_st);
        } else {
          ort_->ReleaseStatus(append_st);
        }
      } else if (ep_status != nullptr) {
        ort_->ReleaseStatus(ep_status);
      }
      ort_->ReleaseSessionOptions(dml_opts);
    }
  }

  // Attempt 2: Multi-threaded CPU fallback
  OrtSessionOptions* cpu_opts = nullptr;
  if (!CheckStatus(ort_, ort_->CreateSessionOptions(&cpu_opts), error_out)) {
    return false;
  }
  IgnoreStatus(ort_,
               ort_->SetSessionGraphOptimizationLevel(cpu_opts, ORT_ENABLE_ALL));
  IgnoreStatus(ort_, ort_->SetIntraOpNumThreads(cpu_opts, 2));

  const bool ok = CheckStatus(
      ort_, ort_->CreateSession(env_, model_path.c_str(), cpu_opts, session_out),
      error_out);
  ort_->ReleaseSessionOptions(cpu_opts);
  return ok && (*session_out != nullptr);
}

bool OnnxPoseHandTracker::Initialize(const std::wstring& pose_model_path,
                                     const std::wstring& hand_model_path,
                                     std::string* error_out) {
  Shutdown();

  const OrtApiBase* base = OrtGetApiBase();
  if (base == nullptr) {
    if (error_out) *error_out = "OrtGetApiBase returned null.";
    return false;
  }
  ort_ = base->GetApi(ORT_API_VERSION);
  if (ort_ == nullptr) {
    if (error_out) *error_out = "Unsupported ONNX Runtime DLL version.";
    return false;
  }

  if (!CheckStatus(ort_,
                   ort_->CreateEnv(ORT_LOGGING_LEVEL_WARNING,
                                   "PagelitVision", &env_),
                   error_out)) {
    return false;
  }

  if (!CheckStatus(
          ort_,
          ort_->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault,
                                    &cpu_mem_info_),
          error_out)) {
    Shutdown();
    return false;
  }

  bool pose_gpu = false;
  bool hand_gpu = false;
  if (!CreateSessionWithDirectMlFallback(pose_model_path, &pose_session_,
                                         &pose_gpu, error_out)) {
    Shutdown();
    return false;
  }
  if (!CreateSessionWithDirectMlFallback(hand_model_path, &hand_session_,
                                         &hand_gpu, error_out)) {
    Shutdown();
    return false;
  }
  using_gpu_ = pose_gpu || hand_gpu;

  OrtAllocator* allocator = nullptr;
  if (!CheckStatus(ort_, ort_->GetAllocatorWithDefaultOptions(&allocator),
                   error_out)) {
    Shutdown();
    return false;
  }

  // Inspect Pose session I/O metadata dynamically
  {
    char* in_name = nullptr;
    if (CheckStatus(ort_,
                    ort_->SessionGetInputName(pose_session_, 0, allocator,
                                              &in_name),
                    error_out) &&
        in_name != nullptr) {
      pose_input_name_ = in_name;
      ort_->AllocatorFree(allocator, in_name);
    }

    OrtTypeInfo* type_info = nullptr;
    if (CheckStatus(ort_,
                    ort_->SessionGetInputTypeInfo(pose_session_, 0, &type_info),
                    nullptr) &&
        type_info != nullptr) {
      const OrtTensorTypeAndShapeInfo* tensor_info = nullptr;
      if (ort_->CastTypeInfoToTensorInfo(type_info, &tensor_info) == nullptr &&
          tensor_info != nullptr) {
        IgnoreStatus(ort_,
                     ort_->GetTensorElementType(tensor_info, &pose_input_type_));
        size_t dim_count = 0;
        IgnoreStatus(ort_, ort_->GetDimensionsCount(tensor_info, &dim_count));
        if (dim_count == 4) {
          std::vector<int64_t> dims(4, 0);
          IgnoreStatus(ort_, ort_->GetDimensions(tensor_info, dims.data(), 4));
          if (dims[1] == 3) {
            pose_nchw_ = true;
            if (dims[2] > 0) pose_h_ = static_cast<int>(dims[2]);
            if (dims[3] > 0) pose_w_ = static_cast<int>(dims[3]);
          } else {
            pose_nchw_ = false;
            if (dims[1] > 0) pose_h_ = static_cast<int>(dims[1]);
            if (dims[2] > 0) pose_w_ = static_cast<int>(dims[2]);
          }
        }
      }
      ort_->ReleaseTypeInfo(type_info);
    }

    size_t out_count = 0;
    IgnoreStatus(ort_, ort_->SessionGetOutputCount(pose_session_, &out_count));
    pose_output_names_.clear();
    for (size_t i = 0; i < out_count; ++i) {
      char* out_name = nullptr;
      if (ort_->SessionGetOutputName(pose_session_, i, allocator, &out_name) ==
              nullptr &&
          out_name != nullptr) {
        pose_output_names_.emplace_back(out_name);
        ort_->AllocatorFree(allocator, out_name);
      }
    }
  }

  // Inspect Hand Landmark session I/O metadata dynamically
  {
    char* in_name = nullptr;
    if (CheckStatus(ort_,
                    ort_->SessionGetInputName(hand_session_, 0, allocator,
                                              &in_name),
                    error_out) &&
        in_name != nullptr) {
      hand_input_name_ = in_name;
      ort_->AllocatorFree(allocator, in_name);
    }

    OrtTypeInfo* type_info = nullptr;
    if (CheckStatus(ort_,
                    ort_->SessionGetInputTypeInfo(hand_session_, 0, &type_info),
                    nullptr) &&
        type_info != nullptr) {
      const OrtTensorTypeAndShapeInfo* tensor_info = nullptr;
      if (ort_->CastTypeInfoToTensorInfo(type_info, &tensor_info) == nullptr &&
          tensor_info != nullptr) {
        size_t dim_count = 0;
        IgnoreStatus(ort_, ort_->GetDimensionsCount(tensor_info, &dim_count));
        if (dim_count == 4) {
          std::vector<int64_t> dims(4, 0);
          IgnoreStatus(ort_, ort_->GetDimensions(tensor_info, dims.data(), 4));
          if (dims[1] == 3) {
            hand_nchw_ = true;
            if (dims[2] > 0) hand_h_ = static_cast<int>(dims[2]);
            if (dims[3] > 0) hand_w_ = static_cast<int>(dims[3]);
          } else {
            hand_nchw_ = false;
            if (dims[1] > 0) hand_h_ = static_cast<int>(dims[1]);
            if (dims[2] > 0) hand_w_ = static_cast<int>(dims[2]);
          }
        }
      }
      ort_->ReleaseTypeInfo(type_info);
    }

    size_t out_count = 0;
    IgnoreStatus(ort_, ort_->SessionGetOutputCount(hand_session_, &out_count));
    hand_output_names_.clear();
    for (size_t i = 0; i < out_count; ++i) {
      char* out_name = nullptr;
      if (ort_->SessionGetOutputName(hand_session_, i, allocator, &out_name) ==
              nullptr &&
          out_name != nullptr) {
        hand_output_names_.emplace_back(out_name);
        ort_->AllocatorFree(allocator, out_name);
      }
    }
  }

  initialized_ = true;
  return true;
}

bool OnnxPoseHandTracker::RunPoseStage(const MirroredRgbFrame& frame,
                                       VisionObservation* obs) {
  if (pose_session_ == nullptr || pose_output_names_.empty()) return false;

  const float scale = std::min(static_cast<float>(pose_w_) / frame.width,
                               static_cast<float>(pose_h_) / frame.height);
  const int scaled_w = static_cast<int>(std::round(frame.width * scale));
  const int scaled_h = static_cast<int>(std::round(frame.height * scale));
  const int pad_x = (pose_w_ - scaled_w) / 2;
  const int pad_y = (pose_h_ - scaled_h) / 2;

  const size_t total_elems = static_cast<size_t>(pose_w_) * pose_h_ * 3;
  const int64_t shape_nhwc[4] = {1, pose_h_, pose_w_, 3};
  const int64_t shape_nchw[4] = {1, 3, pose_h_, pose_w_};
  const int64_t* active_shape = pose_nchw_ ? shape_nchw : shape_nhwc;

  OrtValue* input_tensor = nullptr;
  OrtStatus* st = nullptr;

  auto sample_pixel = [&](int px, int py, uint8_t* r, uint8_t* g, uint8_t* b) {
    if (px < pad_x || px >= pad_x + scaled_w || py < pad_y ||
        py >= pad_y + scaled_h) {
      *r = 0;
      *g = 0;
      *b = 0;
      return;
    }
    const int sx = std::clamp(
        static_cast<int>((px - pad_x) / scale), 0, frame.width - 1);
    const int sy = std::clamp(
        static_cast<int>((py - pad_y) / scale), 0, frame.height - 1);
    const uint8_t* p =
        frame.rgb.data() + (static_cast<size_t>(sy) * frame.width + sx) * 3;
    *r = p[0];
    *g = p[1];
    *b = p[2];
  };

  if (pose_input_type_ == ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32) {
    pose_buf_i32_.assign(total_elems, 0);
    const size_t plane = static_cast<size_t>(pose_w_) * pose_h_;
    for (int y = 0; y < pose_h_; ++y) {
      for (int x = 0; x < pose_w_; ++x) {
        uint8_t r = 0, g = 0, b = 0;
        sample_pixel(x, y, &r, &g, &b);
        const size_t idx = static_cast<size_t>(y) * pose_w_ + x;
        if (pose_nchw_) {
          pose_buf_i32_[idx] = r;
          pose_buf_i32_[plane + idx] = g;
          pose_buf_i32_[plane * 2 + idx] = b;
        } else {
          pose_buf_i32_[idx * 3 + 0] = r;
          pose_buf_i32_[idx * 3 + 1] = g;
          pose_buf_i32_[idx * 3 + 2] = b;
        }
      }
    }
    st = ort_->CreateTensorWithDataAsOrtValue(
        cpu_mem_info_, pose_buf_i32_.data(), total_elems * sizeof(int32_t),
        active_shape, 4, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32, &input_tensor);
  } else if (pose_input_type_ == ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8) {
    pose_buf_u8_.assign(total_elems, 0);
    const size_t plane = static_cast<size_t>(pose_w_) * pose_h_;
    for (int y = 0; y < pose_h_; ++y) {
      for (int x = 0; x < pose_w_; ++x) {
        uint8_t r = 0, g = 0, b = 0;
        sample_pixel(x, y, &r, &g, &b);
        const size_t idx = static_cast<size_t>(y) * pose_w_ + x;
        if (pose_nchw_) {
          pose_buf_u8_[idx] = r;
          pose_buf_u8_[plane + idx] = g;
          pose_buf_u8_[plane * 2 + idx] = b;
        } else {
          pose_buf_u8_[idx * 3 + 0] = r;
          pose_buf_u8_[idx * 3 + 1] = g;
          pose_buf_u8_[idx * 3 + 2] = b;
        }
      }
    }
    st = ort_->CreateTensorWithDataAsOrtValue(
        cpu_mem_info_, pose_buf_u8_.data(), total_elems * sizeof(uint8_t),
        active_shape, 4, ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8, &input_tensor);
  } else {
    pose_buf_f32_.assign(total_elems, 0.0f);
    const size_t plane = static_cast<size_t>(pose_w_) * pose_h_;
    for (int y = 0; y < pose_h_; ++y) {
      for (int x = 0; x < pose_w_; ++x) {
        uint8_t r = 0, g = 0, b = 0;
        sample_pixel(x, y, &r, &g, &b);
        const size_t idx = static_cast<size_t>(y) * pose_w_ + x;
        if (pose_nchw_) {
          pose_buf_f32_[idx] = static_cast<float>(r);
          pose_buf_f32_[plane + idx] = static_cast<float>(g);
          pose_buf_f32_[plane * 2 + idx] = static_cast<float>(b);
        } else {
          pose_buf_f32_[idx * 3 + 0] = static_cast<float>(r);
          pose_buf_f32_[idx * 3 + 1] = static_cast<float>(g);
          pose_buf_f32_[idx * 3 + 2] = static_cast<float>(b);
        }
      }
    }
    st = ort_->CreateTensorWithDataAsOrtValue(
        cpu_mem_info_, pose_buf_f32_.data(), total_elems * sizeof(float),
        active_shape, 4, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &input_tensor);
  }

  if (st != nullptr || input_tensor == nullptr) {
    if (st != nullptr) ort_->ReleaseStatus(st);
    return false;
  }

  const char* in_names[1] = {pose_input_name_.c_str()};
  const char* out_names[1] = {pose_output_names_[0].c_str()};
  OrtValue* out_tensor = nullptr;

  st = ort_->Run(pose_session_, nullptr, in_names,
                 (const OrtValue* const*)&input_tensor, 1, out_names, 1,
                 &out_tensor);
  ort_->ReleaseValue(input_tensor);

  if (st != nullptr || out_tensor == nullptr) {
    if (st != nullptr) ort_->ReleaseStatus(st);
    return false;
  }

  float* kp = nullptr;
  st = ort_->GetTensorMutableData(out_tensor, reinterpret_cast<void**>(&kp));
  if (st != nullptr || kp == nullptr) {
    if (st != nullptr) ort_->ReleaseStatus(st);
    ort_->ReleaseValue(out_tensor);
    return false;
  }

  // MoveNet output: [1, 1, 17, 3] -> (y_norm, x_norm, score) in 192x192 space
  auto decode_kp = [&](int idx, float min_conf) -> Point2f {
    const float yn = kp[idx * 3 + 0];
    const float xn = kp[idx * 3 + 1];
    const float sc = kp[idx * 3 + 2];
    if (sc < min_conf) return Point2f{0.0f, 0.0f, false};
    const float px = (xn * pose_w_ - pad_x) / scaled_w;
    const float py = (yn * pose_h_ - pad_y) / scaled_h;
    return Point2f{std::clamp(px, 0.0f, 1.0f), std::clamp(py, 0.0f, 1.0f),
                   true};
  };

  const Point2f nose = decode_kp(0, 0.22f);
  obs->l_shoulder = decode_kp(5, 0.20f);
  obs->r_shoulder = decode_kp(6, 0.20f);
  obs->l_elbow = decode_kp(7, 0.18f);
  obs->r_elbow = decode_kp(8, 0.18f);
  obs->l_wrist = decode_kp(9, 0.18f);
  obs->r_wrist = decode_kp(10, 0.18f);
  const Point2f l_hip = decode_kp(11, 0.20f);
  const Point2f r_hip = decode_kp(12, 0.20f);

  ort_->ReleaseValue(out_tensor);

  obs->person_detected =
      obs->l_shoulder.valid || obs->r_shoulder.valid || nose.valid;
  if (!obs->person_detected) {
    return false;
  }

  float sh_span = 0.16f;
  float sh_mid_y = 0.42f;
  if (obs->l_shoulder.valid && obs->r_shoulder.valid) {
    sh_span = Dist2D(obs->l_shoulder, obs->r_shoulder);
    sh_mid_y = 0.5f * (obs->l_shoulder.y + obs->r_shoulder.y);
  } else if (obs->l_shoulder.valid) {
    sh_mid_y = obs->l_shoulder.y;
  } else if (obs->r_shoulder.valid) {
    sh_mid_y = obs->r_shoulder.y;
  }

  float torso = sh_span * 1.65f;
  if (l_hip.valid && r_hip.valid) {
    const float hip_mid_y = 0.5f * (l_hip.y + r_hip.y);
    torso = std::max(torso, hip_mid_y - sh_mid_y);
  }
  obs->torso_scale = std::clamp(torso, 0.08f, 0.65f);
  return true;
}

void OnnxPoseHandTracker::RunHandRoiStage(const MirroredRgbFrame& frame,
                                          const Point2f& wrist,
                                          const Point2f& elbow,
                                          VisionObservation* obs) {
  if (hand_session_ == nullptr || hand_output_names_.empty()) return;

  const float fw = static_cast<float>(frame.width);
  const float fh = static_cast<float>(frame.height);
  const float wx = wrist.x * fw;
  const float wy = wrist.y * fh;

  float up_x = 0.0f;
  float up_y = -1.0f;
  if (elbow.valid) {
    const float vx = wx - elbow.x * fw;
    const float vy = wy - elbow.y * fh;
    const float vlen = std::sqrt(vx * vx + vy * vy);
    if (vlen > 6.0f) {
      up_x = vx / vlen;
      up_y = vy / vlen;
    }
  }

  // Smooth orientation slightly if we had a recent high-confidence hand lock
  const bool recent_lock =
      prev_hand_center_.valid && (frame.timestamp_ms - prev_hand_ts_ms_ < 160);
  if (recent_lock && prev_up_dir_.valid) {
    const float bx = up_x * 0.65f + prev_up_dir_.x * 0.35f;
    const float by = up_y * 0.65f + prev_up_dir_.y * 0.35f;
    const float blen = std::sqrt(bx * bx + by * by);
    if (blen > 1e-3f) {
      up_x = bx / blen;
      up_y = by / blen;
    }
  }

  const float crop_side =
      std::clamp(obs->torso_scale * fh * 0.96f, 92.0f, fh * 0.72f);

  float cx = wx + up_x * (crop_side * 0.24f);
  float cy = wy + up_y * (crop_side * 0.24f);
  if (recent_lock) {
    const float dist = std::hypot(cx - prev_hand_center_.x,
                                  cy - prev_hand_center_.y);
    if (dist < crop_side * 0.45f) {
      cx = cx * 0.60f + prev_hand_center_.x * 0.40f;
      cy = cy * 0.60f + prev_hand_center_.y * 0.40f;
    }
  }

  // Orthonormal ROI basis: u_up = (up_x, up_y), u_right = (-up_y, up_x)
  const float right_x = -up_y;
  const float right_y = up_x;

  const size_t total_elems = static_cast<size_t>(hand_w_) * hand_h_ * 3;
  hand_buf_f32_.resize(total_elems);
  const size_t plane = static_cast<size_t>(hand_w_) * hand_h_;
  const float inv_255 = 1.0f / 255.0f;

  for (int v = 0; v < hand_h_; ++v) {
    const float dy =
        (static_cast<float>(v) - hand_h_ * 0.5f) / static_cast<float>(hand_h_);
    for (int u = 0; u < hand_w_; ++u) {
      const float dx = (static_cast<float>(u) - hand_w_ * 0.5f) /
                       static_cast<float>(hand_w_);
      const float sx = cx + crop_side * (dx * right_x - dy * up_x);
      const float sy = cy + crop_side * (dx * right_y - dy * up_y);

      float r = 0.0f, g = 0.0f, b = 0.0f;
      BilinearSampleRgb(frame.rgb.data(), frame.width, frame.height, sx, sy, &r,
                        &g, &b);

      const size_t idx = static_cast<size_t>(v) * hand_w_ + u;
      if (hand_nchw_) {
        hand_buf_f32_[idx] = r * inv_255;
        hand_buf_f32_[plane + idx] = g * inv_255;
        hand_buf_f32_[plane * 2 + idx] = b * inv_255;
      } else {
        hand_buf_f32_[idx * 3 + 0] = r * inv_255;
        hand_buf_f32_[idx * 3 + 1] = g * inv_255;
        hand_buf_f32_[idx * 3 + 2] = b * inv_255;
      }
    }
  }

  const int64_t shape_nhwc[4] = {1, hand_h_, hand_w_, 3};
  const int64_t shape_nchw[4] = {1, 3, hand_h_, hand_w_};
  OrtValue* input_tensor = nullptr;
  OrtStatus* st = ort_->CreateTensorWithDataAsOrtValue(
      cpu_mem_info_, hand_buf_f32_.data(), total_elems * sizeof(float),
      hand_nchw_ ? shape_nchw : shape_nhwc, 4,
      ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &input_tensor);
  if (st != nullptr || input_tensor == nullptr) {
    if (st != nullptr) ort_->ReleaseStatus(st);
    return;
  }

  const char* in_names[1] = {hand_input_name_.c_str()};
  std::vector<const char*> out_names;
  out_names.reserve(hand_output_names_.size());
  for (const auto& s : hand_output_names_) {
    out_names.push_back(s.c_str());
  }
  std::vector<OrtValue*> out_tensors(out_names.size(), nullptr);

  st = ort_->Run(hand_session_, nullptr, in_names,
                 (const OrtValue* const*)&input_tensor, 1, out_names.data(),
                 out_names.size(), out_tensors.data());
  ort_->ReleaseValue(input_tensor);

  if (st != nullptr) {
    ort_->ReleaseStatus(st);
    return;
  }

  const float* screen_lm = nullptr;
  float hand_conf = 0.0f;

  // Identify screen landmarks (first [1, 63] tensor with pixel coords in 0..224)
  // and confidence score (first [1, 1] tensor).
  for (size_t i = 0; i < out_tensors.size(); ++i) {
    if (out_tensors[i] == nullptr) continue;
    OrtTensorTypeAndShapeInfo* info = nullptr;
    size_t elem_count = 0;
    if (ort_->GetTensorTypeAndShape(out_tensors[i], &info) == nullptr &&
        info != nullptr) {
      IgnoreStatus(ort_, ort_->GetTensorShapeElementCount(info, &elem_count));
      ort_->ReleaseTensorTypeAndShapeInfo(info);
    }
    float* ptr = nullptr;
    IgnoreStatus(
        ort_, ort_->GetTensorMutableData(out_tensors[i],
                                         reinterpret_cast<void**>(&ptr)));
    if (ptr == nullptr) continue;

    if (elem_count == 63 && screen_lm == nullptr) {
      // Distinguish screen_landmarks (values ~ 0..224) from world_landmarks (~ -0.1..0.1)
      float max_abs = 0.0f;
      for (int k = 0; k < 21; ++k) {
        max_abs = std::max(max_abs, std::abs(ptr[k * 3]));
      }
      if (max_abs > 4.0f) {
        screen_lm = ptr;
      }
    } else if (elem_count == 1 && hand_conf == 0.0f) {
      // First scalar output in MediaPipe handpose ONNX is hand presence confidence
      hand_conf = ptr[0];
    }
  }

  if (screen_lm != nullptr && hand_conf >= 0.42f) {
    obs->has_hand_landmarks = true;
    for (int k = 0; k < 21; ++k) {
      const float lx = screen_lm[k * 3 + 0];
      const float ly = screen_lm[k * 3 + 1];
      const float dx =
          (lx - hand_w_ * 0.5f) / static_cast<float>(hand_w_);
      const float dy =
          (ly - hand_h_ * 0.5f) / static_cast<float>(hand_h_);
      const float img_x = (cx + crop_side * (dx * right_x - dy * up_x)) / fw;
      const float img_y = (cy + crop_side * (dx * right_y - dy * up_y)) / fh;
      obs->hand_landmarks[k] = Point2f{std::clamp(img_x, 0.0f, 1.0f),
                                       std::clamp(img_y, 0.0f, 1.0f), true};
    }

    // Palm center = midpoint between wrist (0) and middle finger MCP (9)
    const Point2f& lm0 = obs->hand_landmarks[0];
    const Point2f& lm9 = obs->hand_landmarks[9];
    obs->palm = Point2f{0.5f * (lm0.x + lm9.x), 0.5f * (lm0.y + lm9.y), true};

    prev_hand_center_ = Point2f{obs->palm.x * fw, obs->palm.y * fh, true};
    const float ux = (lm9.x - lm0.x) * fw;
    const float uy = (lm9.y - lm0.y) * fh;
    const float ulen = std::hypot(ux, uy);
    if (ulen > 4.0f) {
      prev_up_dir_ = Point2f{ux / ulen, uy / ulen, true};
    }
    prev_hand_ts_ms_ = frame.timestamp_ms;
  } else {
    // Fallback palm estimate from forearm projection if fingers blurred mid-swipe
    obs->palm = Point2f{std::clamp(cx / fw, 0.0f, 1.0f),
                        std::clamp(cy / fh, 0.0f, 1.0f), true};
  }

  for (OrtValue* v : out_tensors) {
    if (v != nullptr) ort_->ReleaseValue(v);
  }
}

VisionObservation OnnxPoseHandTracker::ProcessFrame(
    const MirroredRgbFrame& frame) {
  VisionObservation obs;
  obs.timestamp_ms = frame.timestamp_ms;
  obs.using_gpu = using_gpu_;

  if (prev_frame_ts_ms_ > 0 && frame.timestamp_ms > prev_frame_ts_ms_) {
    const double inst_fps =
        1000.0 / static_cast<double>(frame.timestamp_ms - prev_frame_ts_ms_);
    smoothed_fps_ = smoothed_fps_ * 0.85 + inst_fps * 0.15;
  }
  prev_frame_ts_ms_ = frame.timestamp_ms;
  obs.fps = smoothed_fps_;

  if (!initialized_ || frame.rgb.empty()) return obs;

  if (!RunPoseStage(frame, &obs)) {
    active_side_ = 0;
    return obs;
  }

  float sh_mid_y = 0.42f;
  if (obs.l_shoulder.valid && obs.r_shoulder.valid) {
    sh_mid_y = 0.5f * (obs.l_shoulder.y + obs.r_shoulder.y);
  } else if (obs.l_shoulder.valid) {
    sh_mid_y = obs.l_shoulder.y;
  } else if (obs.r_shoulder.valid) {
    sh_mid_y = obs.r_shoulder.y;
  }

  // Upper-body gesture gate: only run Stage 2 Hand Landmarker when a wrist is
  // raised above lower-chest/elbow height (saves ~70% GPU/CPU while hands rest).
  const float gate_bottom_y =
      std::min(0.92f, sh_mid_y + 0.90f * obs.torso_scale);
  const bool l_raised = obs.l_wrist.valid && obs.l_wrist.y <= gate_bottom_y;
  const bool r_raised = obs.r_wrist.valid && obs.r_wrist.y <= gate_bottom_y;

  int chosen_side = 0;
  if (l_raised && r_raised) {
    if (active_side_ == 1 && obs.l_wrist.y <= obs.r_wrist.y + 0.06f) {
      chosen_side = 1;
    } else if (active_side_ == 2 && obs.r_wrist.y <= obs.l_wrist.y + 0.06f) {
      chosen_side = 2;
    } else {
      chosen_side = obs.l_wrist.y <= obs.r_wrist.y ? 1 : 2;
    }
  } else if (l_raised) {
    chosen_side = 1;
  } else if (r_raised) {
    chosen_side = 2;
  }
  active_side_ = chosen_side;

  if (chosen_side == 1) {
    RunHandRoiStage(frame, obs.l_wrist, obs.l_elbow, &obs);
  } else if (chosen_side == 2) {
    RunHandRoiStage(frame, obs.r_wrist, obs.r_elbow, &obs);
  }

  return obs;
}
