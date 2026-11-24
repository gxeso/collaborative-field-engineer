import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/observation.dart';
import '../../data/repositories/observation_repository.dart';
import '../../domain/entities/version_vector.dart';

class ObservationFormScreen extends StatefulWidget {
  const ObservationFormScreen({
    required this.siteId,
    required this.siteName,
    required this.observationRepository,
    super.key,
  });

  final String siteId;
  final String siteName;
  final ObservationRepository observationRepository;

  @override
  State<ObservationFormScreen> createState() => _ObservationFormScreenState();
}

class _ObservationFormScreenState extends State<ObservationFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _temperatureController = TextEditingController();
  final _humidityController = TextEditingController();
  final _pm25Controller = TextEditingController();
  final _notesController = TextEditingController();
  final _photoPathController = TextEditingController();

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _temperatureController.dispose();
    _humidityController.dispose();
    _pm25Controller.dispose();
    _notesController.dispose();
    _photoPathController.dispose();
    super.dispose();
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

  Future<void> _saveObservation() async {
    if (_isSaving) {
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
      final timestamp = DateTime.now().toUtc();

      final observation = Observation(
        id: const Uuid().v4(),
        siteId: widget.siteId,
        temperature: _parseOptionalNumber(_temperatureController),
        humidity: _parseOptionalNumber(_humidityController),
        pm25: _parseOptionalNumber(_pm25Controller),
        notes: _parseOptionalText(_notesController),
        photoPath: _parseOptionalText(_photoPathController),
        createdAt: timestamp,
        updatedAt: timestamp,
        versionVector: VersionVector(),
        fieldModifiedAt: const {},
      );

      await widget.observationRepository.addObservation(observation);

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
            'The observation could not be saved locally. '
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

  void _clearError() {
    if (_errorMessage == null) {
      return;
    }

    setState(() {
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Observation')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          onChanged: _clearError,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _SiteCard(siteName: widget.siteName),
              const SizedBox(height: 24),
              Text(
                'Measurements',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Enter the measurements available for this survey site.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _temperatureController,
                enabled: !_isSaving,
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
                enabled: !_isSaving,
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
                enabled: !_isSaving,
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
                enabled: !_isSaving,
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
                enabled: !_isSaving,
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
                _ErrorCard(message: _errorMessage!),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isSaving ? null : _saveObservation,
                icon: _isSaving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  _isSaving ? 'Saving locally...' : 'Save observation',
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _isSaving
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SiteCard extends StatelessWidget {
  const _SiteCard({required this.siteName});

  final String siteName;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.primaryContainer,
      child: ListTile(
        leading: Icon(
          Icons.location_on_outlined,
          color: colorScheme.onPrimaryContainer,
        ),
        title: const Text('Selected survey site'),
        subtitle: Text(
          siteName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

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
