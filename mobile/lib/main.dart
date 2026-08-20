import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'document_html_view.dart';

part 'models.dart';
part 'vehicle_catalog.dart';
part 'inspection_submitter.dart';
part 'api_client.dart';
part 'app_storage.dart';
part 'app_utils.dart';
part 'signature_page.dart';
part 'operation_selection_page.dart';
part 'inspection_form_page.dart';
part 'drafts_page.dart';
part 'register_page.dart';
part 'document_widgets.dart';
part 'shared_widgets.dart';

const _defaultServerUrl = String.fromEnvironment(
  'SERVER_URL',
  defaultValue: 'https://autolab.glasscenter.kg',
);
const _appVersion = '1.0.9';
const _appBuildStamp = '2026-08-19 15:10 +06';
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A4A8A),
        ),
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
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  _LoginChallengeResult? _challenge;

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
    _codeController.dispose();
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
      final challenge = await api.login(
        login: _loginController.text.trim(),
        password: _passwordController.text,
      );

      await widget.storage.setServerUrl(serverUrl);
      await widget.storage.setLastLogin(
        login: _loginController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;
      setState(() => _challenge = challenge);
    } catch (error) {
      setState(() => _error = _humanError(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyCode() async {
    final challenge = _challenge;
    if (challenge == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = _ApiClient(serverUrl: _serverController.text.trim());
      final result = await api.verifyTwoFactor(
        challengeId: challenge.challengeId,
        code: _codeController.text.trim(),
        login: _loginController.text.trim(),
      );

      await widget.storage.setSession(
        sessionKey: result.sessionKey,
        userLabel: result.userLabel,
        userFullName: result.userFullName,
      );

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => _HomePage(storage: widget.storage)),
      );
    } catch (error) {
      setState(() => _error = _humanError(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _backToLogin() {
    setState(() {
      _challenge = null;
      _error = null;
      _codeController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Авторизация'),
        leading: _challenge != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _backToLogin,
              )
            : null,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_challenge == null) ...[
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
            ] else ...[
              _StatusBox(
                text:
                    'Код подтверждения отправлен в WhatsApp на номер '
                    '${_challenge!.phoneMasked}.',
                isError: false,
              ),
              if (_challenge!.debugCode != null) ...[
                const SizedBox(height: 8),
                _StatusBox(
                  text: 'DEBUG код: ${_challenge!.debugCode}',
                  isError: false,
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _codeController,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _isLoading ? null : _verifyCode(),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Код из WhatsApp',
                  hintText: '123456',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isLoading ? null : _verifyCode,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('Подтвердить'),
              ),
            ],
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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.primary,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 8, 18),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Авто лаборатория',
                                    style: TextStyle(
                                      color: cs.onPrimary,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    widget.storage.userLabel ?? '—',
                                    style: TextStyle(
                                      color: cs.onPrimary
                                          .withValues(alpha: 0.75),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Выйти',
                              onPressed: _logout,
                              icon: Icon(
                                Icons.logout,
                                color: cs.onPrimary.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Content
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                        children: [
                          // Stats row
                          Row(
                            children: [
                              Expanded(
                                child: _HomeStatCard(
                                  label: 'Черновики',
                                  value: draftsCount,
                                  icon: Icons.edit_document,
                                  onTap: () => _open(
                                    _DraftsPage(storage: widget.storage),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _HomeStatCard(
                                  label: 'Сегодня отправлено',
                                  value: todaySentCount,
                                  icon: Icons.check_circle_outline,
                                  onTap: () => _open(
                                    _RegisterPage(storage: widget.storage),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          // Primary action
                          FilledButton.icon(
                            onPressed: () => _open(
                              _OperationSelectionPage(storage: widget.storage),
                            ),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            icon: const Icon(Icons.add, size: 22),
                            label: const Text('Новый осмотр'),
                          ),
                          const SizedBox(height: 12),
                          // Secondary actions
                          Row(
                            children: [
                              Expanded(
                                child: _HomeSecondaryButton(
                                  label: 'Черновики',
                                  icon: Icons.folder_open_outlined,
                                  badge: draftsCount > 0
                                      ? '$draftsCount'
                                      : null,
                                  onTap: () => _open(
                                    _DraftsPage(storage: widget.storage),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _HomeSecondaryButton(
                                  label: 'Реестр',
                                  icon: Icons.list_alt_rounded,
                                  onTap: () => _open(
                                    _RegisterPage(storage: widget.storage),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'v$_appVersion · $_appBuildStamp',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
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
