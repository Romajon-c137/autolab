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
  });

  final String brand;
  final String country;
  final String vin;

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
      ..setBackgroundColor(Colors.white);
    _loadDocument();
  }

  @override
  void didUpdateWidget(covariant DocumentHtmlView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.brand != widget.brand ||
        oldWidget.country != widget.country ||
        oldWidget.vin != widget.vin) {
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
