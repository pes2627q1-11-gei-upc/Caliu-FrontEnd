import 'package:flutter/material.dart';

import 'data/event.dart';
import 'data/event_query.dart';
import 'data/events_api.dart';
import 'event_detail_screen.dart';
import 'theme/caliu_colors.dart';
import 'widgets/caliu_chip.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    this.lat,
    this.lng,
  });

  final double? lat;
  final double? lng;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final EventsApi _api = EventsApi();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _comarcaController = TextEditingController();
  final TextEditingController _municipalityController = TextEditingController();

  final Set<String> _selectedCategories = {};
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
    _loadCategories();
    _runSearch();
  }

  @override
  void dispose() {
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
    return EventQuery(
      q: _searchController.text,
      category: categories.isEmpty ? null : categories.join(','),
      comarca: _comarcaController.text,
      municipality: _municipalityController.text,
      lat: widget.lat,
      lng: widget.lng,
      limit: 40,
    );
  }

  Future<void> _runSearch() async {
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });

    try {
      final page = await _api.fetchEvents(_buildQuery());
      if (!mounted) return;
      setState(() {
        _results = page.items;
        _total = page.total;
        _loading = false;
      });
    } on EventsApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
        _results = [];
        _total = 0;
      });
    } catch (e) {
      if (!mounted) return;
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
  }

  Future<void> _openFilters() async {
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: CaliuColors.beigeCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 12,
                bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
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
                            setModalState(_resetFilters);
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
                          final selected =
                              _selectedCategories.contains(category);
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
        );
      },
    );

    if (applied == true) {
      await _runSearch();
    }
  }

  void _openDetail(Event event) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(
          eventId: event.id,
          initialEvent: event,
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
    final activeFilters = _selectedCategories.length +
        (_comarcaController.text.trim().isEmpty ? 0 : 1) +
        (_municipalityController.text.trim().isEmpty ? 0 : 1);

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
                  onPressed: _loading ? null : _runSearch,
                  child: const Text('Cercar'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildBody(),
          ),
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
        return Material(
          color: CaliuColors.beigeCard,
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
                  const Icon(Icons.chevron_right, color: CaliuColors.textMuted),
                ],
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
