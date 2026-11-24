import '../models/observation.dart';

abstract interface class ObservationRepository {
  Future<List<Observation>> getObservations(String siteId);

  Future<Observation?> getObservationById(String id);

  Future<void> addObservation(Observation observation);

  Future<void> updateObservation(Observation observation);

  Future<void> deleteObservation(String id);
}
