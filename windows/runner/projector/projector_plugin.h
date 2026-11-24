#ifndef RUNNER_PROJECTOR_PROJECTOR_PLUGIN_H_
#define RUNNER_PROJECTOR_PROJECTOR_PLUGIN_H_

#include <flutter/binary_messenger.h>
#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

#include "win32_window.h"

class ProjectorPlugin;

// Custom Win32 message posted to the primary window to safely tear down the
// secondary Projector window outside of any nested Flutter engine callback.
constexpr UINT kWmCloseProjectorAsync = WM_APP + 41;

// Secondary Win32 window hosting an isolated FlutterEngine ("--projector")
// for locked 60/120Hz presentation output on an external monitor or projector.
class ProjectorHostWindow : public Win32Window {
 public:
  ProjectorHostWindow(HWND primary_hwnd, ProjectorPlugin* owner);
  ~ProjectorHostWindow() override;

  bool CreateAndPlace(int left, int top, int width, int height, bool windowed);
  void ApplyBounds(int left, int top, int width, int height, bool windowed);
  void SendSnapshot(const flutter::EncodableValue& snapshot);

 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND hwnd, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  HWND primary_hwnd_ = nullptr;
  ProjectorPlugin* owner_ = nullptr;
  bool client_ready_ = false;
  bool closing_notified_ = false;
  flutter::EncodableValue pending_snapshot_;
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      client_channel_;
};

// Manages Win32 multi-monitor enumeration, WM_DISPLAYCHANGE hot-plug events,
// and in-process synchronization with ProjectorHostWindow.
class ProjectorPlugin {
 public:
  ProjectorPlugin(HWND primary_hwnd, flutter::BinaryMessenger* messenger);
  ~ProjectorPlugin();

  void OnDisplayChange();
  void OnAsyncCloseRequested();
  void ForwardCommandToPrimary(const flutter::EncodableValue& command_map);
  void CloseProjectorInternal(bool notify_dart);

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  static flutter::EncodableList EnumerateDisplays();

  HWND primary_hwnd_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      display_event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>
      display_event_sink_;
  std::unique_ptr<ProjectorHostWindow> projector_window_;
};

#endif  // RUNNER_PROJECTOR_PROJECTOR_PLUGIN_H_
