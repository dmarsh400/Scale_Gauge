import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'home_view.dart';
import 'features/settings/app_settings.dart';

class TpmsApp extends StatelessWidget {
  const TpmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    const brandGreen = Color(0xFF0D6B63);
    const brandDark = Color(0xFF0B2E2A);
    final lightScheme = ColorScheme.fromSeed(seedColor: brandGreen);
    final darkScheme = ColorScheme.fromSeed(
      seedColor: brandGreen,
      brightness: Brightness.dark,
      surface: brandDark,
      background: brandDark,
    );

    return Consumer<AppSettings>(
      builder: (context, settings, _) {
        return MaterialApp(
          title: 'TPMS Monitor',
          themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            colorScheme: lightScheme,
            useMaterial3: true,
            scaffoldBackgroundColor: lightScheme.surface,
            appBarTheme: AppBarTheme(
              backgroundColor: lightScheme.surface,
              foregroundColor: lightScheme.onSurface,
              elevation: 0,
              centerTitle: false,
            ),
            cardTheme: CardThemeData(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            navigationBarTheme: NavigationBarThemeData(
              indicatorColor: lightScheme.primary.withOpacity(0.15),
              labelTextStyle: WidgetStatePropertyAll(
                TextStyle(color: lightScheme.onSurface),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: lightScheme.primary,
                foregroundColor: lightScheme.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: darkScheme,
            useMaterial3: true,
            scaffoldBackgroundColor: darkScheme.surface,
            appBarTheme: AppBarTheme(
              backgroundColor: darkScheme.surface,
              foregroundColor: darkScheme.onSurface,
              elevation: 0,
              centerTitle: false,
            ),
            cardTheme: CardThemeData(
              elevation: 1,
              color: darkScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            navigationBarTheme: NavigationBarThemeData(
              indicatorColor: darkScheme.primary.withOpacity(0.2),
              labelTextStyle: WidgetStatePropertyAll(
                TextStyle(color: darkScheme.onSurface),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: darkScheme.primary,
                foregroundColor: darkScheme.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          home: const HomeView(),
        );
      },
    );
  }
}
