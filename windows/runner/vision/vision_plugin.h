#ifndef RUNNER_VISION_VISION_PLUGIN_H_
#define RUNNER_VISION_VISION_PLUGIN_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/method_channel.h>
#include <flutter_plugin_registrar.h>
#include <flutter_texture_registrar.h>
#include <windows.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <vector>

#include "vision/mf_camera_capture.h"
#include "vision/onnx_pose_hand_tracker.h"

// Custom Win32 message posted from the background vision thread to flush the
// latest VisionObservation onto Flutter's platform UI thread safely.
constexpr UINT kWmVisionObservationReady = WM_APP + 42;

class VisionPlugin {
 public:
  VisionPlugin(HWND primary_hwnd, flutter::BinaryMessenger* messenger,
               FlutterDesktopTextureRegistrarRef texture_registrar);
  ~VisionPlugin();

  // Invoked on the Win32 main UI thread when kWmVisionObservationReady arrives.
  void DispatchPendingObservationOnUiThread();

 private:
  static const FlutterDesktopPixelBuffer* CopyPixelBufferCallback(
      size_t width, size_t height, void* user_data);

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void OnCameraFrame(const MirroredRgbFrame& frame);
  void StopInternal();
  static std::wstring ResolveAssetModelPath(const wchar_t* relative_asset);

  HWND primary_hwnd_ = nullptr;
  FlutterDesktopTextureRegistrarRef texture_registrar_ = nullptr;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;

  // Zero-copy Flutter preview texture state
  int64_t texture_id_ = -1;
  std::mutex preview_mutex_;
  std::vector<uint8_t> front_rgba_;
  std::vector<uint8_t> render_rgba_;
  FlutterDesktopPixelBuffer pixel_buffer_{};

  // Coalesced UI-thread observation delivery
  std::mutex obs_mutex_;
  VisionObservation latest_obs_;
  std::atomic<bool> obs_pending_{false};

  MfCameraCapture camera_;
  OnnxPoseHandTracker tracker_;
};

#endif  // RUNNER_VISION_VISION_PLUGIN_H_
