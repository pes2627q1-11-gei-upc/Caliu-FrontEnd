import 'package:flutter/material.dart';

import 'data/date_range_filter.dart';
import 'data/event.dart';
import 'data/event_query.dart';
import 'data/events_api.dart';
import 'data/search_radius.dart';
import 'event_detail_screen.dart';
import 'theme/caliu_colors.dart';
import 'widgets/caliu_chip.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.radius, this.api});

  final SearchRadius? radius;
  final EventsApi? api;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final EventsApi _api = widget.api ?? EventsApi();
  late final SearchRadius _radius = widget.radius ?? SearchRadius();
  double _draftRadius = 15;
  int _request = 0;
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
    _draftRadius = _radius.radiusKm ?? 15;
    _radius.addListener(_radiusChanged);
    _loadCategories();
    _runSearch();
  }

  void _radiusChanged() {
    if (!mounted) return;
    ++_request;
    setState(() {
      if (_radius.radiusKm != null) _draftRadius = _radius.radiusKm!;
    });
    if (!_radius.locating) _runSearch();
  }

  @override
  void dispose() {
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

  EventQuery _buildQuery() {
    final categories = _selectedCategories.toList()..sort();
    final range = _dateFilter?.rangeFor(DateTime.now());
    return EventQuery(
      q: _searchController.text,
      category: categories.isEmpty ? null : categories.join(','),
      comarca: _comarcaController.text,
      municipality: _municipalityController.text,
      lat: _radius.center?.latitude,
      lng: _radius.center?.longitude,
      radiusKm: _radius.radiusKm,
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
      _comarcaController.clear();
      _municipalityController.clear();
    });
    _radius.clear();
  }

  Future<void> _openFilters() async {
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: CaliuColors.beigeCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return ListenableBuilder(
          listenable: _radius,
          builder: (context, _) => StatefulBuilder(
            builder: (context, setModalState) {
              final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
              final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;
              return Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 12,
                  bottom: bottomInset + bottomSafe + 20,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context, false),
                            icon: const Icon(Icons.close),
                          ),
                          const Expanded(
                            child: Text(
                              'Filtrar',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                _draftRadius = 15;
                                _resetFilters();
                              });
                            },
                            child: const Text(
                              'Restablir tot',
                              style: TextStyle(color: CaliuColors.red),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Categories',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      if (_loadingCategories)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: CircularProgressIndicator()),
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
                              selected: selected,
                              onSelected: (value) {
                                setModalState(() {
                                  if (value) {
                                    _selectedCategories.add(category);
                                  } else {
                                    _selectedCategories.remove(category);
                                  }
                                });
                              },
                              selectedColor: CaliuColors.red,
                              checkmarkColor: Colors.white,
                              labelStyle: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : CaliuColors.maroonDeep,
                                fontWeight: FontWeight.w600,
                              ),
                              backgroundColor: Colors.white,
                              side: BorderSide(
                                color: selected
                                    ? CaliuColors.red
                                    : CaliuColors.maroon.withValues(alpha: 0.3),
                              ),
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 20),
                      _buildRadiusFilter(setModalState),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _comarcaController,
                        decoration: const InputDecoration(
                          labelText: 'Comarca',
                          hintText: 'Ex: Barcelonès',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setModalState(() {}),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _municipalityController,
                        decoration: const InputDecoration(
                          labelText: 'Municipi',
                          hintText: 'Ex: Barcelona',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setModalState(() {}),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: CaliuColors.red,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Aplicar filtres'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    if (applied == true) {
      await _runSearch();
    }
  }

  Widget _buildRadiusFilter(StateSetter setModalState) {
    String distance(double km) =>
        '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
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
        Slider(
          min: SearchRadius.minKm,
          max: SearchRadius.maxKm,
          divisions: 4999,
          value: _draftRadius,
          activeColor: CaliuColors.red,
          label: distance(_draftRadius),
          onChanged: _radius.locating
              ? null
              : (value) {
                  setModalState(() => _draftRadius = value);
                },
        ),
        if (_radius.radiusKm != null)
          Text('Radi aplicat: ${distance(_radius.radiusKm!)}'),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: _radius.locating
                  ? null
                  : () => _radius.apply(_draftRadius),
              icon: const Icon(Icons.my_location),
              label: Text(
                _radius.locating ? 'Obtenint ubicació…' : 'Aplicar radi',
              ),
            ),
            if (_radius.radiusKm != null || _radius.locating)
              TextButton(
                onPressed: _radius.clear,
                child: const Text('Treure radi'),
              ),
          ],
        ),
        if (_radius.error != null)
          Text(_radius.error!, style: const TextStyle(color: CaliuColors.red)),
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
        builder: (_) =>
            EventDetailScreen(eventId: event.id, initialEvent: event),
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
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: CaliuColors.maroon.withValues(alpha: 0.14),
            ),
            boxShadow: [
              BoxShadow(
                color: CaliuColors.maroonDeep.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _openDetail(event),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: event.imageUrl != null
                            ? Image.network(
                                event.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    _thumbPlaceholder(),
                              )
                            : _thumbPlaceholder(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: CaliuColors.maroonDeep,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _subtitle(event),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: CaliuColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                          Builder(
                            builder: (context) {
                              final labels = <String>{
                                ...event.categories,
                                ...event.tags,
                              }.take(3).toList();
                              if (labels.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: labels
                                      .map((label) => CaliuChip(label: label))
                                      .toList(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: CaliuColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _thumbPlaceholder() {
    return Container(
      color: CaliuColors.maroon,
      child: const Icon(Icons.event, color: Colors.white54),
    );
  }
}
