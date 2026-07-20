import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _defaultServerUrl = String.fromEnvironment(
  'SERVER_URL',
  defaultValue: 'https://autolab.glasscenter.kg',
);
const _carViewsAsset = 'assets/car_views.jpeg';

void main() {
  runApp(const AutoInspectionApp());
}

class AutoInspectionApp extends StatelessWidget {
  const AutoInspectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Авто лаборатория',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late Future<_AppStorage> _storageFuture;

  @override
  void initState() {
    super.initState();
    _storageFuture = _AppStorage.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AppStorage>(
      future: _storageFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final storage = snapshot.data!;
        if (storage.sessionKey == null) {
          return _LoginPage(storage: storage);
        }

        return _HomePage(storage: storage);
      },
    );
  }
}

class _LoginPage extends StatefulWidget {
  const _LoginPage({required this.storage});

  final _AppStorage storage;

  @override
  State<_LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<_LoginPage> {
  late final TextEditingController _serverController;
  late final TextEditingController _loginController;
  late final TextEditingController _passwordController;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(text: widget.storage.serverUrl);
    _loginController = TextEditingController(
      text: widget.storage.lastLogin ?? '',
    );
    _passwordController = TextEditingController(
      text: widget.storage.lastPassword ?? '',
    );
  }

  @override
  void dispose() {
    _serverController.dispose();
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final serverUrl = _serverController.text.trim();
      final api = _ApiClient(serverUrl: serverUrl);
      final result = await api.login(
        login: _loginController.text.trim(),
        password: _passwordController.text,
      );

      await widget.storage.setServerUrl(serverUrl);
      await widget.storage.setLastLogin(
        login: _loginController.text.trim(),
        password: _passwordController.text,
      );
      await widget.storage.setSession(
        sessionKey: result.sessionKey,
        userLabel: result.userLabel,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => _HomePage(storage: widget.storage)),
      );
    } catch (error) {
      setState(() => _error = _humanError(error));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Авторизация')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _serverController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Адрес сервера',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _loginController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Логин',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              onSubmitted: (_) => _isLoading ? null : _login(),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Пароль',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isLoading ? null : _login,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: const Text('Войти'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              _StatusBox(text: _error!, isError: true),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomePage extends StatefulWidget {
  const _HomePage({required this.storage});

  final _AppStorage storage;

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  Future<void> _logout() async {
    try {
      await _ApiClient(
        serverUrl: widget.storage.serverUrl,
        sessionKey: widget.storage.sessionKey,
      ).logout();
    } catch (_) {
      // Local logout still matters if the server is unreachable.
    }

    await widget.storage.clearSession();

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => _LoginPage(storage: widget.storage)),
    );
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final draftsCount = widget.storage.drafts.length;
    final todaySentCount = widget.storage.sent.where(_isToday).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Техосмотр'),
        actions: [
          IconButton(
            tooltip: 'Выйти',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isLandscape =
                constraints.maxWidth >= 720 &&
                constraints.maxWidth > constraints.maxHeight;
            final contentWidth = isLandscape
                ? constraints.maxWidth * 0.6
                : constraints.maxWidth;

            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: contentWidth,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _StatusBox(
                      text:
                          'Пользователь: ${widget.storage.userLabel ?? '-'}\nСервер: ${widget.storage.serverUrl}',
                    ),
                    const SizedBox(height: 16),
                    _MenuButton(
                      title: 'Новый осмотр',
                      subtitle: 'Создать осмотр',
                      onTap: () =>
                          _open(_InspectionFormPage(storage: widget.storage)),
                    ),
                    const SizedBox(height: 10),
                    _MenuButton(
                      title: 'Черновики',
                      subtitle: 'Не отправлено: $draftsCount',
                      onTap: () => _open(_DraftsPage(storage: widget.storage)),
                    ),
                    const SizedBox(height: 10),
                    _MenuButton(
                      title: 'Реестр',
                      subtitle: 'Сегодня отправлено: $todaySentCount',
                      onTap: () =>
                          _open(_RegisterPage(storage: widget.storage)),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InspectionFormPage extends StatefulWidget {
  const _InspectionFormPage({required this.storage, this.initialDraft});

  final _AppStorage storage;
  final _InspectionDraft? initialDraft;

  @override
  State<_InspectionFormPage> createState() => _InspectionFormPageState();
}

class _InspectionFormPageState extends State<_InspectionFormPage> {
  final _plateController = TextEditingController();
  final _brandController = TextEditingController();
  final _vinController = TextEditingController();
  final _picker = ImagePicker();
  final Map<_PhotoKind, String> _photos = {};
  final Map<_PhotoKind, DateTime> _photoTakenAt = {};
  bool _isSaving = false;
  bool _isRecognizingVin = false;
  bool _isCompleted = false;
  String? _status;
  bool _statusIsError = false;
  late String _draftId;
  Timer? _autoSaveTimer;

  bool get _isEditingDraft => widget.initialDraft != null;

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft;
    _draftId = draft?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    if (draft != null) {
      _plateController.text = draft.plateNumber;
      _brandController.text = draft.brand;
      _vinController.text = draft.vin;
      _photos.addAll(draft.photos);
      _photoTakenAt.addAll(draft.photoTakenAt);
    }
    _plateController.addListener(_scheduleAutoSave);
    _brandController.addListener(_scheduleAutoSave);
    _vinController.addListener(_scheduleAutoSave);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    if (!_isCompleted) {
      _autoSaveDraft();
    }
    _plateController.dispose();
    _brandController.dispose();
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

      final savedPath = await _persistPhoto(image, kind);
      setState(() {
        _photos[kind] = savedPath;
        _photoTakenAt[kind] = DateTime.now();
        _status = 'Фото "${kind.label}" готово.';
        _statusIsError = false;
      });
      await _autoSaveDraft();

      if (kind == _PhotoKind.vin) {
        await _recognizeVin(savedPath);
      }
    } catch (error) {
      setState(() {
        _status = _humanError(error);
        _statusIsError = true;
      });
    }
  }

  Future<void> _recognizeVin(String path) async {
    setState(() {
      _isRecognizingVin = true;
      _status = 'Распознаю VIN...';
      _statusIsError = false;
    });

    try {
      final api = _ApiClient(
        serverUrl: widget.storage.serverUrl,
        sessionKey: widget.storage.sessionKey,
      );
      final vin = await api.recognizeVin(path);

      if (!mounted) {
        return;
      }

      setState(() {
        _vinController.text = vin;
        _status = vin.isEmpty
            ? 'VIN не распознан. Можно ввести вручную.'
            : 'VIN распознан: $vin';
        _statusIsError = vin.isEmpty;
      });
      await _autoSaveDraft();
    } catch (error) {
      await _handleActionError(error);
    } finally {
      if (mounted) {
        setState(() => _isRecognizingVin = false);
      }
    }
  }

  Future<String> _persistPhoto(XFile image, _PhotoKind kind) async {
    final directory = await getApplicationDocumentsDirectory();
    final inspectionsDir = Directory('${directory.path}/inspection_photos');
    if (!await inspectionsDir.exists()) {
      await inspectionsDir.create(recursive: true);
    }

    final extension = _extensionForPath(image.path);
    final target = File(
      '${inspectionsDir.path}/${_draftId}_${kind.key}$extension',
    );
    return File(image.path).copy(target.path).then((file) => file.path);
  }

  Future<void> _sendInspection() async {
    final draft = _buildDraft(requireBrand: true, requireAllPhotos: true);
    if (draft == null) {
      return;
    }

    setState(() {
      _isSaving = true;
      _status = 'Отправляю осмотр...';
      _statusIsError = false;
    });

    try {
      final api = _ApiClient(
        serverUrl: widget.storage.serverUrl,
        sessionKey: widget.storage.sessionKey,
      );
      final sent = await api.createInspection(draft);
      final sentWithPhotos = sent.copyWithPhotos(draft.photos);

      await widget.storage.removeDraft(draft.id);
      await widget.storage.addSent(sentWithPhotos);
      _isCompleted = true;

      if (!mounted) {
        return;
      }

      setState(() {
        _status = 'Осмотр отправлен. ID: ${sentWithPhotos.remoteId}';
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
    final plate = _plateController.text.trim().toUpperCase();
    final brand = _brandController.text.trim();
    final vin = _vinController.text.trim().toUpperCase();

    if (!requireBrand &&
        plate.isEmpty &&
        brand.isEmpty &&
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

    final missing = _PhotoKind.values
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
      plateNumber: plate,
      brand: brand,
      vin: vin,
      photos: Map<_PhotoKind, String>.from(_photos),
      photoTakenAt: Map<_PhotoKind, DateTime>.from(_photoTakenAt),
      createdAt: widget.initialDraft?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isTabletLandscape = size.width >= 900 && size.width > size.height;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditingDraft ? 'Черновик' : 'Новый осмотр'),
        actions: [
          TextButton.icon(
            onPressed: _goHome,
            icon: const Icon(Icons.home),
            label: const Text('Домой'),
          ),
        ],
      ),
      body: SafeArea(
        child: isTabletLandscape
            ? _buildTabletLandscapeForm()
            : _buildPhoneForm(),
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
        const SizedBox(height: 16),
        _buildSendButton(),
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
                _buildFields(compact: true),
                if (_status != null) ...[
                  const SizedBox(height: 10),
                  Flexible(
                    child: _StatusBox(text: _status!, isError: _statusIsError),
                  ),
                ] else
                  const Spacer(),
                const SizedBox(height: 10),
                _buildSendButton(),
              ],
            ),
          ),
          const SizedBox(width: 14),
          const VerticalDivider(width: 1),
          const SizedBox(width: 14),
          Expanded(
            child: _buildPhotoGrid(
              columns: 3,
              childAspectRatio: 1.22,
              spacing: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFields({bool compact = false}) {
    final gap = compact ? 8.0 : 12.0;
    return Column(
      children: [
        TextField(
          controller: _plateController,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: compact,
            labelText: 'Гос номер (необязательно)',
            hintText: '01KG123ABC',
          ),
        ),
        SizedBox(height: gap),
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
          controller: _vinController,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: compact,
            labelText: 'VIN',
            hintText: 'Распознается после фото VIN',
            suffixIcon: _isRecognizingVin
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
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
        for (final kind in _PhotoKind.values)
          _PhotoTile(
            label: kind.label,
            path: _photos[kind],
            onTap: _isSaving || _isRecognizingVin
                ? null
                : () => _takePhoto(kind),
          ),
      ],
    );
  }

  Widget _buildSendButton() {
    return SizedBox(
      height: 48,
      child: FilledButton(
        onPressed: _isSaving || _isRecognizingVin ? null : _sendInspection,
        child: _isSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Отправить'),
      ),
    );
  }
}

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
    final drafts = widget.storage.drafts;

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
    final title = [
      if (draft.brand.isNotEmpty) draft.brand else 'Без марки',
      if (draft.plateNumber.isNotEmpty) draft.plateNumber,
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
                    Text('VIN: ${draft.vin.isEmpty ? '-' : draft.vin}'),
                    Text(
                      'Фото: $photoCount/6 • ${_formatDate(draft.updatedAt)}',
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: photoCount / _PhotoKind.values.length,
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
      if (item.plateNumber.isNotEmpty) item.plateNumber,
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
      if (item.plateNumber.isNotEmpty) item.plateNumber,
    ].join(' ');
    final details = _StatusBox(
      text:
          '$title\n'
          'Гос номер: ${item.plateNumber.isEmpty ? '-' : item.plateNumber}\n'
          'Марка: ${item.brand}\n'
          'VIN: ${item.vin.isEmpty ? '-' : item.vin}\n'
          'ID: ${item.remoteId}\n'
          'Дата: ${_formatDate(item.sentAt)}',
    );
    final photos = _ReadonlyPhotoGrid(
      photos: item.photos,
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
  const _ReadonlyPhotoGrid({required this.photos, required this.columns});

  final Map<_PhotoKind, String> photos;
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

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        backgroundColor: colorScheme.surfaceContainerLow,
        foregroundColor: colorScheme.onSurface,
        side: BorderSide(color: colorScheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.label,
    required this.path,
    required this.onTap,
  });

  final String label;
  final String? path;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (path == null)
              ColoredBox(
                color: colorScheme.surfaceContainerHighest,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Opacity(
                        opacity: 0.2,
                        child: Image.asset(
                          _carViewsAsset,
                          fit: BoxFit.contain,
                          color: colorScheme.onSurface,
                          colorBlendMode: BlendMode.srcIn,
                        ),
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Сфотографировать',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              Image.file(
                File(path!),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return ColoredBox(
                    color: colorScheme.surfaceContainerHighest,
                    child: Center(child: Text(label)),
                  );
                },
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                color: Colors.black.withValues(alpha: 0.56),
                child: Text(
                  path == null ? label : '$label готово',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBox extends StatelessWidget {
  const _StatusBox({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: isError ? colorScheme.error : colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          text,
          style: TextStyle(
            color: isError ? colorScheme.error : colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

enum _PhotoKind {
  front('front_photo', 'Спереди'),
  rear('rear_photo', 'Сзади'),
  left('left_photo', 'Слева'),
  right('right_photo', 'Справа'),
  mileage('mileage_photo', 'Пробег'),
  vin('vin_photo', 'VIN');

  const _PhotoKind(this.apiField, this.label);

  final String apiField;
  final String label;

  String get key => apiField;
}

class _InspectionDraft {
  const _InspectionDraft({
    required this.id,
    required this.plateNumber,
    required this.brand,
    required this.vin,
    required this.photos,
    required this.photoTakenAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String plateNumber;
  final String brand;
  final String vin;
  final Map<_PhotoKind, String> photos;
  final Map<_PhotoKind, DateTime> photoTakenAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'plate_number': plateNumber,
      'brand': brand,
      'vin': vin,
      'photos': photos.map((key, value) => MapEntry(key.apiField, value)),
      'photo_taken_at': photoTakenAt.map(
        (key, value) => MapEntry(key.apiField, value.toIso8601String()),
      ),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static _InspectionDraft fromJson(Map<String, dynamic> json) {
    final rawPhotos = Map<String, dynamic>.from(json['photos'] as Map? ?? {});
    final rawPhotoTakenAt = Map<String, dynamic>.from(
      json['photo_taken_at'] as Map? ?? {},
    );
    final photos = <_PhotoKind, String>{};
    final photoTakenAt = <_PhotoKind, DateTime>{};
    for (final kind in _PhotoKind.values) {
      final path = rawPhotos[kind.apiField];
      if (path is String && path.isNotEmpty) {
        photos[kind] = path;
      }

      final rawTakenAt = rawPhotoTakenAt[kind.apiField];
      final takenAt = rawTakenAt is String
          ? DateTime.tryParse(rawTakenAt)
          : null;
      if (takenAt != null) {
        photoTakenAt[kind] = takenAt;
      }
    }

    return _InspectionDraft(
      id: json['id'] as String,
      plateNumber: json['plate_number'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      vin: json['vin'] as String? ?? '',
      photos: photos,
      photoTakenAt: photoTakenAt,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class _SentInspection {
  const _SentInspection({
    required this.remoteId,
    required this.plateNumber,
    required this.brand,
    required this.vin,
    required this.photos,
    required this.sentAt,
  });

  final int remoteId;
  final String plateNumber;
  final String brand;
  final String vin;
  final Map<_PhotoKind, String> photos;
  final DateTime sentAt;

  _SentInspection copyWithPhotos(Map<_PhotoKind, String> photos) {
    return _SentInspection(
      remoteId: remoteId,
      plateNumber: plateNumber,
      brand: brand,
      vin: vin,
      photos: Map<_PhotoKind, String>.from(photos),
      sentAt: sentAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'remote_id': remoteId,
      'plate_number': plateNumber,
      'brand': brand,
      'vin': vin,
      'photos': photos.map((key, value) => MapEntry(key.apiField, value)),
      'sent_at': sentAt.toIso8601String(),
    };
  }

  static _SentInspection fromJson(Map<String, dynamic> json) {
    final rawPhotos = Map<String, dynamic>.from(json['photos'] as Map? ?? {});
    final photos = <_PhotoKind, String>{};
    for (final kind in _PhotoKind.values) {
      final path = rawPhotos[kind.apiField];
      if (path is String && path.isNotEmpty) {
        photos[kind] = path;
      }
    }

    return _SentInspection(
      remoteId: json['remote_id'] as int? ?? 0,
      plateNumber: json['plate_number'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      vin: json['vin'] as String? ?? '',
      photos: photos,
      sentAt:
          DateTime.tryParse(json['sent_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class _LoginResult {
  const _LoginResult({required this.sessionKey, required this.userLabel});

  final String sessionKey;
  final String userLabel;
}

class _ApiClient {
  const _ApiClient({required this.serverUrl, this.sessionKey});

  final String serverUrl;
  final String? sessionKey;

  Future<_LoginResult> login({
    required String login,
    required String password,
  }) async {
    final response = await http
        .post(
          _uri('/api/auth/login/'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'login': login, 'password': password}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        throw _AuthException(response.body);
      }
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final sessionKey = data['session_key'] as String?;
    if (sessionKey == null || sessionKey.isEmpty) {
      throw Exception('Сервер не вернул session_key.');
    }

    final user = data['user'] as Map<String, dynamic>? ?? {};
    final branch = user['branch'] as Map<String, dynamic>?;
    final userLabel = branch == null
        ? '${user['login'] ?? login}'
        : '${user['login'] ?? login} / ${branch['name']}';

    return _LoginResult(sessionKey: sessionKey, userLabel: userLabel);
  }

  Future<void> logout() async {
    await http
        .post(_uri('/api/auth/logout/'), headers: _authHeaders())
        .timeout(const Duration(seconds: 10));
  }

  Future<_SentInspection> createInspection(_InspectionDraft draft) async {
    final request = http.MultipartRequest('POST', _uri('/api/inspections/'));
    request.headers.addAll(_authHeaders());
    request.fields.addAll({
      'plate_number': draft.plateNumber,
      'brand': draft.brand,
      'vin': draft.vin,
    });

    for (final kind in _PhotoKind.values) {
      final path = draft.photos[kind];
      if (path == null) {
        throw Exception('Нет фото: ${kind.label}');
      }

      request.files.add(await _multipartPhoto(kind.apiField, path));
      request.fields['${kind.apiField}_taken_at'] =
          (draft.photoTakenAt[kind] ?? draft.createdAt).toIso8601String();
    }

    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 60),
    );
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        throw _AuthException(response.body);
      }
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return _SentInspection(
      remoteId: data['id'] as int? ?? 0,
      plateNumber: data['plate_number'] as String? ?? draft.plateNumber,
      brand: data['brand'] as String? ?? draft.brand,
      vin: data['vin'] as String? ?? draft.vin,
      photos: const {},
      sentAt: DateTime.now(),
    );
  }

  Future<String> recognizeVin(String vinPhotoPath) async {
    final request = http.MultipartRequest('POST', _uri('/api/recognize-vin/'));
    request.headers.addAll(_authHeaders());
    request.files.add(await _multipartPhoto('vin_photo', vinPhotoPath));

    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 45),
    );
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        throw _AuthException(response.body);
      }
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['vin'] as String? ?? '').trim().toUpperCase();
  }

  Future<http.MultipartFile> _multipartPhoto(String field, String path) async {
    final mimeType = lookupMimeType(path) ?? 'image/jpeg';
    final mediaType = MediaType.parse(mimeType);
    return http.MultipartFile.fromPath(field, path, contentType: mediaType);
  }

  Map<String, String> _authHeaders() {
    final key = sessionKey;
    if (key == null || key.isEmpty) {
      return {};
    }

    return {'X-Session-Key': key};
  }

  Uri _uri(String path) {
    final normalized = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
    return Uri.parse('$normalized$path');
  }
}

class _AppStorage {
  _AppStorage(this._prefs) {
    serverUrl = _prefs.getString('server_url') ?? _defaultServerUrl;
    lastLogin = _prefs.getString('last_login');
    lastPassword = _prefs.getString('last_password');
    sessionKey = _prefs.getString('session_key');
    userLabel = _prefs.getString('user_label');
    drafts = _decodeList(_prefs.getString('drafts'), _InspectionDraft.fromJson);
    sent = _decodeList(
      _prefs.getString('sent_inspections'),
      _SentInspection.fromJson,
    );
  }

  final SharedPreferences _prefs;
  late String serverUrl;
  String? lastLogin;
  String? lastPassword;
  String? sessionKey;
  String? userLabel;
  late List<_InspectionDraft> drafts;
  late List<_SentInspection> sent;

  static Future<_AppStorage> load() async {
    return _AppStorage(await SharedPreferences.getInstance());
  }

  Future<void> setServerUrl(String value) async {
    serverUrl = value;
    await _prefs.setString('server_url', value);
  }

  Future<void> setLastLogin({
    required String login,
    required String password,
  }) async {
    lastLogin = login;
    lastPassword = password;
    await _prefs.setString('last_login', login);
    await _prefs.setString('last_password', password);
  }

  Future<void> setSession({
    required String sessionKey,
    required String userLabel,
  }) async {
    this.sessionKey = sessionKey;
    this.userLabel = userLabel;
    await _prefs.setString('session_key', sessionKey);
    await _prefs.setString('user_label', userLabel);
  }

  Future<void> clearSession() async {
    sessionKey = null;
    userLabel = null;
    await _prefs.remove('session_key');
    await _prefs.remove('user_label');
  }

  Future<void> upsertDraft(_InspectionDraft draft) async {
    drafts.removeWhere((item) => item.id == draft.id);
    drafts.insert(0, draft);
    await _saveDrafts();
  }

  Future<void> removeDraft(String id) async {
    drafts.removeWhere((item) => item.id == id);
    await _saveDrafts();
  }

  Future<void> addSent(_SentInspection inspection) async {
    sent.insert(0, inspection);
    await _prefs.setString(
      'sent_inspections',
      jsonEncode(sent.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _saveDrafts() async {
    await _prefs.setString(
      'drafts',
      jsonEncode(drafts.map((item) => item.toJson()).toList()),
    );
  }

  List<T> _decodeList<T>(
    String? value,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (value == null || value.isEmpty) {
      return [];
    }

    final decoded = jsonDecode(value) as List<dynamic>;
    return decoded.whereType<Map<String, dynamic>>().map(fromJson).toList();
  }
}

class _AuthException implements Exception {
  const _AuthException(this.details);

  final String details;

  @override
  String toString() => details;
}

String _humanError(Object error) {
  if (error is _AuthException) {
    return 'Сессия сброшена.\n'
        'Этот пользователь вошел на другом устройстве, в web или в админке. '
        'Войдите заново, черновик сохранен.\n'
        'Детали: ${error.details}';
  }

  if (error is SocketException) {
    return 'SocketException\nНет подключения к серверу.\nДетали: ${error.message}';
  }

  if (error is TimeoutException) {
    return 'TimeoutException\nСервер не ответил вовремя.\nДетали: ${error.message ?? error.toString()}';
  }

  if (error is FormatException) {
    return 'FormatException\nНеверный формат данных.\nДетали: ${error.message}';
  }

  return '${error.runtimeType}\n${error.toString()}';
}

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}.${two(value.month)}.${value.year} '
      '${two(value.hour)}:${two(value.minute)}';
}

String _formatDateOnly(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}.${two(value.month)}.${value.year}';
}

bool _isToday(_SentInspection item) {
  final now = DateTime.now();
  final sentAt = item.sentAt;
  return sentAt.year == now.year &&
      sentAt.month == now.month &&
      sentAt.day == now.day;
}

String _extensionForPath(String path) {
  final lastSegment = path.split(Platform.pathSeparator).last;
  final dotIndex = lastSegment.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex == lastSegment.length - 1) {
    return '.jpg';
  }

  return lastSegment.substring(dotIndex);
}
