enum VersionVectorRelation { equal, before, after, concurrent }

class VersionVector {
  VersionVector([Map<String, int> versions = const {}])
    : versions = Map.unmodifiable(versions);

  final Map<String, int> versions;

  int get changeCount {
    return versions.values.fold(0, (total, count) => total + count);
  }

  factory VersionVector.fromJson(Map<String, dynamic> json) {
    final parsedVersions = <String, int>{};

    for (final entry in json.entries) {
      final actorId = entry.key.trim();
      final value = entry.value;

      if (actorId.isEmpty) {
        continue;
      }

      if (value is int && value >= 0) {
        parsedVersions[actorId] = value;
      } else if (value is num && value >= 0) {
        parsedVersions[actorId] = value.toInt();
      }
    }

    return VersionVector(parsedVersions);
  }

  Map<String, int> toJson() {
    return Map<String, int>.from(versions);
  }

  int versionFor(String actorId) {
    return versions[actorId] ?? 0;
  }

  VersionVector increment(String actorId) {
    final normalizedActorId = actorId.trim();

    if (normalizedActorId.isEmpty) {
      throw ArgumentError.value(
        actorId,
        'actorId',
        'Actor ID cannot be empty.',
      );
    }

    final updatedVersions = Map<String, int>.from(versions);

    updatedVersions[normalizedActorId] = versionFor(normalizedActorId) + 1;

    return VersionVector(updatedVersions);
  }

  VersionVector merge(VersionVector other) {
    final mergedVersions = <String, int>{};

    final actorIds = <String>{...versions.keys, ...other.versions.keys};

    for (final actorId in actorIds) {
      final localVersion = versionFor(actorId);
      final remoteVersion = other.versionFor(actorId);

      mergedVersions[actorId] = localVersion > remoteVersion
          ? localVersion
          : remoteVersion;
    }

    return VersionVector(mergedVersions);
  }

  VersionVectorRelation compareTo(VersionVector other) {
    var hasGreaterVersion = false;
    var hasSmallerVersion = false;

    final actorIds = <String>{...versions.keys, ...other.versions.keys};

    for (final actorId in actorIds) {
      final localVersion = versionFor(actorId);
      final remoteVersion = other.versionFor(actorId);

      if (localVersion > remoteVersion) {
        hasGreaterVersion = true;
      } else if (localVersion < remoteVersion) {
        hasSmallerVersion = true;
      }

      if (hasGreaterVersion && hasSmallerVersion) {
        return VersionVectorRelation.concurrent;
      }
    }

    if (hasGreaterVersion) {
      return VersionVectorRelation.after;
    }

    if (hasSmallerVersion) {
      return VersionVectorRelation.before;
    }

    return VersionVectorRelation.equal;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    if (other is! VersionVector || versions.length != other.versions.length) {
      return false;
    }

    for (final entry in versions.entries) {
      if (other.versions[entry.key] != entry.value) {
        return false;
      }
    }

    return true;
  }

  @override
  int get hashCode {
    final sortedEntries = versions.entries.toList()
      ..sort((first, second) => first.key.compareTo(second.key));

    return Object.hashAll(
      sortedEntries.map((entry) => Object.hash(entry.key, entry.value)),
    );
  }

  @override
  String toString() {
    return 'VersionVector($versions)';
  }
}
