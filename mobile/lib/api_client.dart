part of 'main.dart';

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
    required List<int>? documentPdfBytes,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/api/inspections/'));
    request.headers.addAll(_authHeaders());
    request.fields.addAll({
      'operation_type': draft.operationCategory.apiValue,
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

    if (documentPdfBytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'document_pdf',
          documentPdfBytes,
          filename: 'inspection_${draft.id}.pdf',
          contentType: MediaType.parse('application/pdf'),
        ),
      );
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
      operationCategory: _OperationCategory.fromApi(
        data['operation_type'] as String? ?? draft.operationCategory.apiValue,
      ),
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
