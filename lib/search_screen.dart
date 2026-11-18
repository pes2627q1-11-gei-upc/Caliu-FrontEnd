import 'package:flutter/material.dart';

import 'data/date_range_filter.dart';
import 'data/event.dart';
import 'data/event_count_preview.dart';
import 'data/event_query.dart';
import 'data/events_api.dart';
import 'data/favorites_controller.dart';
import 'data/search_radius.dart';
import 'event_detail_screen.dart';
import 'theme/caliu_colors.dart';
import 'widgets/event_list_tile.dart';
import 'widgets/favorite_button.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.radius, this.api, this.favorites});

  final SearchRadius? radius;
  final EventsApi? api;

  /// Per defecte, [FavoritesController.shared].
  final FavoritesController? favorites;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _initialRadiusKm = 5.0;
  static const _selectorMinKm = 1.0;
  static const _selectorMaxKm = 50.0;
  late final EventsApi _api = widget.api ?? EventsApi();
  late final SearchRadius _radius = widget.radius ?? SearchRadius();
  double _draftRadius = _initialRadiusKm;
  int _request = 0;
  SearchRadius? _editingRadius;
  SearchRadius get _filterRadius => _editingRadius ?? _radius;
  EventCountPreview? _filterPreview;
  final _locationsVersion = ValueNotifier(0);
  List<EventLocation> _locations = [];
  bool _locationsLoaded = false;
  bool _loadingLocations = false;
  String? _locationsError;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _comarcaController = TextEditingController();
  final TextEditingController _municipalityController = TextEditingController();

  final Set<String> _selectedCategories = {};
  DateRangeFilter? _dateFilter;
  List<String> _allCategories = [];

  List<Event> _results = [];
  int _total = 0;
  bool _loading = false;
  bool _loadingCategories = true;
  String? _error;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _draftRadius = (_radius.radiusKm ?? _initialRadiusKm)
        .clamp(_selectorMinKm, _selectorMaxKm)
        .roundToDouble();
    _radius.addListener(_radiusChanged);
    _loadCategories();
    _runSearch();
  }

  void _radiusChanged() {
    if (!mounted) return;
    ++_request;
    setState(() {
      if (_radius.radiusKm != null) {
        _draftRadius = _radius.radiusKm!
            .clamp(_selectorMinKm, _selectorMaxKm)
            .roundToDouble();
      }
    });
    _updateFilterPreview();
    if (!_radius.locating) _runSearch();
  }

  void _updateFilterPreview() {
    _filterPreview?.update(
      _filterRadius.locating ? null : _buildQuery(preview: true),
    );
  }

  @override
  void dispose() {
    _editingRadius?.dispose();
    _locationsVersion.dispose();
    _filterPreview?.dispose();
    _radius.removeListener(_radiusChanged);
    if (widget.radius == null) _radius.dispose();
    _searchController.dispose();
    _comarcaController.dispose();
    _municipalityController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _api.fetchCategories();
      if (!mounted) return;
      setState(() {
        _allCategories = categories;
        _loadingCategories = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCategories = false);
    }
  }

  EventQuery _buildQuery({bool preview = false}) {
    final radius = preview ? _filterRadius : _radius;
    final categories = _selectedCategories.toList()..sort();
    final range = _dateFilter?.rangeFor(DateTime.now());
    return EventQuery(
      q: _searchController.text,
      category: categories.isEmpty ? null : categories.join(','),
      comarca: _comarcaController.text,
      municipality: _municipalityController.text,
      lat: radius.center?.latitude,
      lng: radius.center?.longitude,
      radiusKm: radius.radiusKm,
      from: range?.from,
      to: range?.to,
      limit: 40,
    );
  }

  Future<void> _runSearch() async {
    if (_radius.locating) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });

    try {
      final page = await _api.fetchEvents(_buildQuery());
      if (!mounted || request != _request) return;
      setState(() {
        _results = page.items;
        _total = page.total;
        _loading = false;
      });
    } on EventsApiException catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = e.message;
        _results = [];
        _total = 0;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = 'Error cercant esdeveniments';
        _results = [];
        _total = 0;
      });
    }
  }

  void _resetFilters() {
    setState(() {
      _selectedCategories.clear();
      _dateFilter = null;
      _comarcaController.clear();
      _municipalityController.clear();
    });
    _filterRadius.clear();
  }

  Future<void> _openFilters() async {
    final originalText = _searchController.text;
    final originalComarca = _comarcaController.text;
    final originalMunicipality = _municipalityController.text;
    final originalCategories = Set<String>.of(_selectedCategories);
    final originalDate = _dateFilter;
    final draft = _radius.fork();
    _editingRadius = draft;
    _draftRadius = (draft.radiusKm ?? _initialRadiusKm)
        .clamp(_selectorMinKm, _selectorMaxKm)
        .roundToDouble();
    draft.addListener(_updateFilterPreview);
    if (!_locationsLoaded) _loadLocations();
    final preview = EventCountPreview(_api);
    _filterPreview = preview;
    _updateFilterPreview();
    try {
      final applied = await _showFilters(preview);
      if (!mounted) return;
      if (applied == true) {
        // Una única confirmació notifica la llista i el mapa.
        _radius.adopt(draft);
      } else {
        setState(() {
          _searchController.text = originalText;
          _comarcaController.text = originalComarca;
          _municipalityController.text = originalMunicipality;
          _selectedCategories
            ..clear()
            ..addAll(originalCategories);
          _dateFilter = originalDate;
        });
      }
    } finally {
      draft.removeListener(_updateFilterPreview);
      if (identical(_editingRadius, draft)) _editingRadius = null;
      draft.dispose();
      if (identical(_filterPreview, preview)) _filterPreview = null;
      preview.dispose();
    }
  }

  Future<bool?> _showFilters(EventCountPreview preview) async {
    final route = MaterialPageRoute<bool>(
      builder: (context) => ListenableBuilder(
        listenable: Listenable.merge([
          _filterRadius,
          preview,
          _locationsVersion,
        ]),
        builder: (context, _) => StatefulBuilder(
          builder: (context, setModalState) => Scaffold(
            backgroundColor: const Color(0xFFF5EDD8),
            appBar: AppBar(
              backgroundColor: const Color(0xFFF5EDD8),
              foregroundColor: CaliuColors.maroonDeep,
              surfaceTintColor: Colors.transparent,
              centerTitle: true,
              toolbarHeight: 64,
              title: const Text(
                'Filtrar',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              leading: IconButton(
                tooltip: 'Tancar filtres',
                onPressed: () => Navigator.pop(context, false),
                icon: const Icon(Icons.close),
                style: IconButton.styleFrom(backgroundColor: Colors.white),
              ),
              actions: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 130),
                  child: TextButton(
                    onPressed: () => setModalState(() {
                      _draftRadius = _initialRadiusKm;
                      _searchController.clear();
                      _resetFilters();
                    }),
                    child: const FittedBox(
                      child: Text(
                        'Restablir tot',
                        style: TextStyle(color: CaliuColors.red),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            body: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(top: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF806B43)
                                        .withValues(alpha: 0.12),
                                    blurRadius: 24,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: SearchBar(
                                elevation: const WidgetStatePropertyAll(0),
                                backgroundColor: const WidgetStatePropertyAll(
                                  Colors.white,
                                ),
                                surfaceTintColor: const WidgetStatePropertyAll(
                                  Colors.transparent,
                                ),
                                shape: WidgetStatePropertyAll(
                                  RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    side: const BorderSide(
                                      color: Color(0xFFE0D5C0),
                                    ),
                                  ),
                                ),
                                padding: const WidgetStatePropertyAll(
                                  EdgeInsets.symmetric(horizontal: 16),
                                ),
                                controller: _searchController,
                                hintText: 'Cerca esdeveniments, llocs…',
                                leading: const Icon(
                                  Icons.search,
                                  color: Color(0xFF700B10),
                                ),
                                onChanged: (_) {
                                  setModalState(() {});
                                  _updateFilterPreview();
                                },
                                trailing: [
                                  IconButton(
                                    tooltip: 'Esborrar cerca',
                                    icon: const Icon(
                                      Icons.cancel_outlined,
                                      color: Color(0xFF700B10),
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      setModalState(() {});
                                      _updateFilterPreview();
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 28),
                            const Text(
                              'CATEGORIES',
                              style: TextStyle(
                                color: CaliuColors.red,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (_loadingCategories)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _allCategories.map((category) {
                                  final selected = _selectedCategories.contains(
                                    category,
                                  );
                                  return FilterChip(
                                    label: Text(category),
                                    showCheckmark: false,
                                    avatar: selected
                                        ? const DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: Color(0xFFF5EDD6),
                                              shape: BoxShape.circle,
                                            ),
                                            child: SizedBox(
                                              width: 6,
                                              height: 6,
                                            ),
                                          )
                                        : null,
                                    avatarBoxConstraints:
                                        const BoxConstraints.tightFor(
                                          width: 8,
                                          height: 8,
                                        ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    labelPadding: EdgeInsets.only(
                                      left: selected ? 8 : 0,
                                    ),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    elevation: 0,
                                    pressElevation: 0,
                                    surfaceTintColor: Colors.transparent,
                                    selected: selected,
                                    onSelected: (value) {
                                      setModalState(() {
                                        if (value) {
                                          _selectedCategories.add(category);
                                        } else {
                                          _selectedCategories.remove(category);
                                        }
                                      });
                                      _updateFilterPreview();
                                    },
                                    selectedColor: CaliuColors.red,
                                    checkmarkColor: Colors.white,
                                    labelStyle: TextStyle(
                                      color: selected
                                          ? const Color(0xFFF5EDD6)
                                          : CaliuColors.maroonDeep,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    backgroundColor: Colors.white,
                                    side: BorderSide(
                                      color: selected
                                          ? CaliuColors.red
                                          : const Color(0xFFE0D5C0),
                                    ),
                                  );
                                }).toList(),
                              ),
                            const SizedBox(height: 20),
                            _buildRadiusFilter(setModalState),
                            _buildFilterDates(setModalState),
                            const SizedBox(height: 20),
                            _buildLocations(setModalState),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 24),
                    _buildApplyFiltersButton(context, preview),
                    if (preview.error != null)
                      Text(
                        preview.error!,
                        style: const TextStyle(color: CaliuColors.red),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final result = await Navigator.of(context, rootNavigator: true).push(route);
    // Manté vius els notificadors fins que s'ha desmuntat la ruta de sortida.
    await route.completed;
    return result;
  }

  Future<void> _loadLocations() async {
    if (_loadingLocations) return;
    _loadingLocations = true;
    _locationsError = null;
    _locationsVersion.value++;
    try {
      final locations = await _api.fetchLocations();
      if (!mounted) return;
      _locations = locations;
      _locationsLoaded = true;
    } catch (_) {
      if (!mounted) return;
      _locationsError =
          'No s’han pogut carregar les comarques i els municipis.';
    }
    if (!mounted) return;
    _loadingLocations = false;
    _locationsVersion.value++;
  }

  Widget _buildLocations(StateSetter setModalState) {
    final comarques =
        _locations
            .map((row) => row.comarca)
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final municipis =
        _locations
            .where(
              (row) =>
                  _comarcaController.text.isEmpty ||
                  row.comarca == _comarcaController.text,
            )
            .map((row) => row.municipality)
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    Widget selector(
      String label,
      TextEditingController controller,
      List<String> options,
    ) {
      // Conserva un filtre guardat encara que ja no surti al catàleg.
      final selected = controller.text;
      final availableOptions = [
        if (selected.isNotEmpty && !options.contains(selected)) selected,
        ...options,
      ];
      return DropdownButtonFormField<String>(
        key: ValueKey('$label-${controller.text}'),
        initialValue: controller.text,
        isExpanded: true,
        dropdownColor: Colors.white,
        style: const TextStyle(color: CaliuColors.maroonDeep, fontSize: 16),
        iconEnabledColor: CaliuColors.maroonDeep,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: CaliuColors.maroonDeep),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE0D5C0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: CaliuColors.red, width: 2),
          ),
        ),
        items: [
          DropdownMenuItem(
            value: '',
            child: Text(
              label == 'Comarca' ? 'Totes les comarques' : 'Tots els municipis',
            ),
          ),
          ...availableOptions.map(
            (name) => DropdownMenuItem(value: name, child: Text(name)),
          ),
        ],
        onChanged: !_locationsLoaded || _loadingLocations
            ? null
            : (value) {
                setModalState(() {
                  controller.text = value ?? '';
                  if (label == 'Comarca') _municipalityController.clear();
                });
                _updateFilterPreview();
              },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        selector('Comarca', _comarcaController, comarques),
        const SizedBox(height: 16),
        selector('Municipi', _municipalityController, municipis),
        if (_locationsLoaded && _locations.isEmpty)
          const Text(
            'No hi ha localitats disponibles.',
            style: TextStyle(color: CaliuColors.maroonDeep),
          ),
        if (_loadingLocations)
          const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(),
          ),
        if (_locationsError != null) ...[
          Text(
            _locationsError!,
            style: const TextStyle(color: CaliuColors.red),
          ),
          TextButton(
            onPressed: _loadLocations,
            child: const Text('Tornar a carregar localitats'),
          ),
        ],
      ],
    );
  }

  Widget _buildFilterDates(StateSetter setModalState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DATA I HORA',
          style: TextStyle(color: CaliuColors.red, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: DateRangeFilter.values.map((filter) {
              final selected = _dateFilter == filter;
              return SizedBox(
                width: (constraints.maxWidth - 12) / 2,
                child: Material(
                  color: selected ? CaliuColors.red : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      setModalState(
                        () => _dateFilter = selected ? null : filter,
                      );
                      _updateFilterPreview();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 20,
                            color: selected ? Colors.white : CaliuColors.maroon,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              filter.label,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? Colors.white
                                    : CaliuColors.maroonDeep,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(height: 40),
      ],
    );
  }

  Widget _buildApplyFiltersButton(
    BuildContext context,
    EventCountPreview preview,
  ) {
    final count = preview.loading
        ? 'Comptant…'
        : preview.error != null
        ? 'No disponible'
        : '${preview.total} ${preview.total == 1 ? 'esdeveniment' : 'esdeveniments'}';
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: _filterRadius.locating
            ? null
            : () => Navigator.pop(context, true),
        style: FilledButton.styleFrom(
          backgroundColor: CaliuColors.red,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Aplicar filtres', maxLines: 1, softWrap: false),
              const SizedBox(width: 20),
              Text(
                count,
                key: const ValueKey('filter-result-count'),
                maxLines: 1,
                softWrap: false,
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRadiusFilter(StateSetter setModalState) {
    String distance(double km) => '${km.toStringAsFixed(0)} km';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        Row(
          children: [
            const Expanded(
              child: Text(
                'RADI DE DISTÀNCIA',
                style: TextStyle(
                  color: CaliuColors.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              distance(_draftRadius),
              style: const TextStyle(
                color: CaliuColors.red,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context)
              .copyWith(showValueIndicator: ShowValueIndicator.never),
          child: Slider(
            min: _selectorMinKm,
            max: _selectorMaxKm,
            divisions: 49,
            value: _draftRadius,
            activeColor: CaliuColors.red,
            onChanged: _filterRadius.locating
                ? null
                : (value) {
                    setModalState(() => _draftRadius = value.roundToDouble());
                  },
            onChangeEnd: _filterRadius.locating
                ? null
                : (value) => _filterRadius.apply(value.roundToDouble()),
          ),
        ),
        if (_filterRadius.locating) const Text('Obtenint ubicació…'),
        if (_filterRadius.radiusKm != null || _filterRadius.locating)
          TextButton(
            onPressed: _filterRadius.clear,
            child: const Text('Treure radi'),
          ),
        if (_filterRadius.error != null)
          Text(
            _filterRadius.error!,
            style: const TextStyle(color: CaliuColors.red),
          ),
        const Divider(height: 32),
      ],
    );
  }

  void _selectDateFilter(DateRangeFilter filter) {
    setState(() {
      _dateFilter = _dateFilter == filter ? null : filter;
    });
    _runSearch();
  }

  Widget _buildDateChips() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: DateRangeFilter.values.map((filter) {
          final selected = _dateFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(filter.label),
              selected: selected,
              onSelected: _loading ? null : (_) => _selectDateFilter(filter),
              selectedColor: CaliuColors.red,
              showCheckmark: false,
              labelStyle: TextStyle(
                color: selected ? Colors.white : CaliuColors.maroonDeep,
                fontWeight: FontWeight.w600,
              ),
              backgroundColor: Colors.white,
              side: BorderSide(
                color: selected
                    ? CaliuColors.red
                    : CaliuColors.maroon.withValues(alpha: 0.3),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _openDetail(Event event) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(
          eventId: event.id,
          initialEvent: event,
          favorites: widget.favorites,
        ),
      ),
    );
  }

  String _subtitle(Event event) {
    final parts = <String>[
      if (event.municipality != null && event.municipality!.isNotEmpty)
        event.municipality!,
      if (event.distanceMeters != null)
        '${(event.distanceMeters! / 1000).toStringAsFixed(1)} km',
      if (event.categories.isNotEmpty) event.categories.first,
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final activeFilters =
        _selectedCategories.length +
        (_comarcaController.text.trim().isEmpty ? 0 : 1) +
        (_municipalityController.text.trim().isEmpty ? 0 : 1) +
        (_radius.radiusKm == null ? 0 : 1);

    return Scaffold(
      backgroundColor: CaliuColors.beige,
      appBar: AppBar(
        backgroundColor: CaliuColors.maroon,
        foregroundColor: Colors.white,
        title: const Text('Cerca'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Cerca esdeveniments, llocs…',
              leading: const Icon(Icons.search),
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                      _runSearch();
                    },
                  ),
                IconButton(
                  tooltip: 'Filtres',
                  onPressed: _openFilters,
                  icon: Badge(
                    isLabelVisible: activeFilters > 0,
                    label: Text('$activeFilters'),
                    child: const Icon(Icons.tune),
                  ),
                ),
              ],
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _runSearch(),
            ),
          ),
          _buildDateChips(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _loading
                        ? 'Cercant…'
                        : _searched
                        ? '$_total esdeveniments'
                        : '',
                    style: const TextStyle(
                      color: CaliuColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _loading || _radius.locating ? null : _runSearch,
                  child: const Text('Cercar'),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: CaliuColors.red),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _runSearch,
                style: FilledButton.styleFrom(backgroundColor: CaliuColors.red),
                child: const Text('Tornar a provar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return const Center(
        child: Text(
          'Cap esdeveniment amb aquests criteris',
          style: TextStyle(color: CaliuColors.textMuted),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _results.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final event = _results[index];
        return EventListTile(
          event: event,
          subtitle: _subtitle(event),
          onTap: () => _openDetail(event),
          trailing: FavoriteButton(event: event, controller: widget.favorites),
        );
      },
    );
  }
}
