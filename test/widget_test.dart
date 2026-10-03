// اختبار أساسي للتأكد من إقلاع تطبيق ميثاق دون أخطاء.
import 'package:flutter_test/flutter_test.dart';

import 'package:mithaq_app/main.dart';

void main() {
  testWidgets('Mithaq app boots and shows splash screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MithaqApp());
    await tester.pump();

    expect(find.text('ميثاق'), findsOneWidget);

    // تجاوز مؤقت شاشة البداية حتى لا يبقى مؤقت معلق بعد انتهاء الاختبار
    await tester.pump(const Duration(seconds: 3));
  });
}
