import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'platform_webview_base.dart';
import 'platform_webview_default.dart';
import 'platform_webview_windows.dart';

PlatformWebView createPlatformWebView() {
  if (!kIsWeb && Platform.isWindows) {
    return WindowsPlatformWebView();
  }
  return DefaultPlatformWebView();
}

export 'platform_webview_base.dart';
