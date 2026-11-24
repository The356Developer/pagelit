#ifndef RUNNER_VISION_MF_CAMERA_CAPTURE_H_
#define RUNNER_VISION_MF_CAMERA_CAPTURE_H_

#include <windows.h>

#include <atomic>
#include <cstdint>
#include <functional>
#include <string>
#include <thread>
#include <vector>

struct CameraDeviceDescriptor {
  int index = 0;
  std::string id;
  std::string name;
};

struct MirroredRgbFrame {
  int width = 0;
  int height = 0;
  int64_t timestamp_ms = 0;
  // Tightly packed horizontally-mirrored RGB24 (width * height * 3)
  std::vector<uint8_t> rgb;
  // Pre-scaled 320x180 RGBA32 for zero-copy Flutter preview texture
  std::vector<uint8_t> preview_rgba;
};

// Low-latency Windows Media Foundation webcam enumerator and background frame
// reader. Negotiates 720p/1080p capture and delivers horizontally mirrored
// RGB24 frames + 320x180 RGBA preview buffers on a dedicated worker thread.
class MfCameraCapture {
 public:
  using FrameCallback = std::function<void(const MirroredRgbFrame& frame)>;

  static constexpr int kPreviewWidth = 320;
  static constexpr int kPreviewHeight = 180;

  MfCameraCapture();
  ~MfCameraCapture();

  static std::vector<CameraDeviceDescriptor> ListDevices();

  bool Start(int camera_index, FrameCallback on_frame, std::string* error_out);
  void Stop();
  bool IsRunning() const { return running_.load(); }

 private:
  void WorkerLoop(int camera_index);

  std::atomic<bool> running_{false};
  std::atomic<bool> stop_requested_{false};
  std::atomic<int> startup_state_{0};  // 0 = pending, 1 = ok, -1 = failed
  std::string startup_error_;
  FrameCallback on_frame_;
  std::thread worker_;
};

#endif  // RUNNER_VISION_MF_CAMERA_CAPTURE_H_
