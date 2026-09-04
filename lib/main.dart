import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/editor_screen.dart';
import 'ui/theme_primitives.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MenoApp()));
}

class MenoApp extends StatelessWidget {
  const MenoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meno',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: MenoTheme.appBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFAAB6A8),
          brightness: Brightness.light,
        ),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: MenoTheme.ink,
          displayColor: MenoTheme.ink,
          fontFamily: MenoTheme.serif,
        ),
      ),
      home: const EditorScreen(),
    );
  }
}
