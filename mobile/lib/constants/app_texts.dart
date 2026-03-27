import 'package:flutter/material.dart';
import '../main.dart';

class AppTexts {
  static Map<String, Map<String, String>> translations = {
    "ar": {
      "home": "الرئيسية",
      "settings": "إعدادات الدخول الى المنصة",
      "language": "اللغة",
      "qr": "QR نافذتي",
      "terms": "الشروط والأحكام",
      "support": "تواصل مع نوافذ",
      "about": "حول منصة نوافذ",
      "logout": "تسجيل الخروج",
      "delete": "حذف الحساب",
    },
    "en": {
      "home": "Home",
      "settings": "Login Settings",
      "language": "Language",
      "qr": "My QR",
      "terms": "Terms & Conditions",
      "support": "Contact Support",
      "about": "About Nawafeth",
      "logout": "Logout",
      "delete": "Delete Account",
    },
  };

  static String getText(BuildContext context, String key) {
    final locale = MyThemeController.of(context)?.locale ?? const Locale('ar');
    final langCode = locale.languageCode;
    return translations[langCode]?[key] ?? key;
  }
}
