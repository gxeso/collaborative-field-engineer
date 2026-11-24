import 'package:flutter_test/flutter_test.dart';
import 'package:offline_survey_and_sync_app/domain/entities/version_vector.dart';

void main() {
  group('VersionVector', () {
    test('starts empty', () {
      final vector = VersionVector();

      expect(vector.versions, isEmpty);
      expect(vector.changeCount, 0);
    });

    test('increments the selected actor', () {
      final original = VersionVector({'device-a': 2});

      final updated = original.increment('device-a');

      expect(original.versionFor('device-a'), 2);
      expect(updated.versionFor('device-a'), 3);
      expect(updated.changeCount, 3);
    });

    test('adds an actor that does not exist', () {
      final vector = VersionVector({'device-a': 2});

      final updated = vector.increment('device-b');

      expect(updated.versionFor('device-a'), 2);
      expect(updated.versionFor('device-b'), 1);
      expect(updated.changeCount, 3);
    });

    test('rejects an empty actor ID', () {
      final vector = VersionVector();

      expect(() => vector.increment('   '), throwsArgumentError);
    });

    test('detects equal vectors', () {
      final local = VersionVector({'device-a': 2, 'device-b': 1});

      final remote = VersionVector({'device-a': 2, 'device-b': 1});

      expect(local.compareTo(remote), VersionVectorRelation.equal);
    });

    test('detects when local vector is before remote', () {
      final local = VersionVector({'device-a': 1});

      final remote = VersionVector({'device-a': 2});

      expect(local.compareTo(remote), VersionVectorRelation.before);
    });

    test('detects when local vector is after remote', () {
      final local = VersionVector({'device-a': 3});

      final remote = VersionVector({'device-a': 2});

      expect(local.compareTo(remote), VersionVectorRelation.after);
    });

    test('detects concurrent changes', () {
      final deviceA = VersionVector({'device-a': 3});

      final deviceB = VersionVector({'device-b': 2});

      expect(deviceA.compareTo(deviceB), VersionVectorRelation.concurrent);
    });

    test('merges vectors using highest actor counters', () {
      final deviceA = VersionVector({'device-a': 3});

      final deviceB = VersionVector({'device-b': 2});

      final merged = deviceA.merge(deviceB);

      expect(merged, VersionVector({'device-a': 3, 'device-b': 2}));

      expect(merged.changeCount, 5);
    });

    test('keeps the highest counter for shared actors', () {
      final local = VersionVector({'device-a': 4, 'device-b': 1});

      final remote = VersionVector({'device-a': 2, 'device-b': 3});

      final merged = local.merge(remote);

      expect(merged, VersionVector({'device-a': 4, 'device-b': 3}));

      expect(merged.changeCount, 7);
    });

    test('converts to and from JSON', () {
      final original = VersionVector({'device-a': 3, 'device-b': 2});

      final restored = VersionVector.fromJson(original.toJson());

      expect(restored, original);
      expect(restored.changeCount, 5);
    });
  });
}
