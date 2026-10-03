import 'package:flutter/widgets.dart';

/// نقاط التحول بين الجوال واللوحي والحاسب
enum ScreenSize { phone, tablet, desktop }

extension ResponsiveContext on BuildContext {
  ScreenSize get screenSize {
    final w = MediaQuery.sizeOf(this).width;
    if (w >= 1100) return ScreenSize.desktop;
    if (w >= 700) return ScreenSize.tablet;
    return ScreenSize.phone;
  }

  bool get isPhone => screenSize == ScreenSize.phone;
}

/// يحصر عرض المحتوى على الشاشات الكبيرة حتى لا تمتد الأسطر بشكل مرهق للقراءة
class ContentWidth extends StatelessWidget {
  final Widget child;
  final double max;
  const ContentWidth({super.key, required this.child, this.max = 920});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: max), child: child),
      );
}
