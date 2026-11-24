import 'package:flutter/material.dart';

import '../../data/models/observation.dart';
import '../../data/repositories/observation_repository.dart';
import '../../domain/entities/sync_status.dart';
import 'observation_edit_screen.dart';
import 'observation_form_screen.dart';

class ObservationsScreen extends StatefulWidget {
  const ObservationsScreen({
    required this.siteId,
    required this.siteName,
    required this.observationRepository,
    super.key,
  });

  final String siteId;
  final String siteName;
  final ObservationRepository observationRepository;

  @override
  State<ObservationsScreen> createState() => _ObservationsScreenState();
}

class _ObservationsScreenState extends State<ObservationsScreen> {
  List<Observation> _observations = const [];

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadObservations();
  }

  Future<void> _loadObservations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final observations = await widget.observationRepository.getObservations(
        widget.siteId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _observations = observations;
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

  Future<void> _createObservation() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ObservationFormScreen(
          siteId: widget.siteId,
          siteName: widget.siteName,
          observationRepository: widget.observationRepository,
        ),
      ),
    );

    if (created == true && mounted) {
      await _loadObservations();
    }
  }

  Future<void> _openObservation(Observation observation) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ObservationEditScreen(
          observation: observation,
          siteName: widget.siteName,
          observationRepository: widget.observationRepository,
        ),
      ),
    );

    if (changed == true && mounted) {
      await _loadObservations();
    }
  }

  int _countForStatus(SyncStatus status) {
    return _observations
        .where((observation) => observation.syncStatus == status)
        .length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Observations'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadObservations,
            tooltip: 'Refresh observations',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _createObservation,
        icon: const Icon(Icons.add),
        label: const Text('Add observation'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadObservations,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              sliver: SliverToBoxAdapter(
                child: _SiteHeader(
                  siteName: widget.siteName,
                  observationCount: _observations.length,
                  pendingCount: _countForStatus(SyncStatus.pending),
                  failedCount: _countForStatus(SyncStatus.failed),
                  conflictCount: _countForStatus(SyncStatus.conflict),
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
                child: _ErrorState(
                  message: _errorMessage!,
                  onRetry: _loadObservations,
                ),
              )
            else if (_observations.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(onCreate: _createObservation),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                sliver: SliverList.separated(
                  itemCount: _observations.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final observation = _observations[index];

                    return _ObservationCard(
                      observation: observation,
                      onTap: () {
                        _openObservation(observation);
                      },
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

class _SiteHeader extends StatelessWidget {
  const _SiteHeader({
    required this.siteName,
    required this.observationCount,
    required this.pendingCount,
    required this.failedCount,
    required this.conflictCount,
  });

  final String siteName;
  final int observationCount;
  final int pendingCount;
  final int failedCount;
  final int conflictCount;

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
              Icons.location_on_outlined,
              color: colorScheme.onPrimaryContainer,
            ),
            const SizedBox(height: 10),
            Text(
              siteName,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$observationCount '
              '${observationCount == 1 ? 'observation' : 'observations'} '
              'stored locally',
              style: TextStyle(color: colorScheme.onPrimaryContainer),
            ),
            if (pendingCount > 0 || failedCount > 0 || conflictCount > 0) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (pendingCount > 0)
                    _SummaryChip(
                      label: '$pendingCount pending',
                      icon: Icons.schedule,
                      color: Colors.orange,
                    ),
                  if (failedCount > 0)
                    _SummaryChip(
                      label: '$failedCount failed',
                      icon: Icons.error_outline,
                      color: Colors.red,
                    ),
                  if (conflictCount > 0)
                    _SummaryChip(
                      label: '$conflictCount conflicts',
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

class _ObservationCard extends StatelessWidget {
  const _ObservationCard({required this.observation, required this.onTap});

  final Observation observation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasMeasurements =
        observation.temperature != null ||
        observation.humidity != null ||
        observation.pm25 != null;

    final notes = observation.notes?.trim();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    child: Icon(_statusIcon(observation.syncStatus)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatDateTime(observation.createdAt),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Updated '
                          '${_formatDateTime(observation.updatedAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  _SyncStatusChip(status: observation.syncStatus),
                ],
              ),
              if (hasMeasurements) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (observation.temperature != null)
                      _MeasurementChip(
                        icon: Icons.thermostat,
                        label:
                            '${observation.temperature!.toStringAsFixed(1)} °C',
                      ),
                    if (observation.humidity != null)
                      _MeasurementChip(
                        icon: Icons.water_drop_outlined,
                        label: '${observation.humidity!.toStringAsFixed(1)}%',
                      ),
                    if (observation.pm25 != null)
                      _MeasurementChip(
                        icon: Icons.air,
                        label: 'PM2.5 ${observation.pm25!.toStringAsFixed(1)}',
                      ),
                  ],
                ),
              ],
              if (notes != null && notes.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(notes, maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.history,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${observation.changeCount} local '
                    '${observation.changeCount == 1 ? 'change' : 'changes'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  if (observation.photoPath != null &&
                      observation.photoPath!.trim().isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.photo_outlined, size: 19),
                    ),
                  const Icon(Icons.edit_outlined, size: 19),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right),
                ],
              ),
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

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();

    return '${_twoDigits(local.day)}/'
        '${_twoDigits(local.month)}/'
        '${local.year} at '
        '${_twoDigits(local.hour)}:'
        '${_twoDigits(local.minute)}';
  }

  static String _twoDigits(int value) {
    return value.toString().padLeft(2, '0');
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

class _MeasurementChip extends StatelessWidget {
  const _MeasurementChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      visualDensity: VisualDensity.compact,
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

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
              Icons.science_outlined,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 18),
            Text(
              'No observations yet',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Measurements collected for this survey site will '
              'appear here and remain available while offline.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Add first observation'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

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
              'Could not load observations',
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
