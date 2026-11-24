import 'dart:developer' as developer;

import '../data/services/replica_identity_service.dart';

Future<void> verifyReplicaIdentity(
  ReplicaIdentityService identityService,
) async {
  final firstActorId = await identityService.getActorId();

  final secondActorId = await identityService.getActorId();

  if (firstActorId != secondActorId) {
    throw StateError('Replica actor ID changed between reads.');
  }

  developer.log(
    'Replica identity verified: $firstActorId',
    name: 'ReplicaIdentityCheck',
  );
}
