#ifndef RUNNER_VISION_ONNX_POSE_HAND_TRACKER_H_
#define RUNNER_VISION_ONNX_POSE_HAND_TRACKER_H_

#include <onnxruntime_c_api.h>

#include <array>
#include <cstdint>
#include <string>
#include <vector>

#include "vision/mf_camera_capture.h"

struct Point2f {
  float x = 0.0f;
  float y = 0.0f;
  bool valid = false;
};

struct VisionObservation {
  int64_t timestamp_ms = 0;
  bool person_detected = false;
  bool using_gpu = false;
  double fps = 0.0;
  float torso_scale = 0.22f;
  float open_palm_score = 0.0f;

  Point2f l_shoulder;
  Point2f r_shoulder;
  Point2f l_elbow;
  Point2f r_elbow;
  Point2f l_wrist;
  Point2f r_wrist;
  Point2f palm;

  bool has_hand_landmarks = false;
  std::array<Point2f, 21> hand_landmarks{};
};

// Two-stage far-field (2-3.5m) DirectML ONNX vision pipeline:
// Stage 1: MoveNet SinglePose Lightning (192x192 letterboxed) -> body pose & torso scale
// Stage 2: Native-res forearm-aligned 224x224 ROI crop -> MediaPipe 21-keypoint Hand Landmarker
class OnnxPoseHandTracker {
 public:
  OnnxPoseHandTracker();
  ~OnnxPoseHandTracker();

  bool Initialize(const std::wstring& pose_model_path,
                  const std::wstring& hand_model_path,
                  std::string* error_out);
  void Shutdown();
  bool IsInitialized() const { return initialized_; }
  bool IsUsingGpu() const { return using_gpu_; }

  VisionObservation ProcessFrame(const MirroredRgbFrame& frame);

 private:
  bool CreateSessionWithDirectMlFallback(const std::wstring& model_path,
                                         OrtSession** session_out,
                                         bool* used_gpu_out,
                                         std::string* error_out);

  bool RunPoseStage(const MirroredRgbFrame& frame, VisionObservation* obs);
  void RunHandRoiStage(const MirroredRgbFrame& frame,
                       const Point2f& wrist,
                       const Point2f& elbow,
                       VisionObservation* obs);

  const OrtApi* ort_ = nullptr;
  OrtEnv* env_ = nullptr;
  OrtMemoryInfo* cpu_mem_info_ = nullptr;

  OrtSession* pose_session_ = nullptr;
  std::string pose_input_name_;
  std::vector<std::string> pose_output_names_;
  ONNXTensorElementDataType pose_input_type_ =
      ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32;
  int pose_w_ = 192;
  int pose_h_ = 192;
  bool pose_nchw_ = false;

  OrtSession* hand_session_ = nullptr;
  std::string hand_input_name_;
  std::vector<std::string> hand_output_names_;
  int hand_w_ = 224;
  int hand_h_ = 224;
  bool hand_nchw_ = false;

  bool initialized_ = false;
  bool using_gpu_ = false;

  // Temporal tracking state for smooth ROI lock & FPS estimation
  Point2f prev_hand_center_;
  Point2f prev_up_dir_;
  int64_t prev_hand_ts_ms_ = 0;
  int active_side_ = 0;  // 0 = none, 1 = left, 2 = right
  int64_t prev_frame_ts_ms_ = 0;
  double smoothed_fps_ = 30.0;

  // Reusable scratch buffers
  std::vector<int32_t> pose_buf_i32_;
  std::vector<float> pose_buf_f32_;
  std::vector<uint8_t> pose_buf_u8_;
  std::vector<float> hand_buf_f32_;
};

#endif  // RUNNER_VISION_ONNX_POSE_HAND_TRACKER_H_
