import 'package:flutter/widgets.dart';

typedef UrlCallback = void Function(String url);
typedef LoadingCallback = void Function(bool isLoading);

abstract class PlatformWebView {
  bool get isInitialized;

  Future<void> initialize({
    required String initialUrl,
    required UrlCallback onUrlChanged,
    required UrlCallback onPageStarted,
    required UrlCallback onPageFinished,
    required LoadingCallback onLoadingChanged,
    ValueChanged<String>? onWebResourceError,
  });

  Future<void> loadUrl(String url);
  Future<void> goBack();
  Future<void> goForward();
  Future<void> reload();
  Future<void> runJavaScript(String script);
  Future<dynamic> runJavaScriptReturningResult(String script);
  Widget buildView();
  Future<void> dispose();
}
