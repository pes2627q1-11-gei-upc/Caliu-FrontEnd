import 'package:flutter/material.dart';

import 'chat_screen.dart';
import 'map_view.dart';
import 'data/preferred_radius.dart';
import 'data/search_radius.dart';
import 'profile_screen.dart';
import 'recommendations_screen.dart';
import 'search_screen.dart';
import 'widgets/home_recommendations.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, this.preferredRadius});

  /// Radi de les preferències que fan servir per defecte el mapa i la cerca
  /// (H.U #9, tasca #125). Per defecte, [PreferredRadius.shared].
  final PreferredRadius? preferredRadius;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const Color _barColor = Color(0xFF2B0A0D);
  static const Color _selectedColor = Color(0xFFF2A33A);
  static const Color _inactiveColor = Color(0xFFE5D5C5);
  static const Color _indicatorColor = Color(0x40F2A33A);

  int _selectedIndex = 0;
  final _radius = SearchRadius();
  late final VoidCallback _unbindPreferredRadius;

  @override
  void initState() {
    super.initState();
    _unbindPreferredRadius = bindPreferredRadius(
      widget.preferredRadius ?? PreferredRadius.shared,
      _radius,
    );
  }

  @override
  void dispose() {
    _unbindPreferredRadius();
    _radius.dispose();
    super.dispose();
  }

  // MapView rep si és la pestanya visible: fora d'ella no ha d'interceptar el
  // botó enrere (#44). L'IndexedStack conserva l'estat de cada pantalla.
  List<Widget> get _screens => [
    // Inici: la cerca amb les recomanacions a dalt (només aquí, no a la
    // cerca que s'obre des del mapa). «Veure tot» porta a «Per a tu».
    SearchScreen(
      radius: _radius,
      homeHeader: HomeRecommendations(
        isActive: _selectedIndex == 0,
        onSeeAll: () => setState(() => _selectedIndex = 1),
      ),
    ),
    // H.U #8: recomanacions. En tornar-hi es recarreguen.
    RecommendationsScreen(isActive: _selectedIndex == 1),
    MapView(isActive: _selectedIndex == 2, radius: _radius),
    const ProfileScreen(),
    // H.U #11: assistent. `isActive` fa que revisi la sessió en tornar-hi.
    ChatScreen(isActive: _selectedIndex == 4),
  ];

  static const List<String> _labels = [
    'Inici',
    'Per a tu',
    'Mapa',
    'Perfil',
    'Xat',
  ];
  static const List<IconData> _outlinedIcons = [
    Icons.home_outlined,
    Icons.star_outline,
    Icons.location_on_outlined,
    Icons.person_outline,
    Icons.chat_bubble_outline,
  ];
  static const List<IconData> _selectedIcons = [
    Icons.home,
    Icons.star,
    Icons.location_on,
    Icons.person,
    Icons.chat_bubble,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: Container(
        color: _barColor,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 5, 8, 3),
            child: Row(
              children: List<Widget>.generate(_labels.length, (index) {
                final selected = index == _selectedIndex;
                final color = selected ? _selectedColor : _inactiveColor;

                return Expanded(
                  child: Semantics(
                    button: true,
                    selected: selected,
                    label: _labels[index],
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _selectedIndex = index),
                      child: SizedBox(
                        height: 52,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 32,
                              height: 25,
                              decoration: BoxDecoration(
                                color: selected
                                    ? _indicatorColor
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Icon(
                                selected
                                    ? _selectedIcons[index]
                                    : _outlinedIcons[index],
                                size: 19,
                                color: color.withValues(
                                  alpha: selected ? 1 : 0.88,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _labels[index],
                              style: TextStyle(
                                color: color.withValues(
                                  alpha: selected ? 1 : 0.88,
                                ),
                                fontSize: 10,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
