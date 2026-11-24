#include "projector/projector_plugin.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>
#include <shellscalingapi.h>

#include <string>
#include <vector>

#include "utils.h"

namespace {

struct MonitorCollectContext {
  flutter::EncodableList* list = nullptr;
  int index = 0;
};

std::string WideToUtf8Safe(const wchar_t* wstr) {
  if (wstr == nullptr || wstr[0] == L'\0') {
    return "";
  }
  const int size_needed = WideCharToMultiByte(CP_UTF8, 0, wstr, -1, nullptr, 0,
                                              nullptr, nullptr);
  if (size_needed <= 1) {
    return "";
  }
  std::string out(static_cast<size_t>(size_needed - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, wstr, -1, &out[0], size_needed - 1, nullptr,
                      nullptr);
  return out;
}

BOOL CALLBACK MonitorEnumProc(HMONITOR hMonitor, HDC /*hdcMonitor*/,
                              LPRECT /*lprcMonitor*/, LPARAM dwData) {
  auto* ctx = reinterpret_cast<MonitorCollectContext*>(dwData);
  MONITORINFOEXW mi = {};
  mi.cbSize = sizeof(MONITORINFOEXW);
  if (!GetMonitorInfoW(hMonitor, &mi)) {
    return TRUE;
  }

  std::string friendly_name;
  DISPLAY_DEVICEW dd = {};
  dd.cb = sizeof(DISPLAY_DEVICEW);
  if (EnumDisplayDevicesW(mi.szDevice, 0, &dd, 0)) {
    friendly_name = WideToUtf8Safe(dd.DeviceString);
  }
  const std::string device_id = WideToUtf8Safe(mi.szDevice);
  if (friendly_name.empty()) {
    friendly_name = "Display " + std::to_string(ctx->index + 1);
  }

  UINT dpi_x = 96;
  UINT dpi_y = 96;
  if (FAILED(GetDpiForMonitor(hMonitor, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y))) {
    dpi_x = 96;
  }
  const double scale = static_cast<double>(dpi_x) / 96.0;
  const bool is_primary = (mi.dwFlags & MONITORINFOF_PRIMARY) != 0;

  const int left = static_cast<int>(mi.rcMonitor.left);
  const int top = static_cast<int>(mi.rcMonitor.top);
  const int width = static_cast<int>(mi.rcMonitor.right - mi.rcMonitor.left);
  const int height = static_cast<int>(mi.rcMonitor.bottom - mi.rcMonitor.top);

  const int work_left = static_cast<int>(mi.rcWork.left);
  const int work_top = static_cast<int>(mi.rcWork.top);
  const int work_width = static_cast<int>(mi.rcWork.right - mi.rcWork.left);
  const int work_height = static_cast<int>(mi.rcWork.bottom - mi.rcWork.top);

  flutter::EncodableMap map;
  map[flutter::EncodableValue("id")] = flutter::EncodableValue(
      device_id.empty() ? ("display_" + std::to_string(ctx->index)) : device_id);
  map[flutter::EncodableValue("name")] = flutter::EncodableValue(friendly_name);
  map[flutter::EncodableValue("left")] = flutter::EncodableValue(left);
  map[flutter::EncodableValue("top")] = flutter::EncodableValue(top);
  map[flutter::EncodableValue("width")] = flutter::EncodableValue(width);
  map[flutter::EncodableValue("height")] = flutter::EncodableValue(height);
  map[flutter::EncodableValue("workLeft")] = flutter::EncodableValue(work_left);
  map[flutter::EncodableValue("workTop")] = flutter::EncodableValue(work_top);
  map[flutter::EncodableValue("workWidth")] =
      flutter::EncodableValue(work_width);
  map[flutter::EncodableValue("workHeight")] =
      flutter::EncodableValue(work_height);
  map[flutter::EncodableValue("scaleFactor")] = flutter::EncodableValue(scale);
  map[flutter::EncodableValue("isPrimary")] =
      flutter::EncodableValue(is_primary);

  ctx->list->push_back(flutter::EncodableValue(map));
  ctx->index++;
  return TRUE;
}

int GetIntOrDefault(const flutter::EncodableMap& map, const char* key,
                    int fallback) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return fallback;
  if (const auto* val = std::get_if<int32_t>(&it->second)) {
    return *val;
  }
  if (const auto* val64 = std::get_if<int64_t>(&it->second)) {
    return static_cast<int>(*val64);
  }
  return fallback;
}

bool GetBoolOrDefault(const flutter::EncodableMap& map, const char* key,
                      bool fallback) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return fallback;
  if (const auto* val = std::get_if<bool>(&it->second)) {
    return *val;
  }
  return fallback;
}

}  // namespace

// ============================================================================
// ProjectorHostWindow
// ============================================================================

ProjectorHostWindow::ProjectorHostWindow(HWND primary_hwnd,
                                         ProjectorPlugin* owner)
    : primary_hwnd_(primary_hwnd), owner_(owner) {}

