import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../../domain/entities/sync_status.dart';
import '../../domain/entities/version_vector.dart';

class Observation extends Equatable {
  const Observation({
    required this.id,
    required this.siteId,
    this.temperature,
    this.humidity,
    this.pm25,
    this.notes,
    this.photoPath,
    this.weatherData,
    required this.createdAt,
    required this.updatedAt,
    required this.versionVector,
    this.fieldModifiedAt = const {},
    this.syncStatus = SyncStatus.pending,
  });

  final String id;
  final String siteId;
  final double? temperature;
  final double? humidity;
  final double? pm25;
  final String? notes;
  final String? photoPath;
  final Map<String, dynamic>? weatherData;
  final DateTime createdAt;
  final DateTime updatedAt;
  final VersionVector versionVector;
  final Map<String, DateTime> fieldModifiedAt;
  final SyncStatus syncStatus;

  int get changeCount {
    return versionVector.versions.values.fold(
      0,
      (total, count) => total + count,
    );
  }

  Observation copyWith({
    String? id,
    String? siteId,
    double? temperature,
    double? humidity,
    double? pm25,
    String? notes,
    String? photoPath,
    Map<String, dynamic>? weatherData,
    DateTime? createdAt,
    DateTime? updatedAt,
    VersionVector? versionVector,
    Map<String, DateTime>? fieldModifiedAt,
    SyncStatus? syncStatus,
    bool clearTemperature = false,
    bool clearHumidity = false,
    bool clearPm25 = false,
    bool clearNotes = false,
    bool clearPhotoPath = false,
    bool clearWeatherData = false,
  }) {
    return Observation(
      id: id ?? this.id,
      siteId: siteId ?? this.siteId,
      temperature: clearTemperature ? null : temperature ?? this.temperature,
      humidity: clearHumidity ? null : humidity ?? this.humidity,
      pm25: clearPm25 ? null : pm25 ?? this.pm25,
      notes: clearNotes ? null : notes ?? this.notes,
      photoPath: clearPhotoPath ? null : photoPath ?? this.photoPath,
      weatherData: clearWeatherData ? null : weatherData ?? this.weatherData,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      versionVector: versionVector ?? this.versionVector,
      fieldModifiedAt: fieldModifiedAt ?? this.fieldModifiedAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'site_id': siteId,
      'temperature': temperature,
      'humidity': humidity,
      'pm25': pm25,
      'notes': notes,
      'photo_path': photoPath,
      'weather_data': weatherData == null ? null : jsonEncode(weatherData),
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'version_vector': jsonEncode(versionVector.toJson()),
      'field_modified_at': jsonEncode(
        fieldModifiedAt.map(
          (field, timestamp) =>
              MapEntry(field, timestamp.toUtc().toIso8601String()),
        ),
      ),
      'sync_status': syncStatus.name,
    };
  }

  factory Observation.fromMap(Map<String, dynamic> map) {
    return Observation(
      id: map['id'] as String,
      siteId: map['site_id'] as String,
      temperature: (map['temperature'] as num?)?.toDouble(),
      humidity: (map['humidity'] as num?)?.toDouble(),
      pm25: (map['pm25'] as num?)?.toDouble(),
      notes: map['notes'] as String?,
      photoPath: map['photo_path'] as String?,
      weatherData: _decodeOptionalJsonMap(map['weather_data']),
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      versionVector: VersionVector.fromJson(
        _decodeRequiredJsonMap(map['version_vector']),
      ),
      fieldModifiedAt: _decodeFieldTimestamps(map['field_modified_at']),
      syncStatus: SyncStatus.fromName(map['sync_status'] as String?),
    );
  }

  Map<String, dynamic> toRemoteJson() {
    return {
      'id': id,
      'siteId': siteId,
      'temperature': temperature,
      'humidity': humidity,
      'pm25': pm25,
      'notes': notes,
      'photoPath': photoPath,
      'weatherData': weatherData,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'versionVector': versionVector.toJson(),
      'fieldModifiedAt': fieldModifiedAt.map(
        (field, timestamp) =>
            MapEntry(field, timestamp.toUtc().toIso8601String()),
      ),
    };
  }

  static Map<String, dynamic> _decodeRequiredJsonMap(dynamic value) {
    return _decodeOptionalJsonMap(value) ?? <String, dynamic>{};
  }

  static Map<String, dynamic>? _decodeOptionalJsonMap(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    if (value is String && value.trim().isNotEmpty) {
      final decoded = jsonDecode(value);

      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    }

    throw const FormatException('Expected a valid JSON object.');
  }

  static Map<String, DateTime> _decodeFieldTimestamps(dynamic value) {
    final decoded = _decodeOptionalJsonMap(value);

    if (decoded == null) {
      return <String, DateTime>{};
    }

    final timestamps = <String, DateTime>{};

    for (final entry in decoded.entries) {
      final timestamp = entry.value;

      if (timestamp is String) {
        timestamps[entry.key] = DateTime.parse(timestamp).toUtc();
      }
    }

    return timestamps;
  }

  @override
  List<Object?> get props => [
    id,
    siteId,
    temperature,
    humidity,
    pm25,
    notes,
    photoPath,
    weatherData,
    createdAt,
    updatedAt,
    versionVector,
    fieldModifiedAt,
    syncStatus,
  ];
}
