part of 'main.dart';

class _DraftsPage extends StatefulWidget {
  const _DraftsPage({required this.storage});

  final _AppStorage storage;

  @override
  State<_DraftsPage> createState() => _DraftsPageState();
}

class _DraftsPageState extends State<_DraftsPage> {
  Future<void> _delete(_InspectionDraft draft) async {
    await widget.storage.removeDraft(draft.id);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _open(_InspectionDraft draft) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _InspectionFormPage(storage: widget.storage, initialDraft: draft),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final drafts = widget.storage.drafts.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Черновики'),
        actions: [
          TextButton.icon(
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            icon: const Icon(Icons.home),
            label: const Text('Домой'),
          ),
        ],
      ),
      body: SafeArea(
        child: drafts.isEmpty
            ? const Center(child: Text('Черновиков нет'))
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: drafts.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final draft = drafts[index];
                      return _DraftCard(
                        draft: draft,
                        onTap: () => _open(draft),
                        onDelete: () => _delete(draft),
                      );
                    },
                  ),
                ),
              ),
      ),
    );
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.draft,
    required this.onTap,
    required this.onDelete,
  });

  final _InspectionDraft draft;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final photoCount = draft.photos.length;
    final expectedPhotoCount =
        draft.operationCategory == _OperationCategory.conversion ? 5 : 6;
    final totalPhotoCount = photoCount + draft.conversionPhotos.length;
    final title = [
      if (draft.brand.isNotEmpty) draft.brand else 'Без марки',
      if (draft.country.isNotEmpty) draft.country,
    ].join(' ');

    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.edit_document,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text('Операция: ${draft.operationCategory.label}'),
                    Text(
                      'Страна: ${draft.country.isEmpty ? '-' : draft.country}',
                    ),
                    Text('VIN: ${draft.vin.isEmpty ? '-' : draft.vin}'),
                    Text(
                      'Фото: $totalPhotoCount • основные $photoCount/$expectedPhotoCount • ${_formatDate(draft.updatedAt)}',
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: (photoCount / expectedPhotoCount).clamp(0, 1),
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Удалить',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
