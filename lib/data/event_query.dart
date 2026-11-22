/// Valors admesos de `price` a `GET /events` (backend #156 / front #157).
abstract final class EventPriceFilter {
  static const free = 'free';
  static const paid = 'paid';

  static bool isValid(String? value) =>
      value == null || value == free || value == paid;
}

class EventQuery {
  const EventQuery({
    this.q,
    this.category,
    this.tag,
    this.comarca,
    this.municipality,
    this.price,
    this.lat,
    this.lng,
    this.radiusKm,
    this.from,
    this.to,
    this.page = 1,
    this.limit = 20,
  }) : assert(
         price == null ||
             price == EventPriceFilter.free ||
             price == EventPriceFilter.paid,
       );

  final String? q;
  final String? category;
  final String? tag;
  final String? comarca;
  final String? municipality;

  /// `free` | `paid` | null (sense filtre).
  final String? price;
  final double? lat;
  final double? lng;
  final double? radiusKm;

  /// Interval de dates (US5). S'envien a l'API en UTC (ISO 8601).
  final DateTime? from;
  final DateTime? to;
  final int page;
  final int limit;

  bool get hasFilters {
    bool filled(String? v) => v != null && v.trim().isNotEmpty;
    return filled(q) ||
        filled(category) ||
        filled(tag) ||
        filled(comarca) ||
        filled(municipality) ||
        price != null ||
        from != null ||
        to != null;
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
    add('price', price);

    // toUtc(): un DateTime local s'escriuria sense zona i el servidor
    // l'interpretaria com a UTC (desfasament d'1-2 hores).
    if (from != null) params['from'] = from!.toUtc().toIso8601String();
    if (to != null) params['to'] = to!.toUtc().toIso8601String();

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
    String? price,
    double? lat,
    double? lng,
    double? radiusKm,
    DateTime? from,
    DateTime? to,
    int? page,
    int? limit,
    bool clearCategory = false,
    bool clearComarca = false,
    bool clearMunicipality = false,
    bool clearQ = false,
    bool clearDates = false,
    bool clearPrice = false,
  }) {
    return EventQuery(
      q: clearQ ? null : (q ?? this.q),
      category: clearCategory ? null : (category ?? this.category),
      tag: tag ?? this.tag,
      comarca: clearComarca ? null : (comarca ?? this.comarca),
      municipality: clearMunicipality
          ? null
          : (municipality ?? this.municipality),
      price: clearPrice ? null : (price ?? this.price),
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      radiusKm: radiusKm ?? this.radiusKm,
      from: clearDates ? null : (from ?? this.from),
      to: clearDates ? null : (to ?? this.to),
      page: page ?? this.page,
      limit: limit ?? this.limit,
    );
  }
}
