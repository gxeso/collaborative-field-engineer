import 'dart:convert';

import 'package:equatable/equatable.dart';

enum SyncEntityType { site, observation }

enum SyncOperationType { create, update, delete }

enum SyncQueueStatus { pending, processing, synced, failed, conflict }

class SyncOperation extends Equatable {
  const SyncOperation({
    this.queueId,
    required this.operationId,
    required this.entityType,
    required this.entityId,
    required this.operationType,
    required this.payload,
    this.status = SyncQueueStatus.pending,
    this.retryCount = 0,
    this.lastAttemptAt,
    this.nextRetryAt,
    this.errorMessage,
    required this.createdAt,
  });

  final int? queueId;
  final String operationId;
  final SyncEntityType entityType;
  final String entityId;
  final SyncOperationType operationType;
  final Map<String, dynamic> payload;
  final SyncQueueStatus status;
  final int retryCount;
  final DateTime? lastAttemptAt;
  final DateTime? nextRetryAt;
  final String? errorMessage;
  final DateTime createdAt;

  SyncOperation copyWith({
    int? queueId,
    String? operationId,
    SyncEntityType? entityType,
    String? entityId,
    SyncOperationType? operationType,
    Map<String, dynamic>? payload,
    SyncQueueStatus? status,
    int? retryCount,
    DateTime? lastAttemptAt,
    DateTime? nextRetryAt,
    String? errorMessage,
    bool clearLastAttemptAt = false,
    bool clearNextRetryAt = false,
    bool clearErrorMessage = false,
    DateTime? createdAt,
  }) {
    return SyncOperation(
      queueId: queueId ?? this.queueId,
      operationId: operationId ?? this.operationId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operationType: operationType ?? this.operationType,
      payload: payload ?? this.payload,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastAttemptAt: clearLastAttemptAt
          ? null
          : lastAttemptAt ?? this.lastAttemptAt,
      nextRetryAt: clearNextRetryAt ? null : nextRetryAt ?? this.nextRetryAt,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (queueId != null) 'id': queueId,
      'operation_id': operationId,
      'entity_type': entityType.name,
      'entity_id': entityId,
      'operation': operationType.name.toUpperCase(),
      'payload': jsonEncode(payload),
      'status': status.name,
      'retry_count': retryCount,
      'last_attempt': lastAttemptAt?.toUtc().toIso8601String(),
      'next_retry_at': nextRetryAt?.toUtc().toIso8601String(),
      'error_message': errorMessage,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  factory SyncOperation.fromMap(Map<String, dynamic> map) {
    return SyncOperation(
      queueId: map['id'] as int?,
      operationId: map['operation_id'] as String,
      entityType: SyncEntityType.values.byName(map['entity_type'] as String),
      entityId: map['entity_id'] as String,
      operationType: SyncOperationType.values.byName(
        (map['operation'] as String).toLowerCase(),
      ),
      payload: _decodePayload(map['payload']),
      status: SyncQueueStatus.values.byName(map['status'] as String),
      retryCount: map['retry_count'] as int? ?? 0,
      lastAttemptAt: _parseOptionalDateTime(map['last_attempt']),
      nextRetryAt: _parseOptionalDateTime(map['next_retry_at']),
      errorMessage: map['error_message'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }

  static Map<String, dynamic> _decodePayload(dynamic value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }

    if (value is String) {
      final decoded = jsonDecode(value);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    }

    throw const FormatException(
      'Sync operation payload must contain a JSON object.',
    );
  }

  static DateTime? _parseOptionalDateTime(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is! String || value.trim().isEmpty) {
      return null;
    }

    return DateTime.parse(value).toUtc();
  }

  @override
  List<Object?> get props => [
    queueId,
    operationId,
    entityType,
    entityId,
    operationType,
    payload,
    status,
    retryCount,
    lastAttemptAt,
    nextRetryAt,
    errorMessage,
    createdAt,
  ];
}
