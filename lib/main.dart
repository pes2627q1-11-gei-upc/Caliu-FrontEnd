import 'package:flutter/material.dart';

import 'data/favorite_alerts_controller.dart';
import 'data/favorites_controller.dart';
import 'main_screen.dart';

void main() {
  FavoritesController.shared.load();
  FavoriteAlertsController.shared.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Caliu',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}
