import '../models/survey_site.dart';

abstract interface class SiteRepository {
  Future<List<SurveySite>> getSites();

  Future<SurveySite?> getSiteById(String id);

  Future<void> addSite(SurveySite site);

  Future<void> updateSite(SurveySite site);

  Future<void> deleteSite(String id);
}
