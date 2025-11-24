import 'package:flutter/widgets.dart';

/// Centraliserade referenser till bundlade bilder som används återkommande
/// i UI:et. Håller paths konsekventa och undviker duplicerad hårdkodning.
class AppImages {
  static const String backgroundPath = 'assets/images/bakgrund.png';
  static const String logoPath = 'assets/images/loggo_clea.png';

  static const AssetImage background = AssetImage(backgroundPath);
  static const AssetImage logo = AssetImage(logoPath);
}
