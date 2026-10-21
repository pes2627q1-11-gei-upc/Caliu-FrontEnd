import 'package:flutter/material.dart';

import 'map_view.dart';
import 'search_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const Color _barColor = Color(0xFF2B0A0D);
  static const Color _selectedColor = Color(0xFFF2A33A);
  static const Color _inactiveColor = Color(0xFFE5D5C5);
  static const Color _indicatorColor = Color(0x40F2A33A);

  int _selectedIndex = 0;

  static const List<Widget> _screens = [
    SearchScreen(),
    MapView(),
    Scaffold(backgroundColor: _barColor, body: SizedBox.expand()),
  ];

  static const List<String> _labels = ['Inici', 'Mapa', 'Perfil'];
  static const List<IconData> _outlinedIcons = [
    Icons.home_outlined,
    Icons.location_on_outlined,
    Icons.person_outline,
  ];
  static const List<IconData> _selectedIcons = [
    Icons.home,
    Icons.location_on,
    Icons.person,
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
