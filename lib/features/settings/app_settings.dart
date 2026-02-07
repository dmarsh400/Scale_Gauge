import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  static const _darkModeKey = 'tpms_dark_mode';

  bool _darkMode = false;
  bool _loaded = false;

  bool get darkMode => _darkMode;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _darkMode = prefs.getBool(_darkModeKey) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    if (value == _darkMode) return;
    _darkMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, value);
    notifyListeners();
  }
}
