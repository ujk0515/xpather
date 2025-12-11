import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'platform_webview_base.dart';

class DefaultPlatformWebView implements PlatformWebView {
  WebViewController? _controller;
  bool _initialized = false;

  @override
  bool get isInitialized => _initialized && _controller != null;

  @override
  Future<void> initialize({
    required String initialUrl,
    required UrlCallback onUrlChanged,
    required UrlCallback onPageStarted,
    required UrlCallback onPageFinished,
    required LoadingCallback onLoadingChanged,
    ValueChanged<String>? onWebResourceError,
  }) async {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            onLoadingChanged(true);
            onUrlChanged(url);
            onPageStarted(url);
          },
          onPageFinished: (url) {
            onLoadingChanged(false);
            onUrlChanged(url);
            onPageFinished(url);
          },
          onWebResourceError: (WebResourceError error) {
            onLoadingChanged(false);
            onWebResourceError?.call(error.description);
          },
        ),
      );

    _controller = controller;
    _initialized = true;
    onLoadingChanged(true);
    await controller.loadRequest(Uri.parse(initialUrl));
  }

  @override
  Future<void> dispose() async {
    _controller = null;
    _initialized = false;
  }

  @override
  Widget buildView() {
    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return WebViewWidget(controller: controller);
  }

  @override
  Future<void> goBack() async {
    await _controller?.goBack();
  }

  @override
  Future<void> goForward() async {
    await _controller?.goForward();
  }

  @override
  Future<void> reload() async {
    await _controller?.reload();
  }

  @override
  Future<void> loadUrl(String url) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.loadRequest(Uri.parse(url));
  }

  @override
  Future<void> runJavaScript(String script) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.runJavaScript(script);
  }

  @override
  Future<dynamic> runJavaScriptReturningResult(String script) async {
    final controller = _controller;
    if (controller == null) return null;
    return controller.runJavaScriptReturningResult(script);
  }
}
