#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(400, 400); // Poziția inițială
  Win32Window::Size size(600, 600);   // Dimensiunea inițială
  Win32Window::Size min_size(300, 200); // Dimensiunea minimă
  Win32Window::Size max_size(600, 600); // Dimensiunea maximă
  if (!window.Create(L"Chat Social", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  // // Dezactivează redimensionarea
  // HWND hwnd = window.GetHandle();
  // LONG style = GetWindowLong(hwnd, GWL_STYLE);
  // style &= ~WS_SIZEBOX; // Elimină stilul de redimensionare
  // SetWindowLong(hwnd, GWL_STYLE, style);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
