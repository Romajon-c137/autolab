part of 'main.dart';

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
