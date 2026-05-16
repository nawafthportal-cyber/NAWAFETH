import 'package:flutter/widgets.dart';

class ResponsiveLayout {
  const ResponsiveLayout._();

  static bool isCompactWidth(BuildContext context) {
    return MediaQuery.sizeOf(context).width < 360;
  }

  static bool isSmallHeight(BuildContext context) {
    return MediaQuery.sizeOf(context).height < 720;
  }

  static double horizontalPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 600) {
      return 28;
    }
    if (width >= 420) {
      return 24;
    }
    return 20;
  }

  static double contentMaxWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 900) {
      return 620;
    }
    if (width >= 600) {
      return 560;
    }
    return width;
  }

  static EdgeInsets screenPadding(
    BuildContext context, {
    double top = 0,
    double bottom = 0,
  }) {
    final horizontal = horizontalPadding(context);
    return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
  }
}