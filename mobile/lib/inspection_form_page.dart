part of 'main.dart';

class _InspectionFormPage extends StatefulWidget {
  const _InspectionFormPage({
    required this.storage,
    this.operationCategory,
    this.initialDraft,
  });

  final _AppStorage storage;
  final _OperationCategory? operationCategory;
  final _InspectionDraft? initialDraft;

  @override
  State<_InspectionFormPage> createState() => _InspectionFormPageState();
}

class _InspectionFormPageState extends State<_InspectionFormPage> {
  final _brandController = TextEditingController();
  final _countryController = TextEditingController();
  final _vinController = TextEditingController();
  final _picker = ImagePicker();
  final GlobalKey _documentViewKey = GlobalKey(
    debugLabel: 'inspection-document-view',
  );
  final Map<_PhotoKind, String> _photos = {};
  final Map<_PhotoKind, DateTime> _photoTakenAt = {};
  final List<String> _conversionPhotos = [];
  _OperationCategory _operationCategory = _OperationCategory.sbgts;
  _VehicleCategory _vehicleCategory = _VehicleCategory.m1;
  bool _isSaving = false;
  bool _showDocument = false;
  bool _documentSigned = false;
  String _documentStateJson = '';
  String? _status;
  bool _statusIsError = false;
  int _documentScrollToBottomSignal = 0;
  int _documentScrollToTopSignal = 0;
  late String _draftId;
  Timer? _autoSaveTimer;

