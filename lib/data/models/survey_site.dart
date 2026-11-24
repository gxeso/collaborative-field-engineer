import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../../domain/entities/sync_status.dart';
import '../../domain/entities/version_vector.dart';

class SurveySite extends Equatable {
  const SurveySite({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.regionGeoJson,
    required this.createdAt,
    required this.updatedAt,
    required this.versionVector,
    this.syncStatus = SyncStatus.pending,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String? regionGeoJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  final VersionVector versionVector;
  final SyncStatus syncStatus;

  int get changeCount {
    return versionVector.versions.values.fold(
      0,
      (total, count) => total + count,
    );
  }

  SurveySite copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    String? regionGeoJson,
    bool clearRegionGeoJson = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    VersionVector? versionVector,
    SyncStatus? syncStatus,
  }) {
    return SurveySite(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      regionGeoJson: clearRegionGeoJson
          ? null
          : regionGeoJson ?? this.regionGeoJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      versionVector: versionVector ?? this.versionVector,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'region_geojson': regionGeoJson,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'version_vector': jsonEncode(versionVector.toJson()),
      'sync_status': syncStatus.name,
    };
  }

  factory SurveySite.fromMap(Map<String, dynamic> map) {
    return SurveySite(
      id: map['id'] as String,
      name: map['name'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      regionGeoJson: map['region_geojson'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      versionVector: VersionVector.fromJson(
        _decodeVersionVector(map['version_vector']),
      ),
      syncStatus: SyncStatus.fromName(map['sync_status'] as String?),
    );
  }

  Map<String, dynamic> toRemoteJson() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'regionGeoJson': regionGeoJson,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'versionVector': versionVector.toJson(),
    };
  }

  static Map<String, dynamic> _decodeVersionVector(dynamic value) {
    if (value == null) {
      return <String, dynamic>{};
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

    throw const FormatException('Survey site version vector is invalid.');
  }

  @override
  List<Object?> get props => [
    id,
    name,
    latitude,
    longitude,
    regionGeoJson,
    createdAt,
    updatedAt,
    versionVector,
    syncStatus,
  ];
}
