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

class _UpperCaseTextFormatter extends TextInputFormatter {
  const _UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class _InspectionFormPageState extends State<_InspectionFormPage> {
  final _brandController = TextEditingController();
  final _brandFocusNode = FocusNode();
  final _plateNumberController = TextEditingController();
  final _plateNumberFocusNode = FocusNode();
  final _countryController = TextEditingController();
  final _vinController = TextEditingController();
  final _mileageController = TextEditingController();
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
  bool _isRecognizingVin = false;
  bool _isRecognizingMileage = false;
  String _documentStateJson = '';
  String? _status;
  bool _statusIsError = false;
  int _documentScrollToBottomSignal = 0;
  int _documentScrollToTopSignal = 0;
  bool _documentScrollDown = true;
  late String _draftId;
  Timer? _autoSaveTimer;

  bool get _isEditingDraft => widget.initialDraft != null;
  bool get _isConversion => _operationCategory == _OperationCategory.conversion;
  List<_VehicleCategory> get _availableVehicleCategories {
    if (_operationCategory == _OperationCategory.techInspection) {
      return const [_VehicleCategory.n2, _VehicleCategory.m1];
    }
    return _VehicleCategory.values;
  }

  List<_PhotoKind> get _visiblePhotoKinds {
    final hidden = <_PhotoKind>{
      if (_isConversion) _PhotoKind.mileage,
    };

    return _PhotoKind.values.where((kind) => !hidden.contains(kind)).toList();
  }

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft;
    _draftId = draft?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    if (draft != null) {
      _operationCategory = draft.operationCategory;
      _brandController.text = draft.brand;
      _plateNumberController.text = draft.plateNumber;
      _countryController.text = draft.country;
      _vinController.text = draft.vin;
      if (draft.mileage != null) {
        _mileageController.text = draft.mileage.toString();
      }
      _vehicleCategory = draft.vehicleCategory;
      _documentStateJson = draft.documentStateJson;
      _photos.addAll(draft.photos);
      _photoTakenAt.addAll(draft.photoTakenAt);
      _conversionPhotos.addAll(draft.conversionPhotos);
    } else {
      _operationCategory = widget.operationCategory ?? _OperationCategory.sbgts;
    }
    _ensureAllowedVehicleCategory();
    _brandController.addListener(_handleFieldChanged);
    _plateNumberController.addListener(_handleFieldChanged);
    _countryController.addListener(_handleFieldChanged);
    _vinController.addListener(_handleFieldChanged);
    _mileageController.addListener(_handleFieldChanged);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _autoSaveDraft();
    _brandController.dispose();
    _brandFocusNode.dispose();
    _plateNumberFocusNode.dispose();
    _plateNumberController.dispose();
    _countryController.dispose();
    _vinController.dispose();
    _mileageController.dispose();
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

  void _ensureAllowedVehicleCategory() {
    if (!_availableVehicleCategories.contains(_vehicleCategory)) {
      _vehicleCategory = _availableVehicleCategories.first;
    }
  }

  String _vehicleCategoryLabel(_VehicleCategory category) {
    if (_operationCategory == _OperationCategory.techInspection) {
      return switch (category) {
        _VehicleCategory.n2 => 'Грузовой',
        _VehicleCategory.m1 => 'Легковой',
        _ => category.apiValue,
      };
    }

    return category.apiValue;
  }

  String? _activeBrandInText(String text) {
    final lower = text.trimLeft().toLowerCase();
    for (final brand in _catalogBrands()) {
      final brandLower = brand.toLowerCase();
      if (lower == brandLower || lower.startsWith('$brandLower ')) {
        return brand;
      }
    }
    return null;
  }

  bool _subsequenceMatch(String value, String query) {
    final chars = query.characters;
    var index = 0;
    for (final char in chars) {
      var found = false;
      while (index < value.length) {
        if (value[index].toLowerCase() == char.toLowerCase()) {
          found = true;
          index++;
          break;
        }
        index++;
      }
      if (!found) {
        return false;
      }
    }
    return true;
  }

  Iterable<String> _filterSuggestions(List<String> source, String query) {
    final lower = query.toLowerCase();
    final prefix = source.where((s) => s.toLowerCase().startsWith(lower));
    final contains = source.where(
      (s) =>
          !s.toLowerCase().startsWith(lower) && s.toLowerCase().contains(lower),
    );
    final subsequence = source.where(
      (s) =>
          !s.toLowerCase().startsWith(lower) &&
          !s.toLowerCase().contains(lower) &&
          _subsequenceMatch(s.toLowerCase(), lower),
    );
    return [...prefix, ...contains, ...subsequence];
  }

  Iterable<String> _brandSuggestions(String text) {
    final trimmed = text.trimLeft();
    if (trimmed.isEmpty) {
      return _catalogBrands();
    }

    final activeBrand = _activeBrandInText(trimmed);
    if (activeBrand != null) {
      final rest = trimmed.substring(activeBrand.length).trimLeft();
      final models = _catalogModels(activeBrand);
      if (rest.isEmpty) {
        return models.map((model) => '$activeBrand $model');
      }
      final matches = _filterSuggestions(models, rest);
      if (matches.isNotEmpty) {
        return matches.map((model) => '$activeBrand $model');
      }
    }

    final matches = _filterSuggestions(_catalogBrands(), trimmed);
    if (matches.isNotEmpty) {
      return matches;
    }
    return const Iterable<String>.empty();
  }

  void _onBrandSelected(String option) {
    final activeBrand = _activeBrandInText(_brandController.text);
    final isModel =
        activeBrand != null &&
        _catalogModels(
          activeBrand,
        ).any((model) => model.toLowerCase() == option.toLowerCase());
    final value = isModel ? '$activeBrand $option' : option;
    _brandController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _scheduleAutoSave();
  }

  Iterable<String> _platePrefixSuggestions(String query) {
    final normalized = query.trim().toUpperCase();
    final prefixes = List.generate(
      10,
      (index) => '${(index + 1).toString().padLeft(2, '0')}KG',
    );

    if (normalized.isEmpty) {
      return prefixes;
    }

    return prefixes.where(
      (prefix) => prefix.startsWith(normalized) || normalized.startsWith(prefix),
    );
  }

  void _onPlatePrefixSelected(String option) {
    final current = _plateNumberController.text.trim().toUpperCase();
    final withoutKnownPrefix = current.replaceFirst(
      RegExp(r'^(0[1-9]|10)KG'),
      '',
    );
    final value = '$option$withoutKnownPrefix';
    _plateNumberController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _scheduleAutoSave();
  }

  Widget _buildPlateNumberField({required bool compact}) {
    return RawAutocomplete<String>(
      textEditingController: _plateNumberController,
      focusNode: _plateNumberFocusNode,
      optionsBuilder: (textEditingValue) {
        return _platePrefixSuggestions(textEditingValue.text);
      },
      optionsViewBuilder: (context, onSelected, options) {
        if (options.isEmpty) {
          return const SizedBox.shrink();
        }
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            color: Theme.of(context).colorScheme.surface,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text(option),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
      onSelected: _onPlatePrefixSelected,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: const [_UpperCaseTextFormatter()],
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: compact,
            labelText: 'Гос номер',
            hintText: '01KG000AAA',
          ),
        );
      },
    );
  }

  Widget _buildBrandField({required bool compact}) {
    return RawAutocomplete<String>(
      textEditingController: _brandController,
      focusNode: _brandFocusNode,
      optionsBuilder: (textEditingValue) {
        return _brandSuggestions(textEditingValue.text);
      },
      optionsViewBuilder: (context, onSelected, options) {
        if (options.isEmpty) {
          return const SizedBox.shrink();
        }
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            color: Theme.of(context).colorScheme.surface,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text(option),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
      onSelected: _onBrandSelected,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: compact,
            labelText: 'Марка авто',
            hintText: 'Toyota Corolla',
          ),
        );
      },
    );
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
      if (kind == _PhotoKind.vin) {
        await _recognizeVinFromPhoto(savedPath);
      } else if (kind == _PhotoKind.mileage) {
        await _recognizeMileageFromPhoto(savedPath);
      }
    } catch (error) {
      setState(() {
        _status = _humanError(error);
        _statusIsError = true;
      });
    }
  }

  Future<void> _recognizeVinFromPhoto(String path) async {
    if (widget.storage.sessionKey == null ||
        widget.storage.sessionKey!.isEmpty) {
      return;
    }

    setState(() {
      _isRecognizingVin = true;
      _status = 'Распознаю VIN...';
      _statusIsError = false;
    });

    try {
      final vin = await _ApiClient(
        serverUrl: widget.storage.serverUrl,
        sessionKey: widget.storage.sessionKey,
      ).recognizeVin(path);

      if (!mounted) {
        return;
      }

      setState(() {
        _vinController.text = vin;
        _isRecognizingVin = false;
        _status = 'VIN распознан: $vin';
        _statusIsError = false;
      });
      await _autoSaveDraft();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isRecognizingVin = false;
        _status = 'VIN не распознан: ${_humanError(error)}';
        _statusIsError = true;
      });
    }
  }

  Future<void> _recognizeMileageFromPhoto(String path) async {
    if (widget.storage.sessionKey == null ||
        widget.storage.sessionKey!.isEmpty) {
      return;
    }

    setState(() {
      _isRecognizingMileage = true;
      _status = 'Распознаю пробег...';
      _statusIsError = false;
    });

    try {
      final mileage = await _ApiClient(
        serverUrl: widget.storage.serverUrl,
        sessionKey: widget.storage.sessionKey,
      ).recognizeMileage(path);

      if (!mounted) {
        return;
      }

      setState(() {
        _mileageController.text = mileage.toString();
        _isRecognizingMileage = false;
        _status = 'Пробег распознан: $mileage км';
        _statusIsError = false;
      });
      await _autoSaveDraft();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isRecognizingMileage = false;
        _status = 'Пробег не распознан: ${_humanError(error)}';
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
    final draft = _buildDraft(requireBrand: true, requireVin: true);
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
    final draft = _buildDraft(requireBrand: true, requireVin: true);
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
      plateNumber: _plateNumberController.text.trim().toUpperCase(),
      brand: _brandController.text.trim(),
      country: _countryController.text.trim(),
      vehicleCategory: _vehicleCategory,
      vin: _vinController.text.trim().toUpperCase(),
      mileage: int.tryParse(_mileageController.text.trim()),
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
    bool requireVin = false,
    bool requireAllPhotos = false,
    bool showErrors = true,
  }) {
    final brand = _brandController.text.trim();
    final plateNumber = _plateNumberController.text.trim().toUpperCase();
    final country = _countryController.text.trim();
    final vin = _vinController.text.trim().toUpperCase();
    final mileage = int.tryParse(_mileageController.text.trim());

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

    if (requireVin && vin.isEmpty) {
      if (showErrors) {
        setState(() {
          _status = 'Заполните VIN номер.';
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
      plateNumber: plateNumber,
      brand: brand,
      country: country,
      vehicleCategory: _vehicleCategory,
      vin: vin,
      mileage: mileage,
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
    final isTech = _operationCategory == _OperationCategory.techInspection;
    return Stack(
      children: [
        Column(
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
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: _buildEmbeddedDocument(),
              ),
            ),
          ],
        ),
        if (!isTech)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.small(
              heroTag: 'scroll_document',
              onPressed: () {
                if (_documentScrollDown) {
                  _scrollDocumentToBottom();
                } else {
                  _scrollDocumentToTop();
                }
                setState(() => _documentScrollDown = !_documentScrollDown);
              },
              child: Icon(
                _documentScrollDown
                    ? Icons.keyboard_double_arrow_down
                    : Icons.keyboard_double_arrow_up,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDocumentWithScrollControls() {
    final isTech = _operationCategory == _OperationCategory.techInspection;
    return Stack(
      children: [
        Column(
          children: [
            const SizedBox(height: 8),
            Expanded(child: _buildEmbeddedDocument()),
            const SizedBox(height: 8),
          ],
        ),
        if (!isTech)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.small(
              heroTag: 'scroll_document_landscape',
              onPressed: () {
                if (_documentScrollDown) {
                  _scrollDocumentToBottom();
                } else {
                  _scrollDocumentToTop();
                }
                setState(() => _documentScrollDown = !_documentScrollDown);
              },
              child: Icon(
                _documentScrollDown
                    ? Icons.keyboard_double_arrow_down
                    : Icons.keyboard_double_arrow_up,
              ),
            ),
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
    final isTech = _operationCategory == _OperationCategory.techInspection;

    if (isTech) {
      return Column(
        children: [
          if (showCategory) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<_VehicleCategory>(
                  segments: _availableVehicleCategories
                      .map(
                        (category) => ButtonSegment(
                          value: category,
                          label: Text(_vehicleCategoryLabel(category)),
                        ),
                      )
                      .toList(),
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
          _buildBrandField(compact: compact),
          SizedBox(height: gap),
          _buildPlateNumberField(compact: compact),
          SizedBox(height: gap),
          TextField(
            controller: _vinController,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: const [_UpperCaseTextFormatter()],
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: compact,
              labelText: 'VIN номер *',
              hintText: 'Введите VIN вручную',
            ),
          ),
          SizedBox(height: gap),
          TextField(
            controller: _mileageController,
            textInputAction: TextInputAction.done,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: compact,
              labelText: 'Пробег (км)',
              hintText: '150000',
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (showCategory) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<_VehicleCategory>(
                segments: _availableVehicleCategories
                    .map(
                      (category) => ButtonSegment(
                        value: category,
                        label: Text(_vehicleCategoryLabel(category)),
                      ),
                    )
                    .toList(),
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
        _buildBrandField(compact: compact),
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
          inputFormatters: const [_UpperCaseTextFormatter()],
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: compact,
            labelText: 'VIN номер *',
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
            isLoading:
                (kind == _PhotoKind.vin && _isRecognizingVin) ||
                (kind == _PhotoKind.mileage && _isRecognizingMileage),
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
