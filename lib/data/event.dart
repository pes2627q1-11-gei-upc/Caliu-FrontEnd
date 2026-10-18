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
        return value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
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
