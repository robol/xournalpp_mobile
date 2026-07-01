#include "flutter_window.h"

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

void FlutterWindow::OnCreate() {
  Win32Window::OnCreate();

  // The size here is arbitrary since SetChildContent will resize it.
  flutter_controller_ =
      std::make_unique<flutter::FlutterViewController>(100, 100, project_);
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
}

void FlutterWindow::OnDestroy() {
  flutter_controller_ = nullptr;

  Win32Window::OnDestroy();
}
