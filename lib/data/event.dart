import 'package:google_maps_flutter/google_maps_flutter.dart';

class Event {
  const Event({
    required this.id,
    required this.title,
    this.location,
    this.categories = const [],
    this.startDate,
    this.distanceMeters,
  });

  final String id;
  final String title;
  final LatLng? location;
  final List<String> categories;
  final DateTime? startDate;
  final int? distanceMeters;

  bool get hasLocation => location != null;

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

    DateTime? startDate;
    final rawStart = json['startDate'];
    if (rawStart is String) {
      startDate = DateTime.tryParse(rawStart);
    }

    final rawCategories = json['categories'];
    final categories = rawCategories is List
        ? rawCategories.map((e) => e.toString()).toList()
        : <String>[];

    return Event(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Sense títol',
      location: location,
      categories: categories,
      startDate: startDate,
      distanceMeters: json['distanceMeters'] is num
          ? (json['distanceMeters'] as num).toInt()
          : null,
    );
  }
}