ProjectorHostWindow::~ProjectorHostWindow() = default;

bool ProjectorHostWindow::CreateAndPlace(int left, int top, int width,
                                         int height, bool windowed) {
  const unsigned int safe_w = width > 320 ? static_cast<unsigned int>(width) : 1280;
  const unsigned int safe_h = height > 240 ? static_cast<unsigned int>(height) : 720;

  if (!Create(L"Pagelit Projector", Point(100, 100), Size(safe_w, safe_h))) {
    return false;
  }
  SetQuitOnClose(false);
  ApplyBounds(left, top, width, height, windowed);
  return true;
}

void ProjectorHostWindow::ApplyBounds(int left, int top, int width, int height,
                                      bool windowed) {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) return;

  if (windowed) {
    SetWindowLongPtrW(hwnd, GWL_STYLE, WS_OVERLAPPEDWINDOW | WS_VISIBLE);
    SetWindowPos(hwnd, HWND_TOP, left, top, width, height,
                 SWP_FRAMECHANGED | SWP_NOACTIVATE | SWP_SHOWWINDOW);
  } else {
    SetWindowLongPtrW(hwnd, GWL_STYLE, WS_POPUP | WS_VISIBLE);
    SetWindowPos(hwnd, HWND_TOPMOST, left, top, width, height,
                 SWP_FRAMECHANGED | SWP_NOACTIVATE | SWP_SHOWWINDOW);
  }

  if (flutter_controller_ && flutter_controller_->view()) {
    RECT client = GetClientArea();
    MoveWindow(flutter_controller_->view()->GetNativeWindow(), client.left,
               client.top, client.right - client.left,
               client.bottom - client.top, TRUE);
  }
}

void ProjectorHostWindow::SendSnapshot(
    const flutter::EncodableValue& snapshot) {
  pending_snapshot_ = snapshot;
  if (client_ready_ && client_channel_) {
    client_channel_->InvokeMethod(
        "syncState", std::make_unique<flutter::EncodableValue>(snapshot));
  }
}

bool ProjectorHostWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();
  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments({"--projector"});

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }

  // Deliberately do NOT call RegisterPlugins() here so global single-window
  // plugins (like window_manager) keep owning the primary Presenter window.
  client_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "pagelit/projector_client",
          &flutter::StandardMethodCodec::GetInstance());

  client_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "clientReady") {
          client_ready_ = true;
          if (!pending_snapshot_.IsNull() && client_channel_) {
            client_channel_->InvokeMethod(
                "syncState", std::make_unique<flutter::EncodableValue>(
                                 pending_snapshot_));
          }
          result->Success();
          return;
        }
        if (call.method_name() == "forwardCommand") {
          if (owner_ != nullptr && call.arguments() != nullptr) {
            owner_->ForwardCommandToPrimary(*call.arguments());
          }
          result->Success();
          return;
        }
        if (call.method_name() == "requestClose") {
          if (!closing_notified_ && primary_hwnd_ != nullptr) {
            closing_notified_ = true;
            PostMessageW(primary_hwnd_, kWmCloseProjectorAsync, 0, 0);
          }
          result->Success();
          return;
        }
        result->NotImplemented();
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  flutter_controller_->ForceRedraw();
  return true;
}

void ProjectorHostWindow::OnDestroy() {
  if (client_channel_) {
    client_channel_->SetMethodCallHandler(nullptr);
    client_channel_.reset();
  }
  if (flutter_controller_) {
    flutter_controller_.reset();
  }
  Win32Window::OnDestroy();
}

LRESULT ProjectorHostWindow::MessageHandler(HWND hwnd, UINT const message,
                                            WPARAM const wparam,
                                            LPARAM const lparam) noexcept {
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_CLOSE:
      if (!closing_notified_ && primary_hwnd_ != nullptr) {
        closing_notified_ = true;
        PostMessageW(primary_hwnd_, kWmCloseProjectorAsync, 0, 0);
      }
      return 0;
    case WM_FONTCHANGE:
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

// ============================================================================
// ProjectorPlugin
// ============================================================================

ProjectorPlugin::ProjectorPlugin(HWND primary_hwnd,
                                 flutter::BinaryMessenger* messenger)
    : primary_hwnd_(primary_hwnd) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "pagelit/projector",
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleMethodCall(call, std::move(result)); });

  display_event_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          messenger, "pagelit/display_events",
          &flutter::StandardMethodCodec::GetInstance());

  auto handler = std::make_unique<
      flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      [this](const flutter::EncodableValue* /*arguments*/,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
                 events)
          -> std::unique_ptr<
              flutter::StreamHandlerError<flutter::EncodableValue>> {
        display_event_sink_ = std::move(events);
        return nullptr;
      },
      [this](const flutter::EncodableValue* /*arguments*/)
          -> std::unique_ptr<
              flutter::StreamHandlerError<flutter::EncodableValue>> {
        display_event_sink_.reset();
        return nullptr;
      });
  display_event_channel_->SetStreamHandler(std::move(handler));
}

