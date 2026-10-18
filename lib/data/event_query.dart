class EventQuery {
  const EventQuery({
    this.q,
    this.category,
    this.tag,
    this.comarca,
    this.municipality,
    this.lat,
    this.lng,
    this.radiusKm,
    this.page = 1,
    this.limit = 20,
  });

  final String? q;
  final String? category;
  final String? tag;
  final String? comarca;
  final String? municipality;
  final double? lat;
  final double? lng;
  final double? radiusKm;
  final int page;
  final int limit;

  bool get hasFilters {
    bool filled(String? v) => v != null && v.trim().isNotEmpty;
    return filled(q) ||
        filled(category) ||
        filled(tag) ||
        filled(comarca) ||
        filled(municipality);
  }

  Map<String, String> toQueryParameters() {
    final params = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };

    void add(String key, String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        params[key] = trimmed;
      }
    }

    add('q', q);
    add('category', category);
    add('tag', tag);
    add('comarca', comarca);
    add('municipality', municipality);

    if (lat != null && lng != null) {
      params['lat'] = lat.toString();
      params['lng'] = lng.toString();
      if (radiusKm != null) {
        params['radiusKm'] = radiusKm.toString();
      }
    }

    return params;
  }

  EventQuery copyWith({
    String? q,
    String? category,
    String? tag,
    String? comarca,
    String? municipality,
    double? lat,
    double? lng,
    double? radiusKm,
    int? page,
    int? limit,
    bool clearCategory = false,
    bool clearComarca = false,
    bool clearMunicipality = false,
    bool clearQ = false,
  }) {
    return EventQuery(
      q: clearQ ? null : (q ?? this.q),
      category: clearCategory ? null : (category ?? this.category),
      tag: tag ?? this.tag,
      comarca: clearComarca ? null : (comarca ?? this.comarca),
      municipality:
          clearMunicipality ? null : (municipality ?? this.municipality),
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      radiusKm: radiusKm ?? this.radiusKm,
      page: page ?? this.page,
      limit: limit ?? this.limit,
    );
  }
}
