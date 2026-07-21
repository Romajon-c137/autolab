import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

class DocumentHtmlView extends StatefulWidget {
  const DocumentHtmlView({
    super.key,
    required this.brand,
    required this.country,
    required this.vin,
    required this.signatureSvg,
    required this.documentStateJson,
    required this.onDocumentStateChanged,
  });

  final String brand;
  final String country;
  final String vin;
  final String? signatureSvg;
  final String documentStateJson;
  final ValueChanged<String> onDocumentStateChanged;

  @override
  State<DocumentHtmlView> createState() => _DocumentHtmlViewState();
}

class _DocumentHtmlViewState extends State<DocumentHtmlView> {
  late final WebViewController _controller;
  String? _lastHtml;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel(
        'DocumentState',
        onMessageReceived: (message) {
          widget.onDocumentStateChanged(message.message);
        },
      );
    _loadDocument();
  }

  @override
  void didUpdateWidget(covariant DocumentHtmlView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.brand != widget.brand ||
        oldWidget.country != widget.country ||
        oldWidget.vin != widget.vin ||
        oldWidget.signatureSvg != widget.signatureSvg) {
      _loadDocument();
    }
  }

  Future<void> _loadDocument() async {
    final source = await rootBundle.loadString('assets/M1_document_clean.html');
    final params = Uri(
      queryParameters: {
        'brand': widget.brand,
        'country': widget.country,
        'vin': widget.vin,
        if (widget.signatureSvg != null) 'signature': widget.signatureSvg!,
        if (widget.documentStateJson.isNotEmpty)
          'state': widget.documentStateJson,
      },
    ).query;
    final html = source.replaceFirst(
      'new URLSearchParams(window.location.search)',
      'new URLSearchParams(${jsonEncode(params)})',
    );

    if (!mounted || html == _lastHtml) {
      return;
    }

    _lastHtml = html;
    await _controller.loadHtmlString(html);
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