ProjectorPlugin::~ProjectorPlugin() {
  CloseProjectorInternal(false);
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }
}

flutter::EncodableList ProjectorPlugin::EnumerateDisplays() {
  flutter::EncodableList list;
  MonitorCollectContext ctx{&list, 0};
  EnumDisplayMonitors(nullptr, nullptr, MonitorEnumProc,
                      reinterpret_cast<LPARAM>(&ctx));
  return list;
}

void ProjectorPlugin::OnDisplayChange() {
  if (display_event_sink_) {
    display_event_sink_->Success(flutter::EncodableValue(EnumerateDisplays()));
  }
}

void ProjectorPlugin::OnAsyncCloseRequested() {
  CloseProjectorInternal(true);
}

void ProjectorPlugin::ForwardCommandToPrimary(
    const flutter::EncodableValue& command_map) {
  if (channel_) {
    channel_->InvokeMethod(
        "onProjectorCommand",
        std::make_unique<flutter::EncodableValue>(command_map));
  }
}

void ProjectorPlugin::CloseProjectorInternal(bool notify_dart) {
  if (projector_window_) {
    projector_window_->Destroy();
    projector_window_.reset();
  }
  if (notify_dart && channel_) {
    channel_->InvokeMethod("onProjectorClosed", nullptr);
  }
}

void ProjectorPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "getDisplays") {
    result->Success(flutter::EncodableValue(EnumerateDisplays()));
    return;
  }

  if (method == "openProjector") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (args == nullptr) {
      result->Success(flutter::EncodableValue(false));
      return;
    }

    const int left = GetIntOrDefault(*args, "left", 0);
    const int top = GetIntOrDefault(*args, "top", 0);
    const int width = GetIntOrDefault(*args, "width", 1920);
    const int height = GetIntOrDefault(*args, "height", 1080);
    const bool windowed = GetBoolOrDefault(*args, "windowed", false);

    flutter::EncodableValue snapshot;
    auto snap_it = args->find(flutter::EncodableValue("snapshot"));
    if (snap_it != args->end()) {
      snapshot = snap_it->second;
    }

    if (!projector_window_) {
      projector_window_ =
          std::make_unique<ProjectorHostWindow>(primary_hwnd_, this);
      if (!projector_window_->CreateAndPlace(left, top, width, height,
                                             windowed)) {
        projector_window_.reset();
        result->Success(flutter::EncodableValue(false));
        return;
      }
    } else {
      projector_window_->ApplyBounds(left, top, width, height, windowed);
    }

    if (!snapshot.IsNull()) {
      projector_window_->SendSnapshot(snapshot);
    }

    // Keep keyboard focus on the primary Presenter window
    if (primary_hwnd_ != nullptr && !windowed) {
      SetForegroundWindow(primary_hwnd_);
    }

    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "syncState") {
    if (projector_window_ && call.arguments() != nullptr) {
      projector_window_->SendSnapshot(*call.arguments());
    }
    result->Success();
    return;
  }

  if (method == "moveDisplays") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (args == nullptr || !projector_window_) {
      result->Success(flutter::EncodableValue(false));
      return;
    }

    auto proj_it = args->find(flutter::EncodableValue("projector"));
    if (proj_it != args->end()) {
      if (const auto* proj_map =
              std::get_if<flutter::EncodableMap>(&proj_it->second)) {
        projector_window_->ApplyBounds(
            GetIntOrDefault(*proj_map, "left", 0),
            GetIntOrDefault(*proj_map, "top", 0),
            GetIntOrDefault(*proj_map, "width", 1920),
            GetIntOrDefault(*proj_map, "height", 1080), false);
      }
    }

    auto pres_it = args->find(flutter::EncodableValue("presenter"));
    if (pres_it != args->end() && primary_hwnd_ != nullptr) {
      if (const auto* pres_map =
              std::get_if<flutter::EncodableMap>(&pres_it->second)) {
        if (IsZoomed(primary_hwnd_)) {
          ShowWindow(primary_hwnd_, SW_RESTORE);
        }
        SetWindowPos(primary_hwnd_, HWND_TOP,
                     GetIntOrDefault(*pres_map, "left", 0),
                     GetIntOrDefault(*pres_map, "top", 0),
                     GetIntOrDefault(*pres_map, "width", 1280),
                     GetIntOrDefault(*pres_map, "height", 820),
                     SWP_SHOWWINDOW);
        ShowWindow(primary_hwnd_, SW_MAXIMIZE);
        SetForegroundWindow(primary_hwnd_);
      }
    }

    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "closeProjector") {
    CloseProjectorInternal(false);
    result->Success();
    return;
  }

  result->NotImplemented();
}
