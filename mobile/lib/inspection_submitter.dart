part of 'main.dart';

Future<_SentInspection> _sendInspectionDraft({
  required _AppStorage storage,
  required _InspectionDraft draft,
  required String expertName,
  required String? signatureSvg,
  required String documentStateJson,
}) async {
  final documentPdfBytes = draft.operationCategory.hasDocument && !kIsWeb
      ? await _createInspectionPdf(
          draft: draft,
          expertName: expertName,
          signatureSvg: signatureSvg,
          documentStateJson: documentStateJson,
        )
      : null;
  final api = _ApiClient(
    serverUrl: storage.serverUrl,
    sessionKey: storage.sessionKey,
  );
  final sent = await api.createInspection(
    draft,
    documentPdfBytes: documentPdfBytes,
  );
  final sentWithPhotos = sent.copyWithPhotos(
    photos: draft.photos,
    conversionPhotos: draft.conversionPhotos,
  );

  await storage.removeDraft(draft.id);
  await storage.addSent(sentWithPhotos);
  return sentWithPhotos;
}

Future<List<int>> _createInspectionPdf({
  required _InspectionDraft draft,
  required String expertName,
  required String? signatureSvg,
  required String documentStateJson,
}) async {
  final html = await _buildInspectionDocumentHtml(
    draft: draft,
    expertName: expertName,
    signatureSvg: signatureSvg,
    documentStateJson: documentStateJson,
  );
  final bytes = await _pdfChannel.invokeMethod<Uint8List>('htmlToPdf', {
    'html': html,
  });
  if (bytes == null || bytes.isEmpty) {
    throw Exception('Не удалось создать PDF документа.');
  }
  return bytes;
}

Future<String> _buildInspectionDocumentHtml({
  required _InspectionDraft draft,
  required String expertName,
  required String? signatureSvg,
  required String documentStateJson,
}) async {
  final source = await rootBundle.loadString(
    'assets/${_documentAssetName(draft)}',
  );
  final params = Uri(
    queryParameters: {
      'brand': draft.brand,
      'plate_number': draft.plateNumber,
      'country': draft.country,
      'vehicle_category': draft.vehicleCategory.apiValue,
      'vin': draft.vin,
      if (draft.mileage != null) 'mileage': draft.mileage.toString(),
      'expert_name': expertName,
      // ignore: use_null_aware_elements
      if (signatureSvg case final svg?) 'signature': svg,
      if (documentStateJson.isNotEmpty) 'state': documentStateJson,
    },
  ).query;
  const pdfCss = '''
  @media screen {
    html,body { background:#fff!important; padding:0!important; }
    .page { margin:0!important; box-shadow:none!important; width:210mm!important; height:297mm!important; min-height:297mm!important; }
    .signature-button { display:none!important; }
    .needs-fill,
    .info-table textarea.needs-fill,
    .info-table input.needs-fill,
    .actual-mm input { background:transparent!important; }
  }
  ''';
  return source
      .replaceFirst('</style>', '$pdfCss</style>')
      .replaceFirst(
        'new URLSearchParams(window.location.search)',
        'new URLSearchParams(${jsonEncode(params)})',
      );
}

String _documentAssetName(_InspectionDraft draft) {
  if (draft.operationCategory == _OperationCategory.techInspection) {
    return draft.vehicleCategory == _VehicleCategory.n2
        ? 'N2_visual_inspection.html'
        : 'M1_visual_inspection.html';
  }
  return '${draft.vehicleCategory.apiValue}_document_clean.html';
}
