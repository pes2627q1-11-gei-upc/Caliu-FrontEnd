import 'package:flutter/material.dart';

import 'data/auth_api.dart';
import 'data/preferred_radius.dart';
import 'theme/caliu_colors.dart';

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({
    super.key,
    required this.authApi,
    required this.token,
    this.onSessionExpired,
    this.preferredRadius,
  });

  final AuthApi authApi;
  final String token;
  final VoidCallback? onSessionExpired;

  /// On es publica el radi desat perquè el mapa i la cerca el facin servir
  /// (tasca #125). Per defecte, [PreferredRadius.shared].
  final PreferredRadius? preferredRadius;

  /// Límits del slider de radi: els mateixos que el filtre de la cerca.
  static const minRadiusKm = 1.0;
  static const maxRadiusKm = 50.0;
  static const defaultRadiusKm = 10.0;

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  List<String>? _categories;
  Set<String> _selected = {};

  /// Radi d'activitat (tasca #124). Si està desactivat, es desa `null`.
  bool _radiusEnabled = false;
  double _radiusKm = PreferencesScreen.defaultRadiusKm;
  String? _errorMessage;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
      _categories = null;
    });

    try {
      final results = await Future.wait([
        widget.authApi.fetchCategories(),
        widget.authApi.fetchUserPreferences(widget.token),
      ]);
      if (!mounted) return;
      final preferences = results[1] as UserPreferences;
      final radius = preferences.proximitatKm;
      setState(() {
        _categories = results[0] as List<String>;
        _selected = preferences.categories.toSet();
        _radiusEnabled = radius != null;
        if (radius != null) {
          _radiusKm = radius
              .clamp(
                PreferencesScreen.minRadiusKm,
                PreferencesScreen.maxRadiusKm,
              )
              .roundToDouble();
        }
        _loading = false;
      });
    } on AuthApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 401) {
        widget.onSessionExpired?.call();
        Navigator.of(context).pop(false);
        return;
      }
      setState(() {
        _errorMessage = error.message;
        _loading = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'No s’han pogut carregar les categories o preferències. Torna-ho a provar.';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_saving || _categories == null) return;
    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final saved = await widget.authApi.saveUserPreferences(
        token: widget.token,
        categories: _categories!.where(_selected.contains).toList(),
        proximitatKm: _radiusEnabled ? _radiusKm : null,
      );
      (widget.preferredRadius ?? PreferredRadius.shared).set(
        saved.proximitatKm,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AuthApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 401) {
        widget.onSessionExpired?.call();
        Navigator.of(context).pop(false);
        return;
      }
      setState(() {
        _saving = false;
        _errorMessage = error.message;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage =
            'No s’han pogut desar les preferències. Torna-ho a provar.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CaliuColors.beige,
      appBar: AppBar(
        backgroundColor: CaliuColors.maroonDeep,
        foregroundColor: Colors.white,
        title: const Text('Preferències culturals'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _loadError()
          : _content(),
    );
  }

  Widget _loadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: CaliuColors.red),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Torna-ho a provar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Radi d'activitat (H.U #9, tasca #124): s'aplica per defecte al mapa i a
  /// la cerca, al voltant de la ubicació de l'usuari.
  Widget _radiusSection() {
    return Column(
      key: const ValueKey('preferences-radius'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        SwitchListTile(
          key: const ValueKey('preferences-radius-switch'),
          contentPadding: EdgeInsets.zero,
          value: _radiusEnabled,
          onChanged: _saving
              ? null
              : (value) => setState(() => _radiusEnabled = value),
          title: Text(
            'Radi d’activitat',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: CaliuColors.maroon,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            _radiusEnabled
                ? 'El mapa i la cerca mostraran els esdeveniments a menys de '
                      '${_radiusKm.toStringAsFixed(0)} km de la teva ubicació.'
                : 'Sense límit de distància.',
          ),
        ),
        if (_radiusEnabled)
          Row(
            children: [
              Expanded(
                child: Slider(
                  key: const ValueKey('preferences-radius-slider'),
                  min: PreferencesScreen.minRadiusKm,
                  max: PreferencesScreen.maxRadiusKm,
                  divisions: 49,
                  value: _radiusKm,
                  label: '${_radiusKm.toStringAsFixed(0)} km',
                  activeColor: CaliuColors.maroon,
                  onChanged: _saving
                      ? null
                      : (value) =>
                            setState(() => _radiusKm = value.roundToDouble()),
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  '${_radiusKm.toStringAsFixed(0)} km',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: CaliuColors.maroon,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _content() {
    final categories = _categories!;
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (categories.isEmpty)
                        const Text('Ara mateix no hi ha categories disponibles.')
                      else ...[
                      Text(
                        'Tria les categories que t’interessen',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: CaliuColors.maroon,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: categories
                            .map(
                              (category) => FilterChip(
                                label: Text(category),
                                selected: _selected.contains(category),
                                onSelected: _saving
                                    ? null
                                    : (selected) => setState(() {
                                        if (selected) {
                                          _selected.add(category);
                                        } else {
                                          _selected.remove(category);
                                        }
                                      }),
                                selectedColor: CaliuColors.maroon,
                                checkmarkColor: Colors.white,
                                labelStyle: TextStyle(
                                  color: _selected.contains(category)
                                      ? Colors.white
                                      : CaliuColors.maroon,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      ],
                      const SizedBox(height: 24),
                      _radiusSection(),
                    ],
                  ),
          ),
          if (_errorMessage case final message?)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                message,
                style: const TextStyle(color: CaliuColors.red),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: CaliuColors.maroon,
                  foregroundColor: Colors.white,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Desa preferències'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
