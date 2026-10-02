// عرض شاشات الإدارة (المرحلة 4) على الحاسب والجوال: أي خطأ أو تجاوز في العرض يُفشل الاختبار
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithaq_app/models/admin.dart';
import 'package:mithaq_app/models/company.dart';
import 'package:mithaq_app/models/questionnaire.dart';
import 'package:mithaq_app/providers/company_state.dart';
import 'package:mithaq_app/providers/contract_state.dart';
import 'package:mithaq_app/providers/dispute_state.dart';
import 'package:mithaq_app/providers/operations_state.dart';
import 'package:mithaq_app/screens/admin/admin_dashboard_screen.dart';
import 'package:mithaq_app/screens/admin/companies_screen.dart';
import 'package:mithaq_app/screens/admin/control_points_screen.dart';
import 'package:mithaq_app/screens/admin/platform_settings_screen.dart';
import 'package:mithaq_app/screens/admin/roles_screen.dart';
import 'package:mithaq_app/screens/admin/security_monitor_screen.dart';
import 'package:mithaq_app/screens/admin/users_screen.dart';
import 'package:mithaq_app/screens/company/consent_requests_screen.dart';
import 'package:mithaq_app/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late CompanyState companies;
  late ContractState cs;
  late OperationsState ops;
  late DisputeState ds;
  late Company c;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    companies = CompanyState();
    await companies.load();
    cs = ContractState()..auditSink = companies.log;
    await cs.load();
    ops = OperationsState()..auditSink = companies.log;
    await ops.load();
    ds = DisputeState();
    await ds.load();
    c = companies.createCompany(
      legalName: 'شركة سبأ للتجارة والاستثمار',
      companyType: 'ذ.م.م',
      currency: AppCurrency.usd,
      capital: 100000,
      members: const [
        CompanyMember(id: 'm', name: 'المدير العام', phone: '771000001', equity: 60, roles: {CompanyRole.managingPartner}),
        CompanyMember(id: 'a', name: 'أحمد', phone: '771000002', equity: 40, roles: {CompanyRole.partner}),
      ],
    );
    companies.inviteStaff(c.id, name: 'سالم المالي', phone: '771000009', role: CompanyRole.financialManager);
    companies.saveControlPoint(c.id, 'partner.phone', CompanyRole.financialManager, {PermAction.view});
    companies.savePermissions(c.id, CompanyRole.accountant, {AppModule.auditLog: {PermAction.view}});
    companies.setSetting(c.id, 'exception.deadlineDays', 5);
  });

  Future<void> pump(WidgetTester t, Widget screen, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: companies),
        ChangeNotifierProvider.value(value: cs),
        ChangeNotifierProvider.value(value: ops),
        ChangeNotifierProvider.value(value: ds),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Directionality(textDirection: TextDirection.rtl, child: screen),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
  }

  final screens = <String, Widget Function()>{
    'A01 لوحة الإدارة': () => const AdminDashboardScreen(),
    'A02 الشركات': () => const CompaniesScreen(),
    'A03 المستخدمون': () => const UsersScreen(),
    'A04 الأدوار والصلاحيات': () => const RolesScreen(),
    'A05 نقاط الإفصاح': () => const ControlPointsScreen(),
    'A05 محرر نقطة': () => const ControlPointEditor(pointId: 'partner.phone'),
    'A20 الأمان والتكامل': () => const SecurityMonitorScreen(),
    'A21 إعدادات المنصة': () => const PlatformSettingsScreen(),
    'موافقة الشريك': () => const ConsentRequestsScreen(),
  };
  for (final (w, label) in [(const Size(1200, 2600), 'الحاسب'), (const Size(390, 2600), 'الجوال')]) {
    for (final e in screens.entries) {
      testWidgets('${e.key} على $label', (t) async {
        await pump(t, e.value(), w);
        expect(find.byType(Scaffold), findsWidgets);
      });
    }
  }

  testWidgets('A04 تعديل خانة يُظهر شريط الحفظ ومعاينة الأثر', (t) async {
    await pump(t, const RolesScreen(initialRole: CompanyRole.accountant), const Size(1200, 2600));
    await t.tap(find.byType(Checkbox).first);
    await t.pump();
    expect(find.text('تغييرات غير محفوظة'), findsOneWidget);
    await t.tap(find.text('معاينة الأثر والحفظ'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('أثر تعديل صلاحيات'), findsOneWidget);
  });

  testWidgets('طلب الموافقة يظهر للشريك', (t) async {
    await pump(t, const ConsentRequestsScreen(), const Size(1200, 2600));
    expect(find.text('جوال الشريك'), findsOneWidget);
  });
}
