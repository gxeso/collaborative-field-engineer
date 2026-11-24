import 'package:flutter/material.dart';

import '../../data/models/observation.dart';
import '../../data/repositories/observation_repository.dart';

class ObservationEditScreen extends StatefulWidget {
  const ObservationEditScreen({
    required this.observation,
    required this.siteName,
    required this.observationRepository,
    super.key,
  });

  final Observation observation;
  final String siteName;
  final ObservationRepository observationRepository;

  @override
  State<ObservationEditScreen> createState() => _ObservationEditScreenState();
}

class _ObservationEditScreenState extends State<ObservationEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _temperatureController;
  late final TextEditingController _humidityController;
  late final TextEditingController _pm25Controller;
  late final TextEditingController _notesController;
  late final TextEditingController _photoPathController;

  bool _isSaving = false;
  bool _isDeleting = false;
  String? _errorMessage;

  bool get _isBusy => _isSaving || _isDeleting;

  @override
  void initState() {
    super.initState();

    final observation = widget.observation;

    _temperatureController = TextEditingController(
      text: _formatOptionalNumber(observation.temperature),
    );

    _humidityController = TextEditingController(
      text: _formatOptionalNumber(observation.humidity),
    );

    _pm25Controller = TextEditingController(
      text: _formatOptionalNumber(observation.pm25),
    );

    _notesController = TextEditingController(text: observation.notes ?? '');

    _photoPathController = TextEditingController(
      text: observation.photoPath ?? '',
    );
  }

  @override
  void dispose() {
    _temperatureController.dispose();
    _humidityController.dispose();
    _pm25Controller.dispose();
    _notesController.dispose();
    _photoPathController.dispose();
    super.dispose();
  }

  String _formatOptionalNumber(double? value) {
    if (value == null) {
      return '';
    }

    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toString();
  }

  String? _validateTemperature(String? value) {
    final text = value?.trim() ?? '';

    if (text.isEmpty) {
      return null;
    }

    final temperature = double.tryParse(text);

    if (temperature == null) {
      return 'Enter a valid temperature.';
    }

    if (temperature < -100 || temperature > 100) {
      return 'Temperature must be between -100°C and 100°C.';
    }

    return null;
  }

  String? _validateHumidity(String? value) {
    final text = value?.trim() ?? '';

    if (text.isEmpty) {
      return null;
    }

    final humidity = double.tryParse(text);

    if (humidity == null) {
      return 'Enter a valid humidity value.';
    }

    if (humidity < 0 || humidity > 100) {
      return 'Humidity must be between 0% and 100%.';
    }

    return null;
  }

  String? _validatePm25(String? value) {
    final text = value?.trim() ?? '';

    if (text.isEmpty) {
      return null;
    }

    final pm25 = double.tryParse(text);

    if (pm25 == null) {
      return 'Enter a valid PM2.5 value.';
    }

    if (pm25 < 0) {
      return 'PM2.5 cannot be negative.';
    }

    return null;
  }

  String? _validatePhotoPath(String? value) {
    final text = value?.trim() ?? '';

    if (text.length > 1000) {
      return 'The photo path is too long.';
    }

    return null;
  }

  double? _parseOptionalNumber(TextEditingController controller) {
    final text = controller.text.trim();

    if (text.isEmpty) {
      return null;
    }

    return double.parse(text);
  }

  String? _parseOptionalText(TextEditingController controller) {
    final text = controller.text.trim();

    return text.isEmpty ? null : text;
  }

  bool _hasObservationData() {
    return _temperatureController.text.trim().isNotEmpty ||
        _humidityController.text.trim().isNotEmpty ||
        _pm25Controller.text.trim().isNotEmpty ||
        _notesController.text.trim().isNotEmpty ||
        _photoPathController.text.trim().isNotEmpty;
  }

  void _clearError() {
    if (_errorMessage == null) {
      return;
    }

    setState(() {
      _errorMessage = null;
    });
  }

  Future<void> _saveObservation() async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _errorMessage = null;
    });

    final formIsValid = _formKey.currentState?.validate() ?? false;

    if (!formIsValid) {
      return;
    }

    if (!_hasObservationData()) {
      setState(() {
        _errorMessage = 'Enter at least one measurement, note, or photo path.';
      });

      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final currentObservation = widget.observation;

      final updatedObservation = Observation(
        id: currentObservation.id,
        siteId: currentObservation.siteId,
        temperature: _parseOptionalNumber(_temperatureController),
        humidity: _parseOptionalNumber(_humidityController),
        pm25: _parseOptionalNumber(_pm25Controller),
        notes: _parseOptionalText(_notesController),
        photoPath: _parseOptionalText(_photoPathController),
        weatherData: currentObservation.weatherData,
        createdAt: currentObservation.createdAt,
        updatedAt: DateTime.now().toUtc(),
        versionVector: currentObservation.versionVector,
        fieldModifiedAt: currentObservation.fieldModifiedAt,
        syncStatus: currentObservation.syncStatus,
      );

      await widget.observationRepository.updateObservation(updatedObservation);

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage =
            'The observation could not be updated locally. '
            'Please try again.\n$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _requestDelete() async {
    if (_isBusy) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(Icons.delete_outline),
          title: const Text('Delete observation?'),
          content: const Text(
            'This observation will be removed locally and a delete '
            'operation will be added to the synchronization queue.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _deleteObservation();
    }
  }

  Future<void> _deleteObservation() async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    try {
      await widget.observationRepository.deleteObservation(
        widget.observation.id,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage =
            'The observation could not be deleted locally. '
            'Please try again.\n$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isBusy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit Observation'),
          actions: [
            IconButton(
              onPressed: _isBusy ? null : _requestDelete,
              tooltip: 'Delete observation',
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            onChanged: _clearError,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _ObservationInformationCard(
                  siteName: widget.siteName,
                  observation: widget.observation,
                ),
                const SizedBox(height: 24),
                Text(
                  'Measurements',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Update the measurements recorded for this observation.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _temperatureController,
                  enabled: !_isBusy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  textInputAction: TextInputAction.next,
                  validator: _validateTemperature,
                  decoration: const InputDecoration(
                    labelText: 'Temperature',
                    hintText: 'Example: 25.4',
                    suffixText: '°C',
                    prefixIcon: Icon(Icons.thermostat_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _humidityController,
                  enabled: !_isBusy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  validator: _validateHumidity,
                  decoration: const InputDecoration(
                    labelText: 'Humidity',
                    hintText: 'Example: 63.5',
                    suffixText: '%',
                    prefixIcon: Icon(Icons.water_drop_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _pm25Controller,
                  enabled: !_isBusy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  validator: _validatePm25,
                  decoration: const InputDecoration(
                    labelText: 'PM2.5',
                    hintText: 'Example: 12.8',
                    suffixText: 'µg/m³',
                    prefixIcon: Icon(Icons.air),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Additional information',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesController,
                  enabled: !_isBusy,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    hintText: 'Describe the conditions or findings...',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.notes),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _photoPathController,
                  enabled: !_isBusy,
                  validator: _validatePhotoPath,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _saveObservation(),
                  decoration: const InputDecoration(
                    labelText: 'Photo path',
                    hintText: 'Optional local photo path',
                    prefixIcon: Icon(Icons.photo_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 20),
                  _OperationErrorCard(message: _errorMessage!),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isBusy ? null : _saveObservation,
                  icon: _isSaving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_isSaving ? 'Saving changes...' : 'Save changes'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _isBusy ? null : _requestDelete,
                  icon: _isDeleting
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                  label: Text(
                    _isDeleting
                        ? 'Deleting observation...'
                        : 'Delete observation',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ObservationInformationCard extends StatelessWidget {
  const _ObservationInformationCard({
    required this.siteName,
    required this.observation,
  });

  final String siteName;
  final Observation observation;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.science_outlined, color: colorScheme.onPrimaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Survey site'),
                  const SizedBox(height: 4),
                  Text(
                    siteName,
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Created ${_formatDateTime(observation.createdAt)}',
                    style: TextStyle(color: colorScheme.onPrimaryContainer),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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

class _OperationErrorCard extends StatelessWidget {
  const _OperationErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
