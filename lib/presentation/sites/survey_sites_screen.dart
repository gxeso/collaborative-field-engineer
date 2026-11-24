import 'package:flutter/material.dart';

import '../../data/models/survey_site.dart';
import '../../domain/entities/sync_status.dart';
import '../../di/app_dependencies.dart';
import '../observations/observations_screen.dart';
import 'survey_site_form_screen.dart';

class SurveySitesScreen extends StatefulWidget {
  const SurveySitesScreen({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<SurveySitesScreen> createState() => _SurveySitesScreenState();
}

class _SurveySitesScreenState extends State<SurveySitesScreen> {
  List<SurveySite> _sites = const [];

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSites();
  }

  Future<void> _loadSites() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final sites = await widget.dependencies.siteRepository.getSites();

      if (!mounted) {
        return;
      }

      setState(() {
        _sites = sites;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _createSite() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SurveySiteFormScreen(
          siteRepository: widget.dependencies.siteRepository,
        ),
      ),
    );

    if (created == true && mounted) {
      await _loadSites();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Survey site saved locally.')),
      );
    }
  }

  Future<void> _openSite(SurveySite site) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ObservationsScreen(
          siteId: site.id,
          siteName: site.name,
          observationRepository: widget.dependencies.observationRepository,
        ),
      ),
    );

    if (mounted) {
      await _loadSites();
    }
  }

  int _countForStatus(SyncStatus status) {
    return _sites.where((site) => site.syncStatus == status).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Survey Sites'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadSites,
            tooltip: 'Refresh sites',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _createSite,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add site'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadSites,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              sliver: SliverToBoxAdapter(
                child: _SitesSummary(
                  total: _sites.length,
                  pending: _countForStatus(SyncStatus.pending),
                  failed: _countForStatus(SyncStatus.failed),
                  conflicts: _countForStatus(SyncStatus.conflict),
                ),
              ),
            ),
            if (_isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorMessage != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _SitesErrorState(
                  message: _errorMessage!,
                  onRetry: _loadSites,
                ),
              )
            else if (_sites.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptySitesState(onCreate: _createSite),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                sliver: SliverList.separated(
                  itemCount: _sites.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final site = _sites[index];

                    return _SurveySiteCard(
                      site: site,
                      onTap: () => _openSite(site),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SitesSummary extends StatelessWidget {
  const _SitesSummary({
    required this.total,
    required this.pending,
    required this.failed,
    required this.conflicts,
  });

  final int total;
  final int pending;
  final int failed;
  final int conflicts;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.map_outlined,
              color: colorScheme.onPrimaryContainer,
              size: 32,
            ),
            const SizedBox(height: 12),
            Text(
              'Field Survey Sites',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$total ${total == 1 ? 'site' : 'sites'} stored locally',
              style: TextStyle(color: colorScheme.onPrimaryContainer),
            ),
            if (pending > 0 || failed > 0 || conflicts > 0) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (pending > 0)
                    _SummaryChip(
                      label: '$pending pending',
                      icon: Icons.schedule,
                      color: Colors.orange,
                    ),
                  if (failed > 0)
                    _SummaryChip(
                      label: '$failed failed',
                      icon: Icons.error_outline,
                      color: Colors.red,
                    ),
                  if (conflicts > 0)
                    _SummaryChip(
                      label: '$conflicts conflicts',
                      icon: Icons.warning_amber,
                      color: Colors.deepOrange,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SurveySiteCard extends StatelessWidget {
  const _SurveySiteCard({required this.site, required this.onTap});

  final SurveySite site;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(child: Icon(_statusIcon(site.syncStatus))),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      site.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 17),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${site.latitude.toStringAsFixed(5)}, '
                            '${site.longitude.toStringAsFixed(5)}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _SyncStatusChip(status: site.syncStatus),
                        const Spacer(),
                        Text(
                          'View observations',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _statusIcon(SyncStatus status) {
    return switch (status) {
      SyncStatus.pending => Icons.schedule,
      SyncStatus.synced => Icons.cloud_done_outlined,
      SyncStatus.failed => Icons.error_outline,
      SyncStatus.conflict => Icons.warning_amber,
    };
  }
}

class _SyncStatusChip extends StatelessWidget {
  const _SyncStatusChip({required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final configuration = switch (status) {
      SyncStatus.pending => (
        label: 'Pending',
        icon: Icons.schedule,
        color: Colors.orange,
      ),
      SyncStatus.synced => (
        label: 'Synced',
        icon: Icons.cloud_done_outlined,
        color: Colors.green,
      ),
      SyncStatus.failed => (
        label: 'Failed',
        icon: Icons.error_outline,
        color: Colors.red,
      ),
      SyncStatus.conflict => (
        label: 'Conflict',
        icon: Icons.warning_amber,
        color: Colors.deepOrange,
      ),
    };

    return Chip(
      avatar: Icon(configuration.icon, size: 16, color: configuration.color),
      label: Text(configuration.label),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: configuration.color.withValues(alpha: 0.45)),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 17, color: color),
      label: Text(label),
      backgroundColor: Theme.of(context).colorScheme.surface,
      side: BorderSide(color: color.withValues(alpha: 0.45)),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _EmptySitesState extends StatelessWidget {
  const _EmptySitesState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_location_alt_outlined,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 18),
            Text(
              'No survey sites yet',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Create your first survey site. It will be stored locally '
              'and remain available while offline.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Create first site'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SitesErrorState extends StatelessWidget {
  const _SitesErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Could not load survey sites',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
