import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

class DocumentHtmlView extends StatefulWidget {
  const DocumentHtmlView({
    super.key,
    required this.operationType,
    required this.vehicleCategory,
    required this.brand,
    required this.plateNumber,
    required this.country,
    required this.vin,
    required this.expertName,
    required this.signatureSvg,
    required this.documentStateJson,
    required this.onDocumentStateChanged,
    required this.onSignRequested,
    required this.scrollToBottomSignal,
    required this.scrollToTopSignal,
    this.mileage,
  });

  final String operationType;
  final String vehicleCategory;
  final String brand;
  final String plateNumber;
  final String country;
  final String vin;
  final int? mileage;
  final String expertName;
  final String? signatureSvg;
  final String documentStateJson;
  final ValueChanged<String> onDocumentStateChanged;
  final VoidCallback onSignRequested;
  final int scrollToBottomSignal;
  final int scrollToTopSignal;

  @override
  State<DocumentHtmlView> createState() => _DocumentHtmlViewState();
}

class _DocumentHtmlViewState extends State<DocumentHtmlView> {
  static int _nextId = 0;
  late final String _viewType;
  web.HTMLIFrameElement? _iframe;

  String get _documentUrl {
    return Uri(
      path:
          '/${_documentAssetName(widget.operationType, widget.vehicleCategory)}',
      queryParameters: {
        'brand': widget.brand,
        'plate_number': widget.plateNumber,
        'country': widget.country,
        'vehicle_category': widget.vehicleCategory,
        'vin': widget.vin,
        if (widget.mileage != null) 'mileage': widget.mileage.toString(),
        'expert_name': widget.expertName,
        if (widget.signatureSvg != null) 'signature': widget.signatureSvg!,
        if (widget.documentStateJson.isNotEmpty)
          'state': widget.documentStateJson,
      },
    ).toString();
  }

  @override
  void initState() {
    super.initState();
    _viewType = 'inspection-document-html-${_nextId++}';
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
    if (oldWidget.operationType != widget.operationType ||
        oldWidget.vehicleCategory != widget.vehicleCategory ||
        oldWidget.brand != widget.brand ||
        oldWidget.plateNumber != widget.plateNumber ||
        oldWidget.country != widget.country ||
        oldWidget.vin != widget.vin ||
        oldWidget.mileage != widget.mileage ||
        oldWidget.expertName != widget.expertName ||
        oldWidget.signatureSvg != widget.signatureSvg) {
      _iframe?.src = _documentUrl;
    }
    if (oldWidget.scrollToBottomSignal != widget.scrollToBottomSignal) {
      _scrollToBottom();
    }
    if (oldWidget.scrollToTopSignal != widget.scrollToTopSignal) {
      _scrollToTop();
    }
  }

  String _documentAssetName(String operationType, String vehicleCategory) {
    if (operationType == 'tech_inspection') {
      return vehicleCategory == 'N2'
          ? 'N2_visual_inspection.html'
          : 'M1_visual_inspection.html';
    }
    return '${vehicleCategory}_document_clean.html';
  }

  void _scrollToBottom() {
    _iframe?.contentWindow?.postMessage('autolab-scroll-bottom'.toJS, '*'.toJS);
    (_iframe?.contentWindow as JSObject?)?.callMethod(
      'scrollTo'.toJS,
      0.toJS,
      1000000.toJS,
    );
  }

  void _scrollToTop() {
    _iframe?.contentWindow?.postMessage('autolab-scroll-top'.toJS, '*'.toJS);
    (_iframe?.contentWindow as JSObject?)?.callMethod(
      'scrollTo'.toJS,
      0.toJS,
      0.toJS,
    );
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
