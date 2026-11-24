#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  projector_plugin_ = std::make_unique<ProjectorPlugin>(
      GetHandle(), flutter_controller_->engine()->messenger());
  FlutterDesktopTextureRegistrarRef tex_registrar =
      FlutterDesktopRegistrarGetTextureRegistrar(
          flutter_controller_->engine()->GetRegistrarForPlugin(
              "PagelitVisionPlugin"));
  vision_plugin_ = std::make_unique<VisionPlugin>(
      GetHandle(), flutter_controller_->engine()->messenger(), tex_registrar);
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (vision_plugin_) {
    vision_plugin_.reset();
  }
  if (projector_plugin_) {
    projector_plugin_.reset();
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_DISPLAYCHANGE:
      if (projector_plugin_) {
        projector_plugin_->OnDisplayChange();
      }
      break;
    case kWmCloseProjectorAsync:
      if (projector_plugin_) {
        projector_plugin_->OnAsyncCloseRequested();
      }
      return 0;
    case kWmVisionObservationReady:
      if (vision_plugin_) {
        vision_plugin_->DispatchPendingObservationOnUiThread();
      }
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
