// Carrega tot lib/ perquè `flutter test --coverage` compti també fitxers
// sense tests (p. ex. map_view). Sense això lcov només té el que els tests toquen.
import 'package:caliu/config.dart';
import 'package:caliu/data/auth_api.dart';
import 'package:caliu/data/auth_session.dart';
import 'package:caliu/data/auth_validators.dart';
import 'package:caliu/data/date_range_filter.dart';
import 'package:caliu/data/event.dart';
import 'package:caliu/data/event_query.dart';
import 'package:caliu/data/events_api.dart';
import 'package:caliu/event_detail_screen.dart';
import 'package:caliu/login_screen.dart';
import 'package:caliu/main.dart';
import 'package:caliu/main_screen.dart';
import 'package:caliu/map_view.dart';
import 'package:caliu/preferences_screen.dart';
import 'package:caliu/profile_screen.dart';
import 'package:caliu/register_screen.dart';
import 'package:caliu/search_screen.dart';
import 'package:caliu/theme/caliu_colors.dart';
import 'package:caliu/widgets/caliu_chip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inclou tot lib/ a la cobertura', () {
    // Referències mínimes perquè l'analitzador no elimini els imports.
    expect(apiBaseUrl, isA<String>());
    expect(AuthApi, isNotNull);
    expect(AuthSession, isNotNull);
    expect(AuthValidators.username, isA<Function>());
    expect(DateRangeFilter.values, isNotEmpty);
    expect(Event, isNotNull);
    expect(EventQuery, isNotNull);
    expect(EventsApi, isNotNull);
    expect(EventDetailScreen, isNotNull);
    expect(LoginScreen, isNotNull);
    expect(MyApp, isNotNull);
    expect(MainScreen, isNotNull);
    expect(MapView, isNotNull);
    expect(PreferencesScreen, isNotNull);
    expect(ProfileScreen, isNotNull);
    expect(RegisterScreen, isNotNull);
    expect(SearchScreen, isNotNull);
    expect(CaliuColors, isNotNull);
    expect(CaliuChip, isNotNull);
  });
}
