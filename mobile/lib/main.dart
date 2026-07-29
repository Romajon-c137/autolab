import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'document_html_view.dart';

const _defaultServerUrl = String.fromEnvironment(
  'SERVER_URL',
  defaultValue: 'https://autolab.glasscenter.kg',
);
const _appVersion = '1.0.1';
const _appTitle = 'Авто лаборатория v$_appVersion';
const _pdfChannel = MethodChannel('autolab/pdf');
void main() {
  runApp(const AutoInspectionApp());
}

class AutoInspectionApp extends StatelessWidget {
  const AutoInspectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: _appTitle,
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
        userFullName: result.userFullName,
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
  @override
  void initState() {
    super.initState();
    _refreshUserProfile();
  }

  Future<void> _refreshUserProfile() async {
    try {
      final profile = await _ApiClient(
        serverUrl: widget.storage.serverUrl,
        sessionKey: widget.storage.sessionKey,
      ).currentUser();
      await widget.storage.setUserProfile(
        userLabel: profile.userLabel,
        userFullName: profile.userFullName,
      );
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      // Existing local session can still be used if profile refresh fails.
    }
  }

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
        title: const Text(_appTitle),
        actions: [
          IconButton(
            tooltip: 'Выйти',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        tooltip: 'Подпись',
        onPressed: () => _open(_SignaturePage(storage: widget.storage)),
        child: const Icon(Icons.draw),
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
                    _HomeSummary(
                      userLabel: widget.storage.userLabel ?? '-',
                      version: _appVersion,
                    ),
                    const SizedBox(height: 16),
                    _MenuButton(
                      title: 'Новый осмотр',
                      subtitle: 'Создать осмотр',
                      primary: true,
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

class _SignaturePage extends StatefulWidget {
  const _SignaturePage({required this.storage});

  final _AppStorage storage;

  @override
  State<_SignaturePage> createState() => _SignaturePageState();
}

class _SignaturePageState extends State<_SignaturePage> {
  late List<List<Offset>> _strokes;
  String? _status;

  @override
  void initState() {
    super.initState();
    _strokes = widget.storage.loadSignature();
  }

  void _startStroke(DragStartDetails details) {
    setState(() {
      _status = null;
      _strokes.add([details.localPosition]);
    });
  }

  void _appendPoint(DragUpdateDetails details) {
    if (_strokes.isEmpty) {
      return;
    }

    setState(() {
      _strokes.last.add(details.localPosition);
    });
  }

  Future<void> _save() async {
    await widget.storage.saveSignature(_strokes);
    if (!mounted) {
      return;
    }

    setState(() => _status = 'Подпись сохранена.');
  }

  Future<void> _clear() async {
    setState(() {
      _strokes = [];
      _status = null;
    });
    await widget.storage.saveSignature(_strokes);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Подпись')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.storage.userLabel ?? 'Пользователь',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: _startStroke,
                      onPanUpdate: _appendPoint,
                      child: CustomPaint(
                        painter: _SignaturePainter(strokes: _strokes),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
              if (_status != null) ...[
                const SizedBox(height: 12),
                _StatusBox(text: _status!),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _clear,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Очистить'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Сохранить'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter({required this.strokes});

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.isEmpty) {
        continue;
      }

      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 1.6, paint);
        continue;
      }

      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) {
    return true;
  }
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
  _VehicleCategory _vehicleCategory = _VehicleCategory.m1;
  bool _isSaving = false;
  bool _showDocument = false;
  bool _documentSigned = false;
  String _documentStateJson = '';
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
      _brandController.text = draft.brand;
      _countryController.text = draft.country;
      _vinController.text = draft.vin;
      _vehicleCategory = draft.vehicleCategory;
      _documentStateJson = draft.documentStateJson;
      _photos.addAll(draft.photos);
      _photoTakenAt.addAll(draft.photoTakenAt);
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

  Future<void> _continueToDocument() async {
    final draft = _buildDraft(requireBrand: true);
    if (draft == null) {
      return;
    }

    await widget.storage.upsertDraft(draft);

    if (!mounted) {
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
      plateNumber: '',
      brand: _brandController.text.trim(),
      country: _countryController.text.trim(),
      vehicleCategory: _vehicleCategory,
      vin: _vinController.text.trim().toUpperCase(),
      documentStateJson: _documentStateJson,
      photos: Map<_PhotoKind, String>.from(_photos),
      photoTakenAt: Map<_PhotoKind, DateTime>.from(_photoTakenAt),
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
      plateNumber: '',
      brand: brand,
      country: country,
      vehicleCategory: _vehicleCategory,
      vin: vin,
      documentStateJson: _documentStateJson,
      photos: Map<_PhotoKind, String>.from(_photos),
      photoTakenAt: Map<_PhotoKind, DateTime>.from(_photoTakenAt),
      createdAt: widget.initialDraft?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isLandscape =
                MediaQuery.orientationOf(context) == Orientation.landscape;
            final isWideLandscape = isLandscape && constraints.maxWidth >= 700;
            final isTabletLandscape =
                isLandscape && constraints.maxWidth >= 900;

            if (_showDocument) {
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
                : _buildPhotoGrid(
                    columns: 3,
                    childAspectRatio: 1.22,
                    spacing: 8,
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
          Expanded(child: _buildEmbeddedDocument()),
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
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: _buildEmbeddedDocument(),
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
        for (final kind in _PhotoKind.values)
          _PhotoTile(
            label: kind.label,
            asset: kind.asset,
            path: _photos[kind],
            onTap: () => _takePhoto(kind),
          ),
      ],
    );
  }

  Widget _buildFormActions() {
    if (_showDocument) {
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
        onPressed: _continueToDocument,
        iconAlignment: IconAlignment.end,
        label: const Text('Далее'),
        icon: const Icon(Icons.arrow_forward),
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
    final drafts = widget.storage.drafts.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

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
                    Text(
                      'Страна: ${draft.country.isEmpty ? '-' : draft.country}',
                    ),
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
          'Марка: ${item.brand}\n'
          'Страна: ${item.country.isEmpty ? '-' : item.country}\n'
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

class _HomeSummary extends StatelessWidget {
  const _HomeSummary({required this.userLabel, required this.version});

  final String userLabel;
  final String version;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
        color: colorScheme.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.account_circle, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                userLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.info_outline, size: 18, color: colorScheme.secondary),
            const SizedBox(width: 4),
            Text(
              'v$version',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        backgroundColor: primary
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerLow,
        foregroundColor: primary
            ? colorScheme.onPrimaryContainer
            : colorScheme.onSurface,
        side: BorderSide(
          color: primary ? colorScheme.primary : colorScheme.outlineVariant,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: primary ? 16 : 14,
          vertical: primary ? 20 : 16,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Row(
        children: [
          if (primary) ...[
            Icon(Icons.add_circle, size: 30, color: colorScheme.primary),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style:
                      (primary
                              ? Theme.of(context).textTheme.titleLarge
                              : Theme.of(context).textTheme.titleMedium)
                          ?.copyWith(fontWeight: FontWeight.w800),
                ),
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
    required this.asset,
    required this.path,
    required this.onTap,
  });

  final String label;
  final String asset;
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
                color: Colors.white,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: const BoxDecoration(color: Colors.white),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Image.asset(
                            asset,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const SizedBox.shrink(),
                          ),
                        ),
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
  front('front_photo', 'Спереди', 'assets/front.jpg'),
  right('right_photo', 'Справа', 'assets/right.jpg'),
  rear('rear_photo', 'Сзади', 'assets/back.jpg'),
  left('left_photo', 'Слева', 'assets/left.jpg'),
  vin('vin_photo', 'VIN', 'assets/vin.jpg'),
  mileage('mileage_photo', 'Пробег', 'assets/left-1.jpg');

  const _PhotoKind(this.apiField, this.label, this.asset);

  final String apiField;
  final String label;
  final String asset;

  String get key => apiField;
}

enum _VehicleCategory {
  m1('M1'),
  m2('M2'),
  m3('M3'),
  n1('N1'),
  n2('N2'),
  n3('N3');

  const _VehicleCategory(this.apiValue);

  final String apiValue;

  static _VehicleCategory fromApi(String? value) {
    return switch (value?.toUpperCase()) {
      'M2' => _VehicleCategory.m2,
      'M3' => _VehicleCategory.m3,
      'N1' => _VehicleCategory.n1,
      'N2' => _VehicleCategory.n2,
      'N3' => _VehicleCategory.n3,
      _ => _VehicleCategory.m1,
    };
  }
}

class _InspectionDraft {
  const _InspectionDraft({
    required this.id,
    required this.plateNumber,
    required this.brand,
    required this.country,
    required this.vehicleCategory,
    required this.vin,
    required this.documentStateJson,
    required this.photos,
    required this.photoTakenAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String plateNumber;
  final String brand;
  final String country;
  final _VehicleCategory vehicleCategory;
  final String vin;
  final String documentStateJson;
  final Map<_PhotoKind, String> photos;
  final Map<_PhotoKind, DateTime> photoTakenAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'plate_number': plateNumber,
      'brand': brand,
      'country': country,
      'vehicle_category': vehicleCategory.apiValue,
      'vin': vin,
      'document_state': documentStateJson,
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
      country: json['country'] as String? ?? '',
      vehicleCategory: _VehicleCategory.fromApi(
        json['vehicle_category'] as String?,
      ),
      vin: json['vin'] as String? ?? '',
      documentStateJson: json['document_state'] as String? ?? '',
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
    required this.country,
    required this.vehicleCategory,
    required this.vin,
    required this.photos,
    required this.sentAt,
  });

  final int remoteId;
  final String plateNumber;
  final String brand;
  final String country;
  final _VehicleCategory vehicleCategory;
  final String vin;
  final Map<_PhotoKind, String> photos;
  final DateTime sentAt;

  _SentInspection copyWithPhotos(Map<_PhotoKind, String> photos) {
    return _SentInspection(
      remoteId: remoteId,
      plateNumber: plateNumber,
      brand: brand,
      country: country,
      vehicleCategory: vehicleCategory,
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
      'country': country,
      'vehicle_category': vehicleCategory.apiValue,
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
      country: json['country'] as String? ?? '',
      vehicleCategory: _VehicleCategory.fromApi(
        json['vehicle_category'] as String?,
      ),
      vin: json['vin'] as String? ?? '',
      photos: photos,
      sentAt:
          DateTime.tryParse(json['sent_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

Future<_SentInspection> _sendInspectionDraft({
  required _AppStorage storage,
  required _InspectionDraft draft,
  required String expertName,
  required String? signatureSvg,
  required String documentStateJson,
}) async {
  final documentPdfBytes = await _createInspectionPdf(
    draft: draft,
    expertName: expertName,
    signatureSvg: signatureSvg,
    documentStateJson: documentStateJson,
  );
  final api = _ApiClient(
    serverUrl: storage.serverUrl,
    sessionKey: storage.sessionKey,
  );
  final sent = await api.createInspection(
    draft,
    documentPdfBytes: documentPdfBytes,
  );
  final sentWithPhotos = sent.copyWithPhotos(draft.photos);

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
    'assets/${draft.vehicleCategory.apiValue}_document_clean.html',
  );
  final params = Uri(
    queryParameters: {
      'brand': draft.brand,
      'country': draft.country,
      'vehicle_category': draft.vehicleCategory.apiValue,
      'vin': draft.vin,
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

class _LoginResult {
  const _LoginResult({
    required this.sessionKey,
    required this.userLabel,
    required this.userFullName,
  });

  final String sessionKey;
  final String userLabel;
  final String userFullName;
}

class _UserProfileResult {
  const _UserProfileResult({
    required this.userLabel,
    required this.userFullName,
  });

  final String userLabel;
  final String userFullName;
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
    final userFullName = '${user['full_name'] ?? user['login'] ?? login}'
        .trim();

    return _LoginResult(
      sessionKey: sessionKey,
      userLabel: userLabel,
      userFullName: userFullName.isEmpty ? login : userFullName,
    );
  }

  Future<void> logout() async {
    await http
        .post(_uri('/api/auth/logout/'), headers: _authHeaders())
        .timeout(const Duration(seconds: 10));
  }

  Future<_UserProfileResult> currentUser() async {
    final response = await http
        .get(_uri('/api/auth/me/'), headers: _authHeaders())
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        throw _AuthException(response.body);
      }
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final user = data['user'] as Map<String, dynamic>? ?? {};
    final login = '${user['login'] ?? ''}'.trim();
    final branch = user['branch'] as Map<String, dynamic>?;
    final userLabel = branch == null ? login : '$login / ${branch['name']}';
    final userFullName = '${user['full_name'] ?? login}'.trim();

    return _UserProfileResult(
      userLabel: userLabel.isEmpty ? '-' : userLabel,
      userFullName: userFullName.isEmpty ? login : userFullName,
    );
  }

  Future<_SentInspection> createInspection(
    _InspectionDraft draft, {
    required List<int> documentPdfBytes,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/api/inspections/'));
    request.headers.addAll(_authHeaders());
    request.fields.addAll({
      'plate_number': draft.plateNumber,
      'brand': draft.brand,
      'country': draft.country,
      'vehicle_category': draft.vehicleCategory.apiValue,
      'vin': draft.vin,
    });

    for (final kind in _PhotoKind.values) {
      final path = draft.photos[kind];
      if (path == null) {
        continue;
      }

      request.files.add(await _multipartPhoto(kind.apiField, path));
      request.fields['${kind.apiField}_taken_at'] =
          (draft.photoTakenAt[kind] ?? draft.createdAt).toIso8601String();
    }

    request.files.add(
      http.MultipartFile.fromBytes(
        'document_pdf',
        documentPdfBytes,
        filename: 'inspection_${draft.id}.pdf',
        contentType: MediaType.parse('application/pdf'),
      ),
    );

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
      country: data['country'] as String? ?? draft.country,
      vehicleCategory: _VehicleCategory.fromApi(
        data['vehicle_category'] as String? ?? draft.vehicleCategory.apiValue,
      ),
      vin: data['vin'] as String? ?? draft.vin,
      photos: const {},
      sentAt: DateTime.now(),
    );
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
    userFullName = _prefs.getString('user_full_name');
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
  String? userFullName;
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
    required String userFullName,
  }) async {
    this.sessionKey = sessionKey;
    await _prefs.setString('session_key', sessionKey);
    await setUserProfile(userLabel: userLabel, userFullName: userFullName);
  }

  Future<void> setUserProfile({
    required String userLabel,
    required String userFullName,
  }) async {
    this.userLabel = userLabel;
    this.userFullName = userFullName;
    await _prefs.setString('user_label', userLabel);
    await _prefs.setString('user_full_name', userFullName);
  }

  Future<void> clearSession() async {
    sessionKey = null;
    userLabel = null;
    userFullName = null;
    await _prefs.remove('session_key');
    await _prefs.remove('user_label');
    await _prefs.remove('user_full_name');
  }

  String get _signatureKey {
    final owner = userLabel ?? lastLogin ?? 'default';
    return 'signature_${base64Url.encode(utf8.encode(owner))}';
  }

  List<List<Offset>> loadSignature() {
    final raw = _prefs.getString(_signatureKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((stroke) {
      final points = stroke as List<dynamic>;
      return points.map((point) {
        final data = point as Map<String, dynamic>;
        return Offset(
          (data['x'] as num).toDouble(),
          (data['y'] as num).toDouble(),
        );
      }).toList();
    }).toList();
  }

  String? signatureSvg() {
    final strokes = loadSignature();
    final points = strokes.expand((stroke) => stroke).toList();
    if (points.isEmpty) {
      return null;
    }

    var minX = points.first.dx;
    var minY = points.first.dy;
    var maxX = points.first.dx;
    var maxY = points.first.dy;
    for (final point in points.skip(1)) {
      if (point.dx < minX) minX = point.dx;
      if (point.dy < minY) minY = point.dy;
      if (point.dx > maxX) maxX = point.dx;
      if (point.dy > maxY) maxY = point.dy;
    }

    const padding = 8.0;
    final width = (maxX - minX + padding * 2).clamp(32.0, 2000.0);
    final height = (maxY - minY + padding * 2).clamp(24.0, 1200.0);

    String number(double value) => value.toStringAsFixed(2);
    final paths = strokes.where((stroke) => stroke.isNotEmpty).map((stroke) {
      final start = stroke.first;
      final buffer = StringBuffer(
        'M ${number(start.dx - minX + padding)} ${number(start.dy - minY + padding)}',
      );
      for (final point in stroke.skip(1)) {
        buffer.write(
          ' L ${number(point.dx - minX + padding)} ${number(point.dy - minY + padding)}',
        );
      }
      return '<path d="$buffer" />';
    }).join();

    return '<svg xmlns="http://www.w3.org/2000/svg" '
        'viewBox="0 0 ${number(width)} ${number(height)}">'
        '<g fill="none" stroke="#000" stroke-width="3" '
        'stroke-linecap="round" stroke-linejoin="round">$paths</g></svg>';
  }

  Future<void> saveSignature(List<List<Offset>> strokes) async {
    final encoded = strokes.map((stroke) {
      return stroke.map((point) {
        return {'x': point.dx, 'y': point.dy};
      }).toList();
    }).toList();

    await _prefs.setString(_signatureKey, jsonEncode(encoded));
  }

  Future<void> upsertDraft(_InspectionDraft draft) async {
    final index = drafts.indexWhere((item) => item.id == draft.id);
    if (index == -1) {
      drafts.add(draft);
    } else {
      drafts[index] = draft;
    }
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

String _shortExpertName(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length < 2) {
    return value.trim();
  }

  return '${parts.first} ${parts[1].characters.first.toUpperCase()}';
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
