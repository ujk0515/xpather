import 'dart:io' show Platform;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:window_manager/window_manager.dart';
import 'platform_webview/platform_webview.dart';
import 'results_window.dart' show ElementInfo;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  runApp(const XpatherApp());
}

class XpatherApp extends StatelessWidget {
  const XpatherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XPather - XPath Generator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        fontFamily: _getPlatformFont(),
      ),
      home: const BrowserPage(),
    );
  }

  String? _getPlatformFont() {
    if (kIsWeb) return null;
    if (Platform.isMacOS) return 'SF Pro Display';
    if (Platform.isWindows) return 'Segoe UI';
    return null;
  }
}

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  late final PlatformWebView _webView;
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFocusNode = FocusNode();
  bool _isLoading = true;
  String _currentUrl = 'https://www.google.com';
  bool _isInitialized = false;
  List<ElementInfo>? _analysisResults;
  bool _showResults = false;
  double _mouseX = 0;
  double _mouseY = 0;
  bool _isCustomXPathMode = false; // 커스텀 XPath 모드 여부
  final List<ElementInfo> _customExtractedElements = []; // 커스텀 모드에서 추출된 요소들
  Timer? _extractionTimer; // 요소 추출 확인 타이머

  @override
  void initState() {
    super.initState();
    _urlController.text = _currentUrl;
    _webView = createPlatformWebView();
    _initWebView();
    _startExtractionTimer();
  }

  void _startExtractionTimer() {
    _extractionTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!_isCustomXPathMode || !_isInitialized) return;

      try {
        final result = await _runJavaScriptReturningResult('window.xpatherGetExtracted()');

        if (result == null) return;

        Map<String, dynamic>? data;

        if (result is Map<Object?, Object?>) {
          // webview_windows 등에서는 JS 객체가 Map으로 전달됨
          data = {};
          result.forEach((key, value) {
            if (key != null) {
              data![key.toString()] = value;
            }
          });
        } else if (result is String) {
          final trimmed = result.trim();
          if (trimmed.isEmpty || trimmed == 'null') {
            return;
          }
          try {
            final decoded = jsonDecode(trimmed);
            if (decoded is Map) {
              data = decoded.map((key, value) => MapEntry(key.toString(), value));
            } else {
              return;
            }
          } catch (_) {
            // macOS의 WKWebView는 문자열을 반환하므로 JSON 변환 실패 시 무시
            return;
          }
        } else {
          return;
        }

        // className이 객체일 수 있으므로 문자열로 변환
        String className = '';
        if (data['className'] != null) {
          if (data['className'] is String) {
            className = data['className'];
          } else {
            className = data['className'].toString();
          }
        }

        final elementInfo = ElementInfo(
          tag: data['tag']?.toString() ?? '',
          text: data['text']?.toString() ?? '',
          xpath: data['xpath']?.toString() ?? '',
          id: data['id']?.toString() ?? '',
          className: className,
          name: data['name']?.toString() ?? '',
          type: data['type']?.toString() ?? '',
          placeholder: data['placeholder']?.toString() ?? '',
        );

        // 중복 체크: 이미 같은 xpath가 있으면 무시
        final isDuplicate = _customExtractedElements.any((e) => e.xpath == elementInfo.xpath);

        if (!isDuplicate) {
          setState(() {
            _customExtractedElements.add(elementInfo);
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('요소 추출됨: ${elementInfo.tag}'),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        }
      } catch (e) {
        // 에러 무시 (null 반환 시)
      }
    });
  }

  Future<void> _injectScripts() async {
    try {
      await _runJavaScript('''
        window.eleCanScroll = function(ele) {
          if (!ele) return document.documentElement;
          if (ele.scrollTop > 0) {
            return ele;
          } else {
            ele.scrollTop++;
            const top = ele.scrollTop;
            top && (ele.scrollTop = 0);
            if(top > 0){
              return ele;
            }else{
              return window.eleCanScroll(ele.parentElement);
            }
          }
        };

        // XPath 생성 함수
        window.generateXPath = function(element) {
          if (!element) return '';

          const parts = [];
          let current = element;

          while (current && current.nodeType === Node.ELEMENT_NODE) {
            const tag = current.tagName.toLowerCase();
            const parent = current.parentElement;

            if (!parent) {
              parts.unshift(tag);
              break;
            }

            let index = 1;
            for (let sibling of parent.children) {
              if (sibling === current) break;
              if (sibling.tagName === current.tagName) index++;
            }

            const sameTagCount = Array.from(parent.children).filter(e => e.tagName === current.tagName).length;
            if (sameTagCount > 1) {
              parts.unshift(tag + '[' + index + ']');
            } else {
              parts.unshift(tag);
            }

            current = parent;
          }

          return '/' + parts.join('/');
        };

        // 요소 정보 추출 함수
        window.extractElementInfo = function(element) {
          const text = element.textContent ? element.textContent.trim() : '';
          const placeholder = element.getAttribute('placeholder') || '';

          let displayText;
          if (text.length > 0) {
            displayText = text.substring(0, 200);
          } else if (placeholder.length > 0) {
            displayText = placeholder;
          } else {
            displayText = '(텍스트 없음)';
          }

          return {
            tag: element.tagName.toLowerCase(),
            text: displayText,
            xpath: window.generateXPath(element),
            id: element.id || '',
            className: element.className || '',
            name: element.getAttribute('name') || '',
            type: element.getAttribute('type') || '',
            placeholder: placeholder
          };
        };

        // 커스텀 XPath 모드 상태
        window.xpatherCustomMode = false;
        window.xpatherCurrentHighlight = null;

        // 호버 이벤트 핸들러
        window.xpatherMouseOver = function(e) {
          if (!window.xpatherCustomMode) return;

          // 마우스 실제 위치의 요소 찾기
          const x = e.clientX;
          const y = e.clientY;

          // 이전 오버레이 임시 숨기기
          const prevOverlay = window.xpatherCurrentHighlight;
          if (prevOverlay) prevOverlay.style.display = 'none';

          // 실제 요소 찾기
          const element = document.elementFromPoint(x, y);

          // 이전 오버레이 제거
          if (prevOverlay) prevOverlay.remove();

          if (!element || element.tagName === 'HTML' || element.tagName === 'BODY') {
            window.xpatherCurrentHighlight = null;
            return;
          }

          const rect = element.getBoundingClientRect();
          const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
          const scrollLeft = window.pageXOffset || document.documentElement.scrollLeft;

          // 새 하이라이트 생성
          const overlay = document.createElement('div');
          overlay.id = 'xpather-hover-overlay';
          overlay.style.position = 'absolute';
          overlay.style.top = (rect.top + scrollTop) + 'px';
          overlay.style.left = (rect.left + scrollLeft) + 'px';
          overlay.style.width = rect.width + 'px';
          overlay.style.height = rect.height + 'px';
          overlay.style.backgroundColor = 'rgba(240, 128, 128, 0.5)';
          overlay.style.border = '2px solid #F08080';
          overlay.style.pointerEvents = 'none';
          overlay.style.zIndex = '999999';
          overlay.style.boxSizing = 'border-box';

          document.body.appendChild(overlay);
          window.xpatherCurrentHighlight = overlay;
        };

        // 추출된 요소를 저장할 큐
        window.xpatherExtractedQueue = [];

        // mousedown 핸들러 - XPath 추출 (disabled 요소도 캡처)
        window.xpatherMouseDown = function(e) {
          if (!window.xpatherCustomMode) return;

          e.preventDefault();
          e.stopPropagation();

          // 마우스 실제 위치의 요소 찾기 (오버레이 무시)
          const x = e.clientX;
          const y = e.clientY;

          // 오버레이 임시 숨기기
          const overlay = window.xpatherCurrentHighlight;
          if (overlay) overlay.style.display = 'none';

          // 실제 요소 찾기
          const element = document.elementFromPoint(x, y);

          // 오버레이 복구
          if (overlay) overlay.style.display = '';

          if (!element) return false;

          const elementInfo = window.extractElementInfo(element);
          window.xpatherExtractedQueue.push(elementInfo);

          return false;
        };

        // click 핸들러 - 기본 동작만 차단 (드롭다운 등)
        window.xpatherClickBlock = function(e) {
          if (!window.xpatherCustomMode) return;

          e.preventDefault();
          e.stopPropagation();
          return false;
        };

        // 큐에서 요소를 꺼내는 함수
        window.xpatherGetExtracted = function() {
          if (window.xpatherExtractedQueue.length > 0) {
            const item = window.xpatherExtractedQueue.shift();
            try {
              return JSON.stringify(item);
            } catch (e) {
              return null;
            }
          }
          return null;
        };

        // 이벤트 리스너 중복 등록 방지
        if (!window.xpatherListenersRegistered) {
          document.addEventListener('mouseover', window.xpatherMouseOver, true);
          document.addEventListener('mousedown', window.xpatherMouseDown, true);
          document.addEventListener('click', window.xpatherClickBlock, true);
          window.xpatherListenersRegistered = true;
        }
      ''');
    } catch (e) {
      debugPrint('스크립트 주입 오류: $e');
    }
  }

  Future<void> _initWebView() async {
    try {
      await _webView.initialize(
        initialUrl: _currentUrl,
        onUrlChanged: _handleUrlChanged,
        onPageStarted: (url) {
          if (!mounted) return;
          setState(() {
            _isLoading = true;
          });
        },
        onPageFinished: (url) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _isInitialized = true;
          });
          Future.delayed(const Duration(milliseconds: 500), () {
            _injectScripts();
          });
        },
        onLoadingChanged: (loading) {
          if (!mounted) return;
          setState(() {
            _isLoading = loading;
            if (!_isInitialized && !loading) {
              _isInitialized = true;
            }
          });
        },
        onWebResourceError: (message) {
          if (message.trim().isNotEmpty) {
            debugPrint('WebView 오류: $message');
          }
        },
      );

      if (!mounted) return;
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      debugPrint('WebView 초기화 오류: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _runJavaScript(String script) async {
    if (!_isInitialized) return;
    try {
      await _webView.runJavaScript(script);
    } catch (e) {
      debugPrint('JavaScript 실행 오류: $e');
    }
  }

  Future<dynamic> _runJavaScriptReturningResult(String script) async {
    if (!_isInitialized) return null;
    try {
      return await _webView.runJavaScriptReturningResult(script);
    } catch (e) {
      debugPrint('JavaScript 결과 요청 오류: $e');
      return null;
    }
  }

  Future<void> _goBack() async {
    if (!_isInitialized) return;
    await _webView.goBack();
  }

  Future<void> _goForward() async {
    if (!_isInitialized) return;
    await _webView.goForward();
  }

  Future<void> _reload() async {
    if (!_isInitialized) return;
    await _webView.reload();
  }

  Widget _buildWebViewWidget() {
    if (!_webView.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return _webView.buildView();
  }

  @override
  void dispose() {
    _extractionTimer?.cancel();
    _urlController.dispose();
    _urlFocusNode.dispose();
    unawaited(_webView.dispose());
    super.dispose();
  }

  void _loadUrl() async {
    if (!_isInitialized) {
      debugPrint('WebView가 아직 초기화되지 않았습니다.');
      return;
    }

    final url = _urlController.text.trim();
    if (url.isNotEmpty) {
      String finalUrl = url;
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        finalUrl = 'https://$url';
      }
      setState(() {
        _isLoading = true;
      });
      _urlFocusNode.unfocus();
      await _webView.loadUrl(finalUrl);
      setState(() {
        _currentUrl = finalUrl;
      });
    }
  }

  Future<void> _analyzeCurrentPage() async {
    try {
      // 기존 리스트 먼저 삭제
      setState(() {
        _analysisResults = null;
      });

      final html = await _runJavaScriptReturningResult('document.documentElement.outerHTML');

      // runJavaScriptReturningResult는 문자열을 String으로 반환
      String htmlString = html.toString();
      // 혹시 양 끝에 따옴표가 있으면 제거
      if (htmlString.startsWith('"') && htmlString.endsWith('"')) {
        htmlString = htmlString.substring(1, htmlString.length - 1);
        // 이스케이프 문자 복원
        htmlString = htmlString
            .replaceAll(r'\"', '"')
            .replaceAll(r'\\', '\\')
            .replaceAll(r'\n', '\n')
            .replaceAll(r'\r', '\r')
            .replaceAll(r'\t', '\t');
      }

      final document = html_parser.parse(htmlString);
      final elements = _extractElements(document);

      if (!mounted) return;

      setState(() {
        _analysisResults = elements;
        _showResults = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('분석 오류: $e')),
      );
    }
  }

  void _closeResults() {
    setState(() {
      _showResults = false;
      _analysisResults = null;
    });
    _toggleCustomXPathMode(false);
  }

  void _toggleCustomXPathMode(bool enabled) async {
    setState(() {
      _isCustomXPathMode = enabled;
    });

    if (!_isInitialized) return;

    try {
      await _runJavaScript('''
        console.log('Setting xpatherCustomMode to: $enabled');
        window.xpatherCustomMode = $enabled;

        // 하이라이트 제거
        if (window.xpatherCurrentHighlight) {
          window.xpatherCurrentHighlight.remove();
          window.xpatherCurrentHighlight = null;
        }

        // 마우스 커서 변경
        if ($enabled) {
          document.body.style.cursor = 'default';
          document.documentElement.style.cursor = 'default';
          const style = document.createElement('style');
          style.id = 'xpather-cursor-style';
          style.textContent = '* { cursor: default !important; } #xpather-hover-overlay, #xpather-highlight-overlay { pointer-events: none !important; }';
          document.head.appendChild(style);
        } else {
          document.body.style.cursor = '';
          document.documentElement.style.cursor = '';
          const style = document.getElementById('xpather-cursor-style');
          if (style) style.remove();
        }

      ''');
    } catch (e) {
      debugPrint('모드 전환 오류: $e');
    }
  }

  void _onTabChanged(int tabIndex) async {
    // tabIndex 0: 자동 분석, 1: 커스텀 XPath
    _toggleCustomXPathMode(tabIndex == 1);
  }

  void _handleUrlChanged(String url) {
    if (!mounted) return;
    setState(() {
      _currentUrl = url;
      if (!_urlFocusNode.hasFocus) {
        _urlController.value = TextEditingValue(
          text: url,
          selection: TextSelection.collapsed(offset: url.length),
        );
      }
    });
  }

  List<ElementInfo> _extractElements(dom.Document document) {
    final List<ElementInfo> elements = [];
    final targetTags = ['button', 'a', 'input', 'select', 'textarea'];

    void traverse(dom.Element element) {
      if (targetTags.contains(element.localName)) {
        final xpath = _generateFullXPath(element);
        final text = element.text.trim();
        final id = element.attributes['id'] ?? '';
        final className = element.attributes['class'] ?? '';
        final name = element.attributes['name'] ?? '';
        final type = element.attributes['type'] ?? '';
        final placeholder = element.attributes['placeholder'] ?? '';

        // 표시할 텍스트 결정: 텍스트 > placeholder > (텍스트 없음)
        String displayText;
        if (text.isNotEmpty) {
          displayText = text;
        } else if (placeholder.isNotEmpty) {
          displayText = placeholder;
        } else {
          displayText = '(텍스트 없음)';
        }

        final elementInfo = ElementInfo(
          tag: element.localName!,
          text: displayText,
          xpath: xpath,
          id: id,
          className: className,
          name: name,
          type: type,
          placeholder: placeholder,
        );
        elements.add(elementInfo);
      }

      for (var child in element.children) {
        traverse(child);
      }
    }

    final body = document.body;
    if (body != null) {
      traverse(body);
    }

    return elements;
  }

  String _generateFullXPath(dom.Element element) {
    final List<String> parts = [];
    dom.Node? current = element;

    while (current != null && current is dom.Element) {
      final tag = current.localName!;
      final parent = current.parent;

      if (parent == null) {
        parts.insert(0, tag);
        break;
      }

      int index = 1;
      for (var sibling in parent.children) {
        if (sibling == current) {
          break;
        }
        if (sibling.localName == tag) {
          index++;
        }
      }

      final sameTagCount = parent.children.where((e) => e.localName == tag).length;
      if (sameTagCount > 1) {
        parts.insert(0, '$tag[$index]');
      } else {
        parts.insert(0, tag);
      }

      current = parent;
    }

    return '/${parts.join('/')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('XPather Browser'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _goBack,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _goForward,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _reload,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    focusNode: _urlFocusNode,
                    decoration: InputDecoration(
                      hintText: 'URL 입력',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      prefixIcon: const Icon(Icons.lock, size: 18),
                    ),
                    onSubmitted: (_) => _loadUrl(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _loadUrl,
                  tooltip: '이동',
                ),
              ],
            ),
          ),
        ),
      ),
      body: Row(
        children: [
          // Browser view (left side)
          Expanded(
            flex: _showResults ? 2 : 3,
            child: Listener(
              onPointerHover: (event) {
                _mouseX = event.localPosition.dx;
                _mouseY = event.localPosition.dy;
              },
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  _runJavaScript('''
                    (function() {
                      var el = document.elementFromPoint($_mouseX, $_mouseY);
                      var el2 = window.eleCanScroll(el);
                      if (el2) {
                        el2.scrollTop += ${event.scrollDelta.dy};
                      }
                    })();
                  ''');
                }
              },
              child: Focus(
                autofocus: true,
                child: Stack(
                  children: [
                    _buildWebViewWidget(),
                    if (_isLoading)
                      const Center(
                        child: CircularProgressIndicator(),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Results panel (right side)
          if (_showResults && _analysisResults != null)
            Expanded(
              flex: 1,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: Colors.grey.shade300, width: 1),
                  ),
                ),
                child: Column(
                  children: [
                    // Results header with close button
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.inversePrimary,
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade300, width: 1),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.analytics),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'XPath 분석 결과',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: _closeResults,
                            tooltip: '닫기',
                          ),
                        ],
                      ),
                    ),
                    // Results content
                    Expanded(
                      child: _ResultsPanel(
                        elements: _analysisResults!,
                        url: _currentUrl,
                        onRunJavaScript: _runJavaScript,
                        onRunJavaScriptReturningResult: _runJavaScriptReturningResult,
                        onTabChanged: _onTabChanged,
                        customExtractedElements: _customExtractedElements,
                        onClearCustomElements: () {
                          setState(() {
                            _customExtractedElements.clear();
                          });
                          // 하이라이트도 제거
                          _runJavaScript('''
                            if (window.xpatherCurrentHighlight) {
                              window.xpatherCurrentHighlight.remove();
                              window.xpatherCurrentHighlight = null;
                            }
                            const prevHighlight = document.getElementById('xpather-highlight-overlay');
                            if (prevHighlight) {
                              prevHighlight.remove();
                            }
                          ''');
                        },
                        onRefreshAnalysis: _analyzeCurrentPage,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: !_showResults
          ? FloatingActionButton.extended(
              onPressed: _analyzeCurrentPage,
              icon: const Icon(Icons.search),
              label: const Text('XPath 분석'),
              tooltip: '현재 페이지의 XPath 분석',
            )
          : null,
    );
  }
}

