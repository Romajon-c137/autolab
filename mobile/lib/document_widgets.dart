part of 'main.dart';

class _EmbeddedInspectionDocument extends StatelessWidget {
  const _EmbeddedInspectionDocument({
    required this.draft,
    required this.expertName,
    required this.signatureSvg,
    required this.documentStateJson,
    required this.onDocumentStateChanged,
    required this.onSign,
    required this.documentViewKey,
  });

  final _InspectionDraft draft;
  final String expertName;
  final String? signatureSvg;
  final String documentStateJson;
  final ValueChanged<String> onDocumentStateChanged;
  final VoidCallback onSign;
  final GlobalKey documentViewKey;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _DocumentHtmlPanel(
          draft: draft,
          expertName: expertName,
          signatureSvg: signatureSvg,
          documentStateJson: documentStateJson,
          onDocumentStateChanged: onDocumentStateChanged,
          onSignRequested: onSign,
          documentViewKey: documentViewKey,
        ),
      ),
    );
  }
}

class _DocumentHtmlPanel extends StatelessWidget {
  const _DocumentHtmlPanel({
    required this.draft,
    required this.expertName,
    required this.signatureSvg,
    required this.documentStateJson,
    required this.onDocumentStateChanged,
    required this.onSignRequested,
    required this.documentViewKey,
  });

  final _InspectionDraft draft;
  final String expertName;
  final String? signatureSvg;
  final String documentStateJson;
  final ValueChanged<String> onDocumentStateChanged;
  final VoidCallback onSignRequested;
  final GlobalKey documentViewKey;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: DocumentHtmlView(
        key: documentViewKey,
        vehicleCategory: draft.vehicleCategory.apiValue,
        brand: draft.brand,
        country: draft.country,
        vin: draft.vin,
        expertName: expertName,
        signatureSvg: signatureSvg,
        documentStateJson: documentStateJson,
        onDocumentStateChanged: onDocumentStateChanged,
        onSignRequested: onSignRequested,
      ),
    );
  }
}
