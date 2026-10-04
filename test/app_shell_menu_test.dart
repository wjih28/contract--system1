// قائمة الهامبرغر: كل واجهات البوابة في قائمة واحدة، وتبديل البوابة منها، على الجوال والحاسب
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithaq_app/models/company.dart';
import 'package:mithaq_app/models/questionnaire.dart';
import 'package:mithaq_app/providers/company_state.dart';
import 'package:mithaq_app/providers/contract_state.dart';
import 'package:mithaq_app/providers/daily_ops_state.dart';
import 'package:mithaq_app/providers/dispute_state.dart';
import 'package:mithaq_app/providers/family_state.dart';
import 'package:mithaq_app/providers/operations_state.dart';
import 'package:mithaq_app/providers/professional_state.dart';
import 'package:mithaq_app/screens/shell/app_shell.dart';
import 'package:mithaq_app/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late CompanyState companies;
  late ContractState contracts;
  late OperationsState ops;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    companies = CompanyState();
    await companies.load();
    contracts = ContractState()..auditSink = companies.log;
    await contracts.load();
    ops = OperationsState()..auditSink = companies.log;
    await ops.load();
    companies.createCompany(
      legalName: 'شركة سبأ',
      companyType: 'ذ.م.م',
      currency: AppCurrency.yer,
      capital: 1000000,
      members: const [
        CompanyMember(id: 'm', name: 'المدير', phone: '771000001', equity: 60, roles: {CompanyRole.managingPartner}),
        CompanyMember(id: 'a', name: 'أحمد', phone: '771000002', equity: 40, roles: {CompanyRole.partner}),
      ],
    );
  });

  Future<void> pump(WidgetTester t, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final daily = DailyOpsState()..auditSink = companies.log;
    final pro = ProfessionalState()..auditSink = companies.log;
    final family = FamilyState()..auditSink = companies.log;
    final ds = DisputeState()..auditSink = companies.log;
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: companies),
        ChangeNotifierProvider.value(value: contracts),
        ChangeNotifierProvider.value(value: ops),
        ChangeNotifierProvider.value(value: daily),
        ChangeNotifierProvider.value(value: pro),
        ChangeNotifierProvider.value(value: family),
        ChangeNotifierProvider.value(value: ds),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Directionality(textDirection: TextDirection.rtl, child: AppShell()),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
  }

  testWidgets('الجوال: لا شريط سفلي، وكل الواجهات وتبديل البوابة في قائمة الهامبرغر', (t) async {
    await pump(t, const Size(390, 900));
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(Drawer), findsNothing);
    await t.tap(find.byTooltip('Open navigation menu'));
    await t.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    expect(find.text('بوابة الشركاء'), findsWidgets);
    expect(find.text('التقارير'), findsOneWidget);
    // التبديل إلى إدارة النظام يعرض واجهاتها في القائمة نفسها
    await t.tap(find.widgetWithText(ChoiceChip, 'إدارة النظام'));
    await t.pumpAndSettle();
    expect(find.text('إدارة الشركات'), findsOneWidget);
    await t.tap(find.text('إدارة الشركات'));
    await t.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('الحاسب: القائمة نفسها مثبتة، وزر الهامبرغر يطويها', (t) async {
    await pump(t, const Size(1300, 900));
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('البوابات'), findsOneWidget);
    await t.tap(find.byTooltip('القائمة'));
    await t.pumpAndSettle();
    expect(find.text('البوابات'), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  });
}