class _ResultsPanel extends StatefulWidget {
  final List<ElementInfo> elements;
  final String url;
  final Future<void> Function(String script) onRunJavaScript;
  final Future<dynamic> Function(String script) onRunJavaScriptReturningResult;
  final Function(int) onTabChanged;
  final List<ElementInfo> customExtractedElements;
  final VoidCallback onClearCustomElements;
  final VoidCallback? onRefreshAnalysis;

  const _ResultsPanel({
    required this.elements,
    required this.url,
    required this.onRunJavaScript,
    required this.onRunJavaScriptReturningResult,
    required this.onTabChanged,
    required this.customExtractedElements,
    required this.onClearCustomElements,
    this.onRefreshAnalysis,
  });

  @override
  State<_ResultsPanel> createState() => _ResultsPanelState();
}

class _ResultsPanelState extends State<_ResultsPanel> with SingleTickerProviderStateMixin {
  int? _expandedIndex;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabControllerChanged);
  }

  void _onTabControllerChanged() {
    if (_tabController.indexIsChanging) return;
    widget.onTabChanged(_tabController.index);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('클립보드에 복사되었습니다')),
    );
  }

  Future<void> _highlightElement(String xpath) async {
    // XPath에서 작은따옴표 이스케이프 처리
    final escapedXpath = xpath.replaceAll("'", "\\'");

    final script = '''
      (function() {
        // 이전 하이라이트 제거
        const prevHighlight = document.getElementById('xpather-highlight-overlay');
        if (prevHighlight) {
          prevHighlight.remove();
        }

        // XPath로 요소 찾기
        function getElementByXPath(xpath) {
          return document.evaluate(xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
        }

        const element = getElementByXPath('$escapedXpath');
        if (!element) {
          console.log('요소를 찾을 수 없음: $escapedXpath');
          return 'NOT_FOUND';
        }

        // 요소 위치 가져오기
        const rect = element.getBoundingClientRect();
        const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
        const scrollLeft = window.pageXOffset || document.documentElement.scrollLeft;

        // 오버레이 생성
        const overlay = document.createElement('div');
        overlay.id = 'xpather-highlight-overlay';
        overlay.style.position = 'absolute';
        overlay.style.top = (rect.top + scrollTop) + 'px';
        overlay.style.left = (rect.left + scrollLeft) + 'px';
        overlay.style.width = rect.width + 'px';
        overlay.style.height = rect.height + 'px';
        overlay.style.backgroundColor = 'rgba(240, 128, 128, 0.5)';
        overlay.style.border = '2px solid #F08080';
        overlay.style.pointerEvents = 'none';
        overlay.style.zIndex = '999999';
        overlay.style.boxSizing = 'border-box';

        document.body.appendChild(overlay);

        // 요소로 스크롤
        element.scrollIntoView({ behavior: 'smooth', block: 'center' });

        return 'SUCCESS';
      })();
    ''';

    try {
      final result = await widget.onRunJavaScriptReturningResult(script);
      if (result.toString() == 'NOT_FOUND') {
        debugPrint('요소를 찾을 수 없음: $xpath');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('요소를 찾을 수 없습니다. XPath가 유효하지 않을 수 있습니다.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('하이라이트 오류: $e');
    }
  }

  Future<void> _clearHighlight() async {
    final script = '''
      (function() {
        const prevHighlight = document.getElementById('xpather-highlight-overlay');
        if (prevHighlight) {
          prevHighlight.remove();
        }
      })();
    ''';

    try {
      await widget.onRunJavaScript(script);
    } catch (e) {
      debugPrint('하이라이트 제거 오류: $e');
    }
  }

  Color _getTagColor(String tag) {
    switch (tag.toLowerCase()) {
      case 'button':
        return Colors.blue;
      case 'a':
        return Colors.purple;
      case 'input':
        return Colors.green;
      case 'select':
        return Colors.orange;
      case 'textarea':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab Bar
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: Colors.blue.shade700,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.blue.shade700,
            tabs: const [
              Tab(text: '자동 분석'),
              Tab(text: '커스텀 XPath'),
            ],
          ),
        ),
        // Tab Bar View
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // 첫 번째 탭: 자동 분석 결과
              _buildAutoAnalysisTab(),
              // 두 번째 탭: 커스텀 XPath
              _buildCustomXPathTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAutoAnalysisTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '분석 URL:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.url,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade700, size: 16),
              const SizedBox(width: 8),
              Text(
                '총 ${widget.elements.length}개의 요소 발견',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () {
                  // 부모 위젯의 분석 함수 호출
                  widget.onRefreshAnalysis?.call();
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('새로고침', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: widget.elements.length,
              itemBuilder: (context, index) {
                final element = widget.elements[index];
                final isExpanded = _expandedIndex == index;
                return Card(
                  key: ValueKey('card_${index}_${isExpanded ? 'expanded' : 'collapsed'}'),
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: ExpansionTile(
                    initiallyExpanded: isExpanded,
                    onExpansionChanged: (expanded) {
                      if (expanded) {
                        setState(() {
                          _expandedIndex = index;
                        });
                        _highlightElement(element.xpath);
                      } else {
                        setState(() {
                          _expandedIndex = null;
                        });
                        _clearHighlight();
                      }
                    },
                    leading: CircleAvatar(
                      backgroundColor: _getTagColor(element.tag),
                      radius: 16,
                      child: Text(
                        element.tag[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    title: Text(
                      '${element.tag.toUpperCase()} - ${element.text}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        element.xpath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          border: Border(
                            top: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (element.id.isNotEmpty) ...[
                              _buildInfoRow('ID', element.id),
                              const SizedBox(height: 6),
                            ],
                            if (element.className.isNotEmpty) ...[
                              _buildInfoRow('Class', element.className),
                              const SizedBox(height: 6),
                            ],
                            if (element.name.isNotEmpty) ...[
                              _buildInfoRow('Name', element.name),
                              const SizedBox(height: 6),
                            ],
                            if (element.type.isNotEmpty) ...[
                              _buildInfoRow('Type', element.type),
                              const SizedBox(height: 6),
                            ],
                            if (element.placeholder.isNotEmpty) ...[
                              _buildInfoRow('Placeholder', element.placeholder),
                              const SizedBox(height: 6),
                            ],
                            const Divider(),
                            const SizedBox(height: 8),
                            const Text(
                              'XPath:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: SelectableText(
                                element.xpath,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Katalon TestObject:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.blueGrey.shade200),
                              ),
                              child: SelectableText(
                                element.katalonCode,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _copyToClipboard(context, element.xpath),
                                  icon: const Icon(Icons.copy, size: 14),
                                  label: const Text('XPath 복사', style: TextStyle(fontSize: 11)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                ElevatedButton.icon(
                                  onPressed: () => _copyToClipboard(context, element.katalonCode),
                                  icon: const Icon(Icons.code, size: 14),
                                  label: const Text('Katalon 코드 복사', style: TextStyle(fontSize: 11)),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomXPathTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 안내 메시지
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.purple.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.touch_app, color: Colors.purple.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '웹페이지의 요소를 클릭하여 XPath를 추출하세요',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.purple.shade700,
                    ),
                  ),
                ),
                if (widget.customExtractedElements.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () {
                      // 아코디언 닫기
                      setState(() {
                        _expandedIndex = null;
                      });
                      // 하이라이트 제거
                      _clearHighlight();
                      // 리스트 삭제
                      widget.onClearCustomElements();
                    },
                    icon: const Icon(Icons.clear_all, size: 14),
                    label: const Text('전체 삭제', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 추출된 요소 개수
          if (widget.customExtractedElements.isNotEmpty)
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade700, size: 16),
                const SizedBox(width: 8),
                Text(
                  '총 ${widget.customExtractedElements.length}개의 요소 추출됨',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          if (widget.customExtractedElements.isNotEmpty)
            const SizedBox(height: 12),
          // 결과 영역
          Expanded(
            child: widget.customExtractedElements.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.touch_app, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          '웹페이지의 요소를 클릭하세요',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: widget.customExtractedElements.length,
                    itemBuilder: (context, index) {
                      final element = widget.customExtractedElements[index];
                      final isExpanded = _expandedIndex == index;
                      return Card(
                        key: ValueKey('custom_card_${index}_${isExpanded ? 'expanded' : 'collapsed'}'),
                        margin: const EdgeInsets.only(bottom: 8),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: ExpansionTile(
                          initiallyExpanded: isExpanded,
                          onExpansionChanged: (expanded) {
                            if (expanded) {
                              setState(() {
                                _expandedIndex = index;
                              });
                              _highlightElement(element.xpath);
                            } else {
                              setState(() {
                                _expandedIndex = null;
                              });
                              _clearHighlight();
                            }
                          },
                          leading: CircleAvatar(
                            backgroundColor: Colors.purple.shade600,
                            radius: 16,
                            child: Text(
                              element.tag[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          title: Text(
                            '${element.tag.toUpperCase()} - ${element.text}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              element.xpath,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16.0),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                border: Border(
                                  top: BorderSide(color: Colors.grey.shade200),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (element.id.isNotEmpty) ...[
                                    _buildInfoRow('ID', element.id),
                                    const SizedBox(height: 6),
                                  ],
                                  if (element.className.isNotEmpty) ...[
                                    _buildInfoRow('Class', element.className),
                                    const SizedBox(height: 6),
                                  ],
                                  if (element.name.isNotEmpty) ...[
                                    _buildInfoRow('Name', element.name),
                                    const SizedBox(height: 6),
                                  ],
                                  if (element.type.isNotEmpty) ...[
                                    _buildInfoRow('Type', element.type),
                                    const SizedBox(height: 6),
                                  ],
                                  if (element.placeholder.isNotEmpty) ...[
                                    _buildInfoRow('Placeholder', element.placeholder),
                                    const SizedBox(height: 6),
                                  ],
                                  const Divider(),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'XPath:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.grey.shade300),
                                    ),
                                    child: SelectableText(
                                      element.xpath,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () => _copyToClipboard(context, element.xpath),
                                        icon: const Icon(Icons.copy, size: 14),
                                        label: const Text('XPath 복사', style: TextStyle(fontSize: 11)),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}
