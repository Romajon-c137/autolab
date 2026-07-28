import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

class DocumentHtmlView extends StatefulWidget {
  const DocumentHtmlView({
    super.key,
    required this.vehicleCategory,
    required this.brand,
    required this.country,
    required this.vin,
    required this.expertName,
    required this.signatureSvg,
    required this.documentStateJson,
    required this.onDocumentStateChanged,
    required this.onSignRequested,
  });

  final String vehicleCategory;
  final String brand;
  final String country;
  final String vin;
  final String expertName;
  final String? signatureSvg;
  final String documentStateJson;
  final ValueChanged<String> onDocumentStateChanged;
  final VoidCallback onSignRequested;

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
      )
      ..addJavaScriptChannel(
        'SignDocument',
        onMessageReceived: (_) {
          widget.onSignRequested();
        },
      );
    _loadDocument();
  }

  @override
  void didUpdateWidget(covariant DocumentHtmlView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vehicleCategory != widget.vehicleCategory ||
        oldWidget.brand != widget.brand ||
        oldWidget.country != widget.country ||
        oldWidget.vin != widget.vin ||
        oldWidget.expertName != widget.expertName ||
        oldWidget.signatureSvg != widget.signatureSvg) {
      _captureCurrentState().then((state) {
        if (mounted) {
          _loadDocument(stateOverride: state);
        }
      });
    }
  }

  @override
  void dispose() {
    _captureCurrentState();
    super.dispose();
  }

  Future<String?> _captureCurrentState() async {
    try {
      final result = await _controller.runJavaScriptReturningResult(
        "window.AutolabCollectDocumentState ? JSON.stringify(window.AutolabCollectDocumentState()) : ''",
      );
      final state = _normalizeJavaScriptString(result);
      if (state.isNotEmpty && state != '{}' && state != 'null') {
        widget.onDocumentStateChanged(state);
        return state;
      }
    } catch (_) {
      // The WebView may already be gone during rotation/dispose.
    }
    return null;
  }

  String _normalizeJavaScriptString(Object result) {
    final raw = result.toString();
    if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
      final decoded = jsonDecode(raw);
      return decoded is String ? decoded : raw;
    }
    return raw;
  }

  Future<void> _loadDocument({String? stateOverride}) async {
    final source = await rootBundle.loadString(
      'assets/${widget.vehicleCategory}_document_clean.html',
    );
    final params = Uri(
      queryParameters: {
        'brand': widget.brand,
        'country': widget.country,
        'vehicle_category': widget.vehicleCategory,
        'vin': widget.vin,
        'expert_name': widget.expertName,
        if (widget.signatureSvg != null) 'signature': widget.signatureSvg!,
        if ((stateOverride ?? widget.documentStateJson).isNotEmpty)
          'state': stateOverride ?? widget.documentStateJson,
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
    if (widget.signatureSvg != null) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) {
        return;
      }
      await _controller.runJavaScript(
        "document.querySelector('.signature-line')?.scrollIntoView({block:'center'});",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
