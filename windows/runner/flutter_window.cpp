#include "flutter_window.h"

#include <dwmapi.h>

#include <cstdint>
#include <optional>

#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kWindowChromeChannel[] = "dayseven/window_chrome";
constexpr DWORD kDwmwaUseImmersiveDarkMode = 20;
constexpr DWORD kDwmwaCaptionColor = 35;

bool IsDarkColor(uint32_t argb) {
  const double red = static_cast<double>((argb >> 16) & 0xff) / 255.0;
  const double green = static_cast<double>((argb >> 8) & 0xff) / 255.0;
  const double blue = static_cast<double>(argb & 0xff) / 255.0;
  const double luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
  return luminance < 0.5;
}

void SetCaptionColor(HWND window, uint32_t argb) {
  const COLORREF caption_color =
      RGB((argb >> 16) & 0xff, (argb >> 8) & 0xff, argb & 0xff);
  DwmSetWindowAttribute(
      window, static_cast<DWMWINDOWATTRIBUTE>(kDwmwaCaptionColor),
      &caption_color, sizeof(caption_color));

  // Windows uses this flag to choose caption glyph and title contrast.
  const BOOL use_dark_mode = IsDarkColor(argb) ? TRUE : FALSE;
  DwmSetWindowAttribute(
      window, static_cast<DWMWINDOWATTRIBUTE>(kDwmwaUseImmersiveDarkMode),
      &use_dark_mode, sizeof(use_dark_mode));
}

}  // namespace

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  window_chrome_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kWindowChromeChannel,
          &flutter::StandardMethodCodec::GetInstance());
  window_chrome_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "setBackgroundColor") {
          result->NotImplemented();
          return;
        }

        const auto* arguments =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (!arguments) {
          result->Error("invalid_arguments",
                        "setBackgroundColor requires an argument map");
          return;
        }

        const auto color = arguments->find(flutter::EncodableValue("argb"));
        if (color == arguments->end()) {
          result->Error("invalid_arguments", "Missing integer argb value");
          return;
        }

        uint32_t argb;
        if (const auto* value64 = std::get_if<int64_t>(&color->second)) {
          argb = static_cast<uint32_t>(*value64);
        } else if (const auto* value32 =
                       std::get_if<int32_t>(&color->second)) {
          argb = static_cast<uint32_t>(*value32);
        } else {
          result->Error("invalid_arguments", "argb must be an integer");
          return;
        }

        SetCaptionColor(GetHandle(), argb);
        result->Success();
      });

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
  window_chrome_channel_.reset();
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
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