  bool get _isEditingDraft => widget.initialDraft != null;
  bool get _isConversion => _operationCategory == _OperationCategory.conversion;
  List<_PhotoKind> get _visiblePhotoKinds {
    if (_isConversion) {
      return _PhotoKind.values
          .where((kind) => kind != _PhotoKind.mileage)
          .toList();
    }
    return _PhotoKind.values;
  }

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft;
    _draftId = draft?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    if (draft != null) {
      _operationCategory = draft.operationCategory;
      _brandController.text = draft.brand;
      _countryController.text = draft.country;
      _vinController.text = draft.vin;
      _vehicleCategory = draft.vehicleCategory;
      _documentStateJson = draft.documentStateJson;
      _photos.addAll(draft.photos);
      _photoTakenAt.addAll(draft.photoTakenAt);
      _conversionPhotos.addAll(draft.conversionPhotos);
    } else {
      _operationCategory = widget.operationCategory ?? _OperationCategory.sbgts;
    }
    _brandController.addListener(_handleFieldChanged);
    _countryController.addListener(_handleFieldChanged);
    _vinController.addListener(_handleFieldChanged);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _autoSaveDraft();
    _brandController.dispose();
    _countryController.dispose();
    _vinController.dispose();
    super.dispose();
  }

  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 500), _autoSaveDraft);
  }

  void _handleFieldChanged() {
    _scheduleAutoSave();
    if (_showDocument) {
      setState(() {});
    }
  }

  Future<void> _autoSaveDraft() async {
    final draft = _buildDraft(showErrors: false);
    if (draft == null) {
      return;
    }

    await widget.storage.upsertDraft(draft);
  }

  Future<void> _takePhoto(_PhotoKind kind) async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1600,
      );

      if (image == null) {
        setState(() {
          _status = 'Съемка отменена.';
          _statusIsError = false;
        });
        return;
      }

      final savedPath = await _persistPhoto(image, kind, _photos[kind]);
      setState(() {
        _photos[kind] = savedPath;
        _photoTakenAt[kind] = DateTime.now();
        _status = 'Фото "${kind.label}" готово.';
        _statusIsError = false;
      });
      await _autoSaveDraft();
    } catch (error) {
      setState(() {
        _status = _humanError(error);
        _statusIsError = true;
      });
    }
  }

  Future<String> _persistPhoto(
    XFile image,
    _PhotoKind kind,
    String? previousPath,
  ) async {
    final directory = await getApplicationDocumentsDirectory();
    final inspectionsDir = Directory('${directory.path}/inspection_photos');
    if (!await inspectionsDir.exists()) {
      await inspectionsDir.create(recursive: true);
    }

    final extension = _extensionForPath(image.path);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final target = File(
      '${inspectionsDir.path}/${_draftId}_${kind.key}_$stamp$extension',
    );
    final saved = await File(image.path).copy(target.path);

    if (previousPath != null && previousPath != saved.path) {
      final previous = File(previousPath);
      if (await previous.exists()) {
        await previous.delete();
      }
    }

    return saved.path;
  }

  Future<void> _addConversionPhoto() async {
    if (_conversionPhotos.length >= 12) {
      setState(() {
        _status = 'Можно добавить максимум 12 фото переоборудованной части.';
        _statusIsError = true;
      });
      return;
    }

    try {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (image == null) {
        setState(() {
          _status = 'Съемка отменена.';
          _statusIsError = false;
        });
        return;
      }

      final savedPath = await _persistConversionPhoto(image);
      setState(() {
        _conversionPhotos.add(savedPath);
        _status = 'Фото переоборудованной части добавлено.';
        _statusIsError = false;
      });
      await _autoSaveDraft();
    } catch (error) {
      setState(() {
        _status = _humanError(error);
        _statusIsError = true;
      });
    }
  }

  Future<String> _persistConversionPhoto(XFile image) async {
    final directory = await getApplicationDocumentsDirectory();
    final inspectionsDir = Directory('${directory.path}/inspection_photos');
    if (!await inspectionsDir.exists()) {
      await inspectionsDir.create(recursive: true);
    }

    final extension = _extensionForPath(image.path);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final target = File(
      '${inspectionsDir.path}/${_draftId}_conversion_$stamp$extension',
    );
    final saved = await File(image.path).copy(target.path);
    return saved.path;
  }

  Future<void> _removeConversionPhoto(String path) async {
    setState(() {
      _conversionPhotos.remove(path);
    });
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    await _autoSaveDraft();
  }

  Future<void> _continueToDocument() async {
    final draft = _buildDraft(requireBrand: true);
    if (draft == null) {
      return;
    }

    await widget.storage.upsertDraft(draft);

    if (!mounted) {
      return;
    }

    if (!_operationCategory.hasDocument) {
      await _sendInspection();
      return;
    }

    setState(() {
      _showDocument = true;
      _status = null;
      _statusIsError = false;
    });
  }

  void _backToPhotos() {
    setState(() {
      _showDocument = false;
      _status = null;
      _statusIsError = false;
    });
  }

  void _signDocument() {
    final signature = widget.storage.signatureSvg();
    if (signature == null) {
      setState(() {
        _status = 'Сначала сохраните подпись в пункте "Подпись".';
        _statusIsError = true;
      });
      return;
    }

    setState(() {
      _documentSigned = true;
      _status = null;
      _statusIsError = false;
    });
  }

  void _scrollDocumentToBottom() {
    setState(() => _documentScrollToBottomSignal++);
  }

  void _scrollDocumentToTop() {
    setState(() => _documentScrollToTopSignal++);
  }

  String get _expertName {
    final fullName = widget.storage.userFullName?.trim();
    if (fullName != null && fullName.isNotEmpty) {
      return _shortExpertName(fullName);
    }

    final label = widget.storage.userLabel?.split('/').first.trim();
    if (label != null && label.isNotEmpty) {
      return _shortExpertName(label);
    }

    return widget.storage.lastLogin ?? '';
  }

  Future<void> _sendInspection() async {
    final draft = _buildDraft(requireBrand: true);
    if (draft == null) {
      return;
    }

    setState(() {
      _isSaving = true;
      _status = 'Отправляю осмотр...';
      _statusIsError = false;
    });

    try {
      final sent = await _sendInspectionDraft(
        storage: widget.storage,
        draft: draft,
        expertName: _expertName,
        signatureSvg: _documentSigned ? widget.storage.signatureSvg() : null,
        documentStateJson: _documentStateJson,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _status = 'Осмотр отправлен. ID: ${sent.remoteId}';
        _statusIsError = false;
      });

      Navigator.of(context).pop();
    } catch (error) {
      await _handleActionError(error);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  _InspectionDraft _draftSnapshot() {
    return _InspectionDraft(
      id: _draftId,
      operationCategory: _operationCategory,
      plateNumber: '',
      brand: _brandController.text.trim(),
      country: _countryController.text.trim(),
      vehicleCategory: _vehicleCategory,
      vin: _vinController.text.trim().toUpperCase(),
      documentStateJson: _documentStateJson,
      photos: Map<_PhotoKind, String>.from(_photos),
      photoTakenAt: Map<_PhotoKind, DateTime>.from(_photoTakenAt),
      conversionPhotos: List<String>.from(_conversionPhotos),
      createdAt: widget.initialDraft?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _handleActionError(Object error) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _status = _humanError(error);
      _statusIsError = true;
    });

    if (error is _AuthException) {
      await widget.storage.clearSession();
      if (!mounted) {
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => _LoginPage(storage: widget.storage)),
        (route) => false,
      );
    }
  }

  _InspectionDraft? _buildDraft({
    bool requireBrand = false,
    bool requireAllPhotos = false,
    bool showErrors = true,
  }) {
    final brand = _brandController.text.trim();
    final country = _countryController.text.trim();
    final vin = _vinController.text.trim().toUpperCase();

    if (!requireBrand &&
        brand.isEmpty &&
        country.isEmpty &&
        vin.isEmpty &&
        _photos.isEmpty) {
      return null;
    }

    if (requireBrand && brand.isEmpty) {
      if (showErrors) {
        setState(() {
          _status = 'Заполните марку авто.';
          _statusIsError = true;
        });
      }
      return null;
    }

    final missing = _visiblePhotoKinds
        .where((kind) => !_photos.containsKey(kind))
        .map((kind) => kind.label)
        .toList();

    if (requireAllPhotos && missing.isNotEmpty) {
      if (showErrors) {
        setState(() {
          _status = 'Не хватает фото: ${missing.join(', ')}.';
          _statusIsError = true;
        });
      }
      return null;
    }

    return _InspectionDraft(
      id: _draftId,
      operationCategory: _operationCategory,
      plateNumber: '',
      brand: brand,
      country: country,
      vehicleCategory: _vehicleCategory,
      vin: vin,
      documentStateJson: _documentStateJson,
      photos: Map<_PhotoKind, String>.from(_photos),
      photoTakenAt: Map<_PhotoKind, DateTime>.from(_photoTakenAt),
      conversionPhotos: List<String>.from(_conversionPhotos),
      createdAt: widget.initialDraft?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_operationCategory.label),
        bottom: _isEditingDraft
            ? PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Черновик',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              )
            : null,
        actions: [
          TextButton.icon(
            onPressed: _goHome,
            icon: const Icon(Icons.home),
            label: const Text('Домой'),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isLandscape =
                MediaQuery.orientationOf(context) == Orientation.landscape;
            final isWideLandscape = isLandscape && constraints.maxWidth >= 700;
            final isTabletLandscape =
                isLandscape && constraints.maxWidth >= 900;

            if (_showDocument && _operationCategory.hasDocument) {
              return isWideLandscape
                  ? _buildDocumentLandscapeForm()
                  : _buildDocumentPortraitForm();
            }

            return isTabletLandscape
                ? _buildTabletLandscapeForm()
                : _buildPhoneForm();
          },
        ),
      ),
    );
  }

  Widget _buildPhoneForm() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildFields(),
        const SizedBox(height: 16),
        if (_status != null) ...[
          _StatusBox(text: _status!, isError: _statusIsError),
          const SizedBox(height: 16),
        ],
        _buildPhotoGrid(columns: 2),
        if (_isConversion) ...[
          const SizedBox(height: 16),
          _buildConversionPhotosSection(),
        ],
        const SizedBox(height: 16),
        _buildFormActions(),
      ],
    );
  }

  Widget _buildTabletLandscapeForm() {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildFields(compact: true, showCategory: false),
                if (_status != null) ...[
                  const SizedBox(height: 10),
                  Flexible(
                    child: _StatusBox(text: _status!, isError: _statusIsError),
                  ),
                ] else
                  const Spacer(),
                const SizedBox(height: 10),
                _buildFormActions(),
              ],
            ),
          ),
          const SizedBox(width: 14),
          const VerticalDivider(width: 1),
          const SizedBox(width: 14),
          Expanded(
            child: _showDocument
                ? _buildEmbeddedDocument()
                : ListView(
                    children: [
                      _buildPhotoGrid(
                        columns: 3,
                        childAspectRatio: 1.22,
                        spacing: 8,
                      ),
                      if (_isConversion) ...[
                        const SizedBox(height: 10),
                        _buildConversionPhotosSection(compact: true),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentLandscapeForm() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 330,
            child: ListView(
              children: [
                _buildFields(compact: true),
                if (_status != null) ...[
                  const SizedBox(height: 10),
                  _StatusBox(text: _status!, isError: _statusIsError),
                ],
                const SizedBox(height: 10),
                _buildFormActions(),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const VerticalDivider(width: 1),
          const SizedBox(width: 12),
          Expanded(child: _buildDocumentWithScrollControls()),
        ],
      ),
    );
  }

  Widget _buildDocumentPortraitForm() {
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: ExpansionTile(
            initiallyExpanded: false,
            title: const Text('Данные авто'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              _buildFields(compact: true, showCategory: false),
              if (_status != null) ...[
                const SizedBox(height: 10),
                _StatusBox(text: _status!, isError: _statusIsError),
              ],
              const SizedBox(height: 10),
              _buildFormActions(),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: _DocumentJumpButton(
            label: 'В самый низ',
            icon: Icons.keyboard_double_arrow_down,
            onPressed: _scrollDocumentToBottom,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: _buildEmbeddedDocument(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: _DocumentJumpButton(
            label: 'Вверх',
            icon: Icons.keyboard_double_arrow_up,
            onPressed: _scrollDocumentToTop,
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentWithScrollControls() {
    return Column(
      children: [
        _DocumentJumpButton(
          label: 'В самый низ',
          icon: Icons.keyboard_double_arrow_down,
          onPressed: _scrollDocumentToBottom,
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildEmbeddedDocument()),
        const SizedBox(height: 8),
        _DocumentJumpButton(
          label: 'Вверх',
          icon: Icons.keyboard_double_arrow_up,
          onPressed: _scrollDocumentToTop,
        ),
      ],
    );
  }

  Widget _buildEmbeddedDocument() {
    return _EmbeddedInspectionDocument(
      draft: _draftSnapshot(),
      expertName: _expertName,
      signatureSvg: _documentSigned ? widget.storage.signatureSvg() : null,
      documentStateJson: _documentStateJson,
      onDocumentStateChanged: (state) {
        if (!mounted) {
          return;
        }
        _documentStateJson = state;
        _scheduleAutoSave();
      },
      onSign: _signDocument,
      documentViewKey: _documentViewKey,
      scrollToBottomSignal: _documentScrollToBottomSignal,
      scrollToTopSignal: _documentScrollToTopSignal,
    );
  }

  Widget _buildFields({bool compact = false, bool showCategory = true}) {
    final gap = compact ? 8.0 : 12.0;
    return Column(
      children: [
        if (showCategory) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<_VehicleCategory>(
                segments: const [
                  ButtonSegment(value: _VehicleCategory.m1, label: Text('M1')),
                  ButtonSegment(value: _VehicleCategory.m2, label: Text('M2')),
                  ButtonSegment(value: _VehicleCategory.m3, label: Text('M3')),
                  ButtonSegment(value: _VehicleCategory.n1, label: Text('N1')),
                  ButtonSegment(value: _VehicleCategory.n2, label: Text('N2')),
                  ButtonSegment(value: _VehicleCategory.n3, label: Text('N3')),
                ],
                selected: {_vehicleCategory},
                onSelectionChanged: (selection) {
                  final next = selection.first;
                  if (next == _vehicleCategory) {
                    return;
                  }
                  setState(() {
                    _vehicleCategory = next;
                  });
                  _scheduleAutoSave();
                },
              ),
            ),
          ),
          SizedBox(height: gap),
        ],
        TextField(
          controller: _brandController,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: compact,
            labelText: 'Марка авто',
            hintText: 'Toyota',
          ),
        ),
        SizedBox(height: gap),
        TextField(
          controller: _countryController,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: compact,
            labelText: 'Страна',
            hintText: 'Япония',
          ),
        ),
        SizedBox(height: gap),
        TextField(
          controller: _vinController,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: compact,
            labelText: 'VIN номер',
            hintText: 'Введите VIN вручную',
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoGrid({
    required int columns,
    double childAspectRatio = 1.08,
    double spacing = 10,
  }) {
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: childAspectRatio,
      ),
      children: [
        for (final kind in _visiblePhotoKinds)
          _PhotoTile(
            label: kind.label,
            asset: kind.asset,
            path: _photos[kind],
            onTap: () => _takePhoto(kind),
          ),
      ],
    );
  }

  Widget _buildConversionPhotosSection({bool compact = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    final columns = compact ? 4 : 3;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 8 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Фото переоборудованной части',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text('${_conversionPhotos.length}/12'),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Добавить фото',
                  onPressed: _conversionPhotos.length >= 12
                      ? null
                      : _addConversionPhoto,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (_conversionPhotos.isNotEmpty) ...[
              const SizedBox(height: 10),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _conversionPhotos.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  final path = _conversionPhotos[index];
                  return _ConversionPhotoTile(
                    path: path,
                    onDelete: () => _removeConversionPhoto(path),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFormActions() {
    if (_showDocument && _operationCategory.hasDocument) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _isSaving ? null : _backToPhotos,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Назад'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _sendInspection,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: const Text('Отправить'),
            ),
          ),
        ],
      );
    }

    return SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: _isSaving ? null : _continueToDocument,
        iconAlignment: IconAlignment.end,
        label: Text(_operationCategory.hasDocument ? 'Далее' : 'Отправить'),
        icon: _isSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                _operationCategory.hasDocument
                    ? Icons.arrow_forward
                    : Icons.send,
              ),
      ),
    );
  }
}
