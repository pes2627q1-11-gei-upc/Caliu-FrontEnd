import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'event.dart';

/// Itinerari d'un dia que proposa l'assistent (H.U #13, tasca #141).
///
/// Arriba quan `POST /chat/messages` respon amb `type: "plan"`: el camp `plan`
/// porta els passos ordenats per hora i distància (backend #139/#140).
class ChatPlan {
  const ChatPlan({required this.steps, this.date});

  /// Dia de l'itinerari (sense hora).
  final DateTime? date;
  final List<ChatPlanStep> steps;

  /// Null si no és un pla vàlid (sense passos o amb un format inesperat).
  static ChatPlan? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final rawSteps = json['steps'];
    if (rawSteps is! List) return null;
    final steps = <ChatPlanStep>[];
    for (final raw in rawSteps) {
      final step = ChatPlanStep.fromJson(raw);
      if (step != null) steps.add(step);
    }
    if (steps.isEmpty) return null;
    steps.sort((a, b) => a.order.compareTo(b.order));
    final date = json['date'];
    return ChatPlan(
      steps: List.unmodifiable(steps),
      date: date is String ? DateTime.tryParse(date) : null,
    );
  }

  /// Passos amb coordenades, en ordre (per dibuixar la ruta).
  List<ChatPlanStep> get locatedSteps =>
      steps.where((step) => step.location != null).toList();

  /// Ruta a peu a Google Maps entre els passos amb coordenades. Null si n'hi
  /// ha menys de dos.
  Uri? get directionsUri {
    final points = locatedSteps.map((s) => s.location!).toList();
    if (points.length < 2) return null;
    String format(LatLng p) => '${p.latitude},${p.longitude}';
    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'origin': format(points.first),
      'destination': format(points.last),
      if (points.length > 2)
        'waypoints': points
            .sublist(1, points.length - 1)
            .map(format)
            .join('|'),
      'travelmode': 'walking',
    });
  }
}

/// Un pas de l'itinerari.
class ChatPlanStep {
  const ChatPlanStep({
    required this.order,
    required this.title,
    this.id,
    this.start,
    this.end,
    this.venue,
    this.address,
    this.municipality,
    this.location,
    this.distanceKm,
    this.travelMinutes,
    this.url,
  });

  final int order;
  final String title;

  /// Id de l'esdeveniment (`GET /events/{id}`); null si no en té.
  final String? id;
  final DateTime? start;
  final DateTime? end;
  final String? venue;
  final String? address;
  final String? municipality;
  final LatLng? location;

  /// Distància i temps des del pas anterior (null al primer pas).
  final double? distanceKm;
  final int? travelMinutes;
  final String? url;

  bool get canOpen => id != null;

  /// Espai i municipi en una línia.
  String get place => [
    ?venue,
    if (municipality != null && !(venue ?? '').contains(municipality!))
      municipality!,
  ].join(', ');

  /// Esdeveniment mínim per obrir-ne la fitxa (que després es completa amb
  /// `GET /events/{id}`).
  Event toEvent() => Event(
    id: id ?? '',
    title: title,
    startDate: start,
    endDate: end,
    venue: venue,
    address: address,
    municipality: municipality,
    location: location,
    url: url,
  );

  static ChatPlanStep? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final title = json['title'];
    if (title is! String || title.trim().isEmpty) return null;

    String? text(Object? value) =>
        value is String && value.trim().isNotEmpty ? value.trim() : null;
    DateTime? date(Object? value) =>
        value is String ? DateTime.tryParse(value) : null;

    LatLng? location;
    final coords = json['coordinates'];
    if (coords is List && coords.length >= 2) {
      final lng = coords[0];
      final lat = coords[1];
      if (lng is num && lat is num) {
        location = LatLng(lat.toDouble(), lng.toDouble());
      }
    }

    final order = json['order'];
    final distance = json['distanceKm'];
    final minutes = json['travelMinutes'];
    return ChatPlanStep(
      order: order is num ? order.toInt() : 0,
      title: title.trim(),
      id: text(json['id']),
      start: date(json['start']),
      end: date(json['end']),
      venue: text(json['venue']),
      address: text(json['address']),
      municipality: text(json['municipality']),
      location: location,
      distanceKm: distance is num ? distance.toDouble() : null,
      travelMinutes: minutes is num ? minutes.toInt() : null,
      url: text(json['url']),
    );
  }
}
