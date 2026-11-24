import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/survey_site.dart';
import '../../data/repositories/site_repository.dart';
import '../../domain/entities/version_vector.dart';

class SurveySiteFormScreen extends StatefulWidget {
  const SurveySiteFormScreen({required this.siteRepository, super.key});

  final SiteRepository siteRepository;

  @override
  State<SurveySiteFormScreen> createState() {
    return _SurveySiteFormScreenState();
  }
}

class _SurveySiteFormScreenState extends State<SurveySiteFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';

    if (name.isEmpty) {
      return 'Enter a site name.';
    }

    if (name.length < 2) {
      return 'The site name must contain at least 2 characters.';
    }

    if (name.length > 100) {
      return 'The site name cannot exceed 100 characters.';
    }

    return null;
  }

  String? _validateLatitude(String? value) {
    final text = value?.trim() ?? '';

    if (text.isEmpty) {
      return 'Enter a latitude.';
    }

    final latitude = double.tryParse(text);

    if (latitude == null) {
      return 'Enter a valid number.';
    }

    if (latitude < -90 || latitude > 90) {
      return 'Latitude must be between -90 and 90.';
    }

    return null;
  }

  String? _validateLongitude(String? value) {
    final text = value?.trim() ?? '';

    if (text.isEmpty) {
      return 'Enter a longitude.';
    }

    final longitude = double.tryParse(text);

    if (longitude == null) {
      return 'Enter a valid number.';
    }

    if (longitude < -180 || longitude > 180) {
      return 'Longitude must be between -180 and 180.';
    }

    return null;
  }

  Future<void> _saveSite() async {
    if (_isSaving) {
      return;
    }

    final formState = _formKey.currentState;

    if (formState == null || !formState.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final now = DateTime.now().toUtc();

    final site = SurveySite(
      id: const Uuid().v4(),
      name: _nameController.text.trim(),
      latitude: double.parse(_latitudeController.text.trim()),
      longitude: double.parse(_longitudeController.text.trim()),
      createdAt: now,
      updatedAt: now,
      versionVector: VersionVector(),
    );

    try {
      await widget.siteRepository.addSite(site);

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
        _errorMessage = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Survey Site')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Icon(
                Icons.add_location_alt_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Create a survey site',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The site will be saved locally and queued for '
                'synchronization.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 28),
              TextFormField(
                controller: _nameController,
                enabled: !_isSaving,
                textInputAction: TextInputAction.next,
                validator: _validateName,
                decoration: const InputDecoration(
                  labelText: 'Site name',
                  hintText: 'Example: Al Majaz Survey Area',
                  prefixIcon: Icon(Icons.business_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _latitudeController,
                enabled: !_isSaving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                textInputAction: TextInputAction.next,
                validator: _validateLatitude,
                decoration: const InputDecoration(
                  labelText: 'Latitude',
                  hintText: 'Example: 25.3284',
                  prefixIcon: Icon(Icons.north),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _longitudeController,
                enabled: !_isSaving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                textInputAction: TextInputAction.done,
                validator: _validateLongitude,
                onFieldSubmitted: (_) => _saveSite(),
                decoration: const InputDecoration(
                  labelText: 'Longitude',
                  hintText: 'Example: 55.3763',
                  prefixIcon: Icon(Icons.east),
                  border: OutlineInputBorder(),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Could not save the site: $_errorMessage',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isSaving ? null : _saveSite,
                icon: _isSaving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_isSaving ? 'Saving site...' : 'Save survey site'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
