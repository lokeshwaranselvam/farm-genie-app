import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum FarmgenieThemeChoice { farmgenie, ocean, earth }

extension FarmgenieThemeChoiceLabel on FarmgenieThemeChoice {
  String get label => switch (this) {
    FarmgenieThemeChoice.farmgenie => 'Farmgenie Green',
    FarmgenieThemeChoice.ocean => 'Ocean Blue',
    FarmgenieThemeChoice.earth => 'Earth Brown',
  };
}

class FarmgenieThemeController {
  FarmgenieThemeController._();

  static const _preferenceKey = 'farmgenie_theme_choice_v1';
  static final choice = ValueNotifier(FarmgenieThemeChoice.farmgenie);

  static Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_preferenceKey);
    if (saved == 'leaf') {
      choice.value = FarmgenieThemeChoice.ocean;
      return;
    }
    choice.value = FarmgenieThemeChoice.values.firstWhere(
      (value) => value.name == saved,
      orElse: () => FarmgenieThemeChoice.farmgenie,
    );
  }

  static Future<void> setChoice(FarmgenieThemeChoice value) async {
    if (choice.value == value) return;
    choice.value = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferenceKey, value.name);
  }
}
