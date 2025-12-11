import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main(List<String> args) {
  if (args.isNotEmpty) {
    final windowId = int.parse(args.first);
    final data = args.length > 1 ? jsonDecode(args[1]) : {};

    runApp(ResultsWindowApp(windowId: windowId, data: data));
  }
}

class ResultsWindowApp extends StatelessWidget {
  final int windowId;
  final Map<String, dynamic> data;

  const ResultsWindowApp({
    super.key,
    required this.windowId,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final elementsList = (data['elements'] as List?)?.map((e) => ElementInfo(
      tag: e['tag'] as String,
      text: e['text'] as String,
      xpath: e['xpath'] as String,
      id: e['id'] as String? ?? '',
      className: e['className'] as String? ?? '',
      name: e['name'] as String? ?? '',
      type: e['type'] as String? ?? '',
      placeholder: e['placeholder'] as String? ?? '',
    )).toList() ?? [];

    final url = data['url'] as String? ?? '';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: ResultsPage(
        elements: elementsList,
        url: url,
      ),
    );
  }
}

class ResultsPage extends StatelessWidget {
  final List<ElementInfo> elements;
  final String url;

  const ResultsPage({
    super.key,
    required this.elements,
    required this.url,
  });

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('클립보드에 복사되었습니다')),
    );
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('XPath 분석 결과'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
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
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    url,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  '총 ${elements.length}개의 요소 발견',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: elements.length,
                itemBuilder: (context, index) {
                  final element = elements[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: ExpansionTile(
                      leading: CircleAvatar(
                        backgroundColor: _getTagColor(element.tag),
                        child: Text(
                          element.tag[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        '${element.tag.toUpperCase()} - ${element.text}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          element.xpath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20.0),
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
                                const SizedBox(height: 8),
                              ],
                              if (element.className.isNotEmpty) ...[
                                _buildInfoRow('Class', element.className),
                                const SizedBox(height: 8),
                              ],
                              if (element.name.isNotEmpty) ...[
                                _buildInfoRow('Name', element.name),
                                const SizedBox(height: 8),
                              ],
                              if (element.type.isNotEmpty) ...[
                                _buildInfoRow('Type', element.type),
                                const SizedBox(height: 8),
                              ],
                              if (element.placeholder.isNotEmpty) ...[
                                _buildInfoRow('Placeholder', element.placeholder),
                                const SizedBox(height: 8),
                              ],
                              const Divider(),
                              const SizedBox(height: 8),
                              const Text(
                                'XPath:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: SelectableText(
                                  element.xpath,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Katalon TestObject:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blueGrey.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.blueGrey.shade200),
                                ),
                                child: SelectableText(
                                  element.katalonCode,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _copyToClipboard(context, element.xpath),
                                    icon: const Icon(Icons.copy, size: 16),
                                    label: const Text('XPath 복사'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () => _copyToClipboard(context, element.katalonCode),
                                    icon: const Icon(Icons.code, size: 16),
                                    label: const Text('Katalon 코드 복사'),
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
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            '$label:',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class ElementInfo {
  final String tag;
  final String text;
  final String xpath;
  final String id;
  final String className;
  final String name;
  final String type;
  final String placeholder;

  ElementInfo({
    required this.tag,
    required this.text,
    required this.xpath,
    this.id = '',
    this.className = '',
    this.name = '',
    this.type = '',
    this.placeholder = '',
  });

  String get katalonCode {
    final objectName = '${tag}_${text.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase()}';
    return '''TestObject $objectName = new TestObject("$objectName")
$objectName.addProperty("xpath", ConditionType.EQUALS, "$xpath")

// 사용 예시:
WebUI.click($objectName)''';
  }
}
