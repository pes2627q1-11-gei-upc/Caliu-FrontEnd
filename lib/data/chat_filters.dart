import 'chat_dates.dart';

/// Filtres que l'assistent ha interpretat del missatge (H.U #12, tasca #138).
///
/// Arriben al camp `filters` de `POST /chat/messages` (null si no n'hi ha cap).
/// Tots els camps són opcionals: el que no es reconeix s'ignora.
class ChatFilters {
  const ChatFilters({
    this.from,
    this.to,
    this.timeOfDay,
    this.categories = const [],
    this.audience,
    this.maxPrice,
    this.municipality,
    this.comarca,
    this.datePassed = false,
  });

  final DateTime? from;
  final DateTime? to;

  /// `mati`, `migdia`, `tarda`, `vespre` o `nit`.
  final String? timeOfDay;
  final List<String> categories;

  /// `familiar` o `infantil`.
  final String? audience;

  /// 0 = només gratuïts.
  final double? maxPrice;
  final String? municipality;
  final String? comarca;

  /// La data demanada ja ha passat.
  final bool datePassed;

  /// Null si el JSON no és un objecte o no conté cap filtre.
  static ChatFilters? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;

    DateTime? date(Object? value) =>
        value is String ? DateTime.tryParse(value) : null;
    String? text(Object? value) =>
        value is String && value.trim().isNotEmpty ? value.trim() : null;

    final categories = json['categories'];
    final price = json['maxPrice'];
    final filters = ChatFilters(
      from: date(json['from']),
      to: date(json['to']),
      timeOfDay: text(json['timeOfDay']),
      categories: categories is List
          ? categories.whereType<String>().where((c) => c.isNotEmpty).toList()
          : const [],
      audience: text(json['audience']),
      maxPrice: price is num ? price.toDouble() : null,
      municipality: text(json['municipality']),
      comarca: text(json['comarca']),
      datePassed: json['datePassed'] == true,
    );
    return filters.isEmpty ? null : filters;
  }

  bool get isEmpty =>
      from == null &&
      to == null &&
      timeOfDay == null &&
      categories.isEmpty &&
      audience == null &&
      maxPrice == null &&
      municipality == null &&
      comarca == null &&
      !datePassed;

  /// Etiquetes curtes per mostrar sota la resposta, p. ex.
  /// `[Avui, Tarda, Infantil, Gratuït, Girona]`.
  List<String> labels(DateTime now) => [
    ?_dateLabel(now),
    if (timeOfDay case final slot?) _timeOfDayLabels[slot] ?? _capitalize(slot),
    ...categories,
    if (audience case final audience?)
      _audienceLabels[audience] ?? _capitalize(audience),
    ?_priceLabel(),
    ?municipality,
    if (municipality == null) ?comarca,
  ];

  String? _dateLabel(DateTime now) {
    if (datePassed) return 'Data ja passada';
    final start = from?.toLocal();
    if (start == null) return null;
    final end = to?.toLocal() ?? start;
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    if (!endDay.isAfter(startDay)) return chatDayLabel(start, now);
    if (_isWeekend(startDay, endDay)) return 'Cap de setmana';
    return 'Del ${chatDayMonth(start)} al ${chatDayMonth(end)}';
  }

  String? _priceLabel() {
    final price = maxPrice;
    if (price == null) return null;
    if (price == 0) return 'Gratuït';
    final amount = price == price.roundToDouble()
        ? price.toInt().toString()
        : price.toStringAsFixed(2).replaceAll('.', ',');
    return 'Fins a $amount €';
  }

  static bool _isWeekend(DateTime startDay, DateTime endDay) =>
      startDay.weekday == DateTime.saturday &&
      endDay.difference(startDay).inDays == 1;

  static String _capitalize(String value) =>
      value[0].toUpperCase() + value.substring(1);

  static const _timeOfDayLabels = {
    'mati': 'Matí',
    'migdia': 'Migdia',
    'tarda': 'Tarda',
    'vespre': 'Vespre',
    'nit': 'Nit',
  };

  static const _audienceLabels = {
    'familiar': 'Familiar',
    'infantil': 'Infantil',
  };
}
