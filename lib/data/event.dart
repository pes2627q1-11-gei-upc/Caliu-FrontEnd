import 'package:google_maps_flutter/google_maps_flutter.dart';

class Event {
  const Event({
    required this.id,
    required this.title,
    this.description,
    this.startDate,
    this.endDate,
    this.schedule,
    this.venue,
    this.address,
    this.municipality,
    this.comarca,
    this.location,
    this.categories = const [],
    this.tags = const [],
    this.price,
    this.url,
    this.images = const [],
    this.distanceMeters,
  });

  final String id;
  final String title;
  final String? description;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? schedule;
  final String? venue;
  final String? address;
  final String? municipality;
  final String? comarca;
  final LatLng? location;
  final List<String> categories;
  final List<String> tags;
  final double? price;
  final String? url;
  final List<String> images;
  final int? distanceMeters;

  bool get hasLocation => location != null;

  String? get imageUrl => images.isNotEmpty ? images.first : null;

  String get placeLine {
    final parts = <String>[
      if (venue != null && venue!.trim().isNotEmpty) venue!.trim(),
      if (address != null && address!.trim().isNotEmpty) address!.trim(),
      if (municipality != null && municipality!.trim().isNotEmpty)
        municipality!.trim(),
    ];
    if (parts.isEmpty && comarca != null && comarca!.trim().isNotEmpty) {
      return comarca!.trim();
    }
    return parts.join(', ');
  }

  /// Lloc en una línia curta (espai i municipi), per al popup del marcador.
  /// No repeteix el municipi si ja surt al nom de l'espai o a l'adreça.
  String get shortPlace {
    String? clean(String? value) =>
        value == null || value.trim().isEmpty ? null : value.trim();
    final where = clean(venue) ?? clean(address);
    final town = clean(municipality) ?? clean(comarca);
    if (where == null) return town ?? '';
    if (town == null || where.toLowerCase().contains(town.toLowerCase())) {
      return where;
    }
    return '$where, $town';
  }

  /// Enllaç per obrir la ubicació a Google Maps (null si no té coordenades).
  Uri? get googleMapsUri {
    final point = location;
    if (point == null) return null;
    return Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '${point.latitude},${point.longitude}',
    });
  }

  Uri? get googleMapsDirectionsUri {
    final point = location;
    final hasVenue = venue?.trim().isNotEmpty == true;
    final hasAddress = address?.trim().isNotEmpty == true;
    if (point == null && !hasVenue && !hasAddress) return null;

    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': point == null
          ? placeLine
          : '${point.latitude},${point.longitude}',
    });
  }

  Uri? get googleCalendarUri {
    final start = startDate;
    final end = endDate;
    if (start == null || (end != null && end.isBefore(start))) return null;

    String formatUtc(DateTime date) {
      final isoDate = date.toUtc().toIso8601String().split('.').first;
      return '${isoDate.replaceAll('-', '').replaceAll(':', '')}Z';
    }

    String formatDay(DateTime date) =>
        date.toIso8601String().split('T').first.replaceAll('-', '');

    const maxSpan = Duration(days: 14);
    final startInMadrid = _madridDateTime(start);
    final firstDay = DateTime.utc(
      startInMadrid.year,
      startInMadrid.month,
      startInMadrid.day,
    );
    final nextDay = DateTime.utc(
      firstDay.year,
      firstDay.month,
      firstDay.day + 1,
    );
    final String dates;
    // L’agenda representa els dies sense hora d’inici amb la mitjanit local.
    if (startInMadrid == firstDay) {
      final lastDay = _madridDateTime(end ?? start);
      final exclusiveEnd = DateTime.utc(
        lastDay.year,
        lastDay.month,
        lastDay.day + 1,
      );
      // Exposicions llargues: només el primer dia (dia sencer).
      final dayEnd = exclusiveEnd.difference(firstDay) >= maxSpan
          ? nextDay
          : exclusiveEnd;
      dates = '${formatDay(firstDay)}/${formatDay(dayEnd)}';
    } else {
      // El backend també pot repetir l’inici quan no disposa de data de fi.
      final calendarEnd = end == null || end.isAtSameMomentAs(start)
          ? start.add(const Duration(hours: 2))
          : end;
      // Intervals llargs: primer dia amb la hora d’inici i 2 h de durada.
      final eventEnd = calendarEnd.difference(start) >= maxSpan
          ? start.add(const Duration(hours: 2))
          : calendarEnd;
      dates = '${formatUtc(start)}/${formatUtc(eventEnd)}';
    }

    final place = placeLine;
    final officialUrl = Uri.tryParse(url?.trim() ?? '');
    return Uri.https('calendar.google.com', '/calendar/r/eventedit', {
      'action': 'TEMPLATE',
      'text': title,
      'dates': dates,
      'stz': 'Europe/Madrid',
      'etz': 'Europe/Madrid',
      if (place.isNotEmpty) 'location': place,
      if (officialUrl != null &&
          officialUrl.host.isNotEmpty &&
          (officialUrl.isScheme('https') || officialUrl.isScheme('http')))
        'details': officialUrl.toString(),
    });
  }

  // Mateixa regla que el sincronitzador de l’agenda. Emprem un DateTime UTC
  // per llegir els components de Madrid sense dependre de la zona del mòbil.
  static DateTime _madridDateTime(DateTime date) {
    final utc = date.toUtc();
    DateTime clockChange(int month) {
      final lastDay = DateTime.utc(utc.year, month + 1, 0, 1);
      return lastDay.subtract(Duration(days: lastDay.weekday % 7));
    }

    final summerTime =
        !utc.isBefore(clockChange(3)) && utc.isBefore(clockChange(10));
    return utc.add(Duration(hours: summerTime ? 2 : 1));
  }

  factory Event.fromJson(Map<String, dynamic> json) {
    LatLng? location;
    final rawLocation = json['location'];
    if (rawLocation is Map<String, dynamic>) {
      final coords = rawLocation['coordinates'];
      if (coords is List && coords.length >= 2) {
        final lng = (coords[0] as num).toDouble();
        final lat = (coords[1] as num).toDouble();
        location = LatLng(lat, lng);
      }
    }

    DateTime? parseDate(dynamic value) {
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    List<String> parseStringList(dynamic value) {
      if (value is List) {
        return value
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return const [];
    }

    double? price;
    final rawPrice = json['price'];
    if (rawPrice is num) price = rawPrice.toDouble();

    return Event(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Sense títol',
      description: json['description']?.toString(),
      startDate: parseDate(json['startDate']),
      endDate: parseDate(json['endDate']),
      schedule: json['schedule']?.toString(),
      venue: json['venue']?.toString(),
      address: json['address']?.toString(),
      municipality: json['municipality']?.toString(),
      comarca: json['comarca']?.toString(),
      location: location,
      categories: parseStringList(json['categories']),
      tags: parseStringList(json['tags']),
      price: price,
      url: json['url']?.toString(),
      images: parseStringList(json['images']),
      distanceMeters: json['distanceMeters'] is num
          ? (json['distanceMeters'] as num).toInt()
          : null,
    );
  }
}
