import 'dart:async';

import 'package:flutter/foundation.dart';

import 'event_query.dart';
import 'events_api.dart';

/// Recompte del servidor per als filtres que s'estan editant.
class EventCountPreview extends ChangeNotifier {
  EventCountPreview(this._api);

  final EventsApi _api;
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;
  int? total;
  bool loading = true;
  String? error;

  /// Sense ubicació resolta, espera abans de consultar un radi pendent.
  void update(EventQuery? query) {
    if (_disposed) return;
    final generation = ++_generation;
    _timer?.cancel();
    total = null;
    loading = true;
    error = null;
    notifyListeners();
    if (query == null) return;
    _timer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final page = await _api.fetchEvents(query.copyWith(limit: 1));
        if (_disposed || generation != _generation) return;
        total = page.total;
      } catch (_) {
        if (_disposed || generation != _generation) return;
        error = 'No s’ha pogut calcular el recompte.';
      }
      loading = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
