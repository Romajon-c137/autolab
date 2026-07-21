import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

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
  static int _nextId = 0;
  late final String _viewType;
  web.HTMLIFrameElement? _iframe;

  String get _documentUrl {
    return Uri(
      path: '/M1_document_clean.html',
      queryParameters: {
        'brand': widget.brand,
        'country': widget.country,
        'vin': widget.vin,
      },
    ).toString();
  }

  @override
  void initState() {
    super.initState();
    _viewType = 'm1-document-html-${_nextId++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = web.HTMLIFrameElement()..src = _documentUrl;
      iframe.style
        ..setProperty('width', '100%')
        ..setProperty('height', '100%')
        ..setProperty('border', '0')
        ..setProperty('background', 'white');
      _iframe = iframe;
      return iframe;
    });
  }

  @override
  void didUpdateWidget(covariant DocumentHtmlView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.brand != widget.brand ||
        oldWidget.country != widget.country ||
        oldWidget.vin != widget.vin) {
      _iframe?.src = _documentUrl;
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
