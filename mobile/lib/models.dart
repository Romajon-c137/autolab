part of 'main.dart';

enum _PhotoKind {
  application('application_photo', 'Фото заявки', 'assets/vin.jpg'),
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

enum _OperationCategory {
  techInspection('tech_inspection', 'Техосмотр', true),
  sbgts('sbgts', 'СБКТС', true),
  legalization('legalization', 'Легализация', false),
  conversion('conversion', 'Переоборудование', false);

  const _OperationCategory(this.apiValue, this.label, this.hasDocument);

  final String apiValue;
  final String label;
  final bool hasDocument;

  static _OperationCategory fromApi(String? value) {
    return switch (value) {
      'tech_inspection' => _OperationCategory.techInspection,
      'legalization' => _OperationCategory.legalization,
      'conversion' => _OperationCategory.conversion,
      _ => _OperationCategory.sbgts,
    };
  }
}

class _InspectionDraft {
  const _InspectionDraft({
    required this.id,
    required this.operationCategory,
    required this.plateNumber,
    required this.brand,
    required this.country,
    required this.vehicleCategory,
    required this.vin,
    this.mileage,
    required this.documentStateJson,
    required this.photos,
    required this.photoTakenAt,
    required this.conversionPhotos,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final _OperationCategory operationCategory;
  final String plateNumber;
  final String brand;
  final String country;
  final _VehicleCategory vehicleCategory;
  final String vin;
  final int? mileage;
  final String documentStateJson;
  final Map<_PhotoKind, String> photos;
  final Map<_PhotoKind, DateTime> photoTakenAt;
  final List<String> conversionPhotos;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'operation_type': operationCategory.apiValue,
      'plate_number': plateNumber,
      'brand': brand,
      'country': country,
      'vehicle_category': vehicleCategory.apiValue,
      'vin': vin,
      'mileage': mileage,
      'document_state': documentStateJson,
      'photos': photos.map((key, value) => MapEntry(key.apiField, value)),
      'photo_taken_at': photoTakenAt.map(
        (key, value) => MapEntry(key.apiField, value.toIso8601String()),
      ),
      'conversion_photos': conversionPhotos,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static _InspectionDraft fromJson(Map<String, dynamic> json) {
    final rawPhotos = Map<String, dynamic>.from(json['photos'] as Map? ?? {});
    final rawPhotoTakenAt = Map<String, dynamic>.from(
      json['photo_taken_at'] as Map? ?? {},
    );
    final rawConversionPhotos = json['conversion_photos'] as List? ?? [];
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
      operationCategory: _OperationCategory.fromApi(
        json['operation_type'] as String?,
      ),
      plateNumber: json['plate_number'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      country: json['country'] as String? ?? '',
      vehicleCategory: _VehicleCategory.fromApi(
        json['vehicle_category'] as String?,
      ),
      vin: json['vin'] as String? ?? '',
      mileage: json['mileage'] as int?,
      documentStateJson: json['document_state'] as String? ?? '',
      photos: photos,
      photoTakenAt: photoTakenAt,
      conversionPhotos: rawConversionPhotos.whereType<String>().toList(),
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
    required this.operationCategory,
    required this.plateNumber,
    required this.brand,
    required this.country,
    required this.vehicleCategory,
    required this.vin,
    required this.photos,
    required this.conversionPhotos,
    required this.sentAt,
  });

  final int remoteId;
  final _OperationCategory operationCategory;
  final String plateNumber;
  final String brand;
  final String country;
  final _VehicleCategory vehicleCategory;
  final String vin;
  final Map<_PhotoKind, String> photos;
  final List<String> conversionPhotos;
  final DateTime sentAt;

  _SentInspection copyWithPhotos({
    required Map<_PhotoKind, String> photos,
    required List<String> conversionPhotos,
  }) {
    return _SentInspection(
      remoteId: remoteId,
      operationCategory: operationCategory,
      plateNumber: plateNumber,
      brand: brand,
      country: country,
      vehicleCategory: vehicleCategory,
      vin: vin,
      photos: Map<_PhotoKind, String>.from(photos),
      conversionPhotos: List<String>.from(conversionPhotos),
      sentAt: sentAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'remote_id': remoteId,
      'operation_type': operationCategory.apiValue,
      'plate_number': plateNumber,
      'brand': brand,
      'country': country,
      'vehicle_category': vehicleCategory.apiValue,
      'vin': vin,
      'photos': photos.map((key, value) => MapEntry(key.apiField, value)),
      'conversion_photos': conversionPhotos,
      'sent_at': sentAt.toIso8601String(),
    };
  }

  static _SentInspection fromJson(Map<String, dynamic> json) {
    final rawPhotos = Map<String, dynamic>.from(json['photos'] as Map? ?? {});
    final rawConversionPhotos = json['conversion_photos'] as List? ?? [];
    final photos = <_PhotoKind, String>{};
    for (final kind in _PhotoKind.values) {
      final path = rawPhotos[kind.apiField];
      if (path is String && path.isNotEmpty) {
        photos[kind] = path;
      }
    }

    return _SentInspection(
      remoteId: json['remote_id'] as int? ?? 0,
      operationCategory: _OperationCategory.fromApi(
        json['operation_type'] as String?,
      ),
      plateNumber: json['plate_number'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      country: json['country'] as String? ?? '',
      vehicleCategory: _VehicleCategory.fromApi(
        json['vehicle_category'] as String?,
      ),
      vin: json['vin'] as String? ?? '',
      photos: photos,
      conversionPhotos: rawConversionPhotos.whereType<String>().toList(),
      sentAt:
          DateTime.tryParse(json['sent_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
