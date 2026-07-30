part of 'main.dart';

class _RegisterPage extends StatefulWidget {
  const _RegisterPage({required this.storage});

  final _AppStorage storage;

  @override
  State<_RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<_RegisterPage> {
  late DateTime _dateFrom;
  late DateTime _dateTo;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateFrom = DateTime(now.year, now.month, now.day);
    _dateTo = _dateFrom;
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _dateFrom : _dateTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked == null) {
      return;
    }

    setState(() {
      if (isFrom) {
        _dateFrom = DateTime(picked.year, picked.month, picked.day);
        if (_dateFrom.isAfter(_dateTo)) {
          _dateTo = _dateFrom;
        }
      } else {
        _dateTo = DateTime(picked.year, picked.month, picked.day);
        if (_dateTo.isBefore(_dateFrom)) {
          _dateFrom = _dateTo;
        }
      }
    });
  }

  bool _inPeriod(_SentInspection item) {
    final day = DateTime(item.sentAt.year, item.sentAt.month, item.sentAt.day);
    return !day.isBefore(_dateFrom) && !day.isAfter(_dateTo);
  }

  @override
  Widget build(BuildContext context) {
    final sent = widget.storage.sent.where(_inPeriod).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Реестр'),
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(isFrom: true),
                          icon: const Icon(Icons.date_range),
                          label: Text('С ${_formatDateOnly(_dateFrom)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(isFrom: false),
                          icon: const Icon(Icons.event),
                          label: Text('По ${_formatDateOnly(_dateTo)}'),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: sent.isEmpty
                      ? const Center(
                          child: Text('За выбранный период осмотров нет'),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: sent.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = sent[index];
                            return _InspectionRegisterCard(
                              item: item,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        _InspectionDetailsPage(item: item),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InspectionRegisterCard extends StatelessWidget {
  const _InspectionRegisterCard({required this.item, required this.onTap});

  final _SentInspection item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = [
      item.brand,
      if (item.country.isNotEmpty) item.country,
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
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.directions_car,
                  color: colorScheme.onPrimaryContainer,
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
                    Text('Операция: ${item.operationCategory.label}'),
                    if (item.conversionPhotos.isNotEmpty)
                      Text('Доп. фото: ${item.conversionPhotos.length}'),
                    Text('VIN: ${item.vin.isEmpty ? '-' : item.vin}'),
                    Text('ID: ${item.remoteId} • ${_formatDate(item.sentAt)}'),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _InspectionDetailsPage extends StatelessWidget {
  const _InspectionDetailsPage({required this.item});

  final _SentInspection item;

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.sizeOf(context).width >= 720;
    final title = [
      item.brand,
      if (item.country.isNotEmpty) item.country,
    ].join(' ');
    final details = _StatusBox(
      text:
          '$title\n'
          'Операция: ${item.operationCategory.label}\n'
          'Марка: ${item.brand}\n'
          'Страна: ${item.country.isEmpty ? '-' : item.country}\n'
          'VIN: ${item.vin.isEmpty ? '-' : item.vin}\n'
          'ID: ${item.remoteId}\n'
          'Дата: ${_formatDate(item.sentAt)}',
    );
    final photos = _ReadonlyPhotoGrid(
      photos: item.photos,
      conversionPhotos: item.conversionPhotos,
      columns: isTablet ? 3 : 2,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Осмотр'),
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
        child: isTablet
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 360,
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [details],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [photos],
                    ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [details, const SizedBox(height: 16), photos],
              ),
      ),
    );
  }
}

class _ReadonlyPhotoGrid extends StatelessWidget {
  const _ReadonlyPhotoGrid({
    required this.photos,
    required this.conversionPhotos,
    required this.columns,
  });

  final Map<_PhotoKind, String> photos;
  final List<String> conversionPhotos;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.08,
      ),
      children: [
        for (final kind in _PhotoKind.values)
          _ReadonlyPhotoTile(label: kind.label, path: photos[kind]),
        for (var index = 0; index < conversionPhotos.length; index++)
          _ReadonlyPhotoTile(
            label: 'Переоборудование ${index + 1}',
            path: conversionPhotos[index],
          ),
      ],
    );
  }
}

class _ReadonlyPhotoTile extends StatelessWidget {
  const _ReadonlyPhotoTile({required this.label, required this.path});

  final String label;
  final String? path;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fileExists = path != null && File(path!).existsSync();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (fileExists)
            Image.file(File(path!), fit: BoxFit.cover)
          else
            ColoredBox(
              color: colorScheme.surfaceContainerHighest,
              child: const Center(child: Icon(Icons.image_not_supported)),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              color: Colors.black.withValues(alpha: 0.56),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
