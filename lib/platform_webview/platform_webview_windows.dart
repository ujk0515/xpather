import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart' as windows_webview;

import 'platform_webview_base.dart';

class WindowsPlatformWebView implements PlatformWebView {
  final windows_webview.WebviewController _controller =
      windows_webview.WebviewController();
  final List<StreamSubscription> _subscriptions = [];
  bool _initialized = false;
  String _currentUrl = '';

  @override
  bool get isInitialized =>
      _initialized && _controller.value.isInitialized;

  @override
  Future<void> initialize({
    required String initialUrl,
    required UrlCallback onUrlChanged,
    required UrlCallback onPageStarted,
    required UrlCallback onPageFinished,
    required LoadingCallback onLoadingChanged,
    ValueChanged<String>? onWebResourceError,
  }) async {
    try {
      await _controller.initialize();
      _subscriptions.add(_controller.url.listen((url) {
        _currentUrl = url;
        onUrlChanged(url);
      }));
      _subscriptions.add(_controller.loadingState.listen((state) {
        final isLoading = state == windows_webview.LoadingState.loading;
        onLoadingChanged(isLoading);
        if (state == windows_webview.LoadingState.loading) {
          onPageStarted(_currentUrl);
        } else if (state ==
            windows_webview.LoadingState.navigationCompleted) {
          onPageFinished(_currentUrl);
        }
      }));

      await _controller.setBackgroundColor(Colors.transparent);
      await _controller.setPopupWindowPolicy(
        windows_webview.WebviewPopupWindowPolicy.deny,
      );

      _initialized = true;
      onLoadingChanged(true);
      await _controller.loadUrl(initialUrl);
    } catch (e) {
      onWebResourceError?.call(e.toString());
      rethrow;
    }
  }

  @override
  Widget buildView() {
    if (!isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return windows_webview.Webview(_controller);
  }

  @override
  Future<void> loadUrl(String url) async {
    if (!isInitialized) return;
    await _controller.loadUrl(url);
  }

  @override
  Future<void> goBack() async {
    if (!isInitialized) return;
    await _controller.goBack();
  }

  @override
  Future<void> goForward() async {
    if (!isInitialized) return;
    await _controller.goForward();
  }

  @override
  Future<void> reload() async {
    if (!isInitialized) return;
    await _controller.reload();
  }

  @override
  Future<void> runJavaScript(String script) async {
    if (!isInitialized) return;
    await _controller.executeScript(script);
  }

  @override
  Future<dynamic> runJavaScriptReturningResult(String script) async {
    if (!isInitialized) return null;
    return _controller.executeScript(script);
  }

  @override
  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await _controller.dispose();
    _initialized = false;
  }
}
