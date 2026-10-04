// عرض شاشات التشغيل والتقارير والملف الشخصي (المرحلة 4) على الحاسب والجوال ببيانات حقيقية
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithaq_app/models/company.dart';
import 'package:mithaq_app/models/operations.dart';
import 'package:mithaq_app/models/ops_extra.dart';
import 'package:mithaq_app/models/questionnaire.dart';
import 'package:mithaq_app/providers/app_state.dart';
import 'package:mithaq_app/providers/company_state.dart';
import 'package:mithaq_app/providers/contract_state.dart';
import 'package:mithaq_app/providers/daily_ops_state.dart';
import 'package:mithaq_app/providers/dispute_state.dart';
import 'package:mithaq_app/providers/operations_state.dart';
import 'package:mithaq_app/screens/operations/approval_center_screen.dart';
import 'package:mithaq_app/screens/operations/correspondence_screen.dart';
import 'package:mithaq_app/screens/operations/current_account_screen.dart';
import 'package:mithaq_app/screens/operations/decision_execution_screen.dart';
import 'package:mithaq_app/screens/operations/expense_limits_screen.dart';
import 'package:mithaq_app/screens/operations/ops_alerts_screen.dart';
import 'package:mithaq_app/screens/operations/payroll_screen.dart';
import 'package:mithaq_app/screens/operations/plans_screen.dart';
import 'package:mithaq_app/screens/profile_screen.dart';
import 'package:mithaq_app/screens/reports/reports_screen.dart';
import 'package:mithaq_app/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late CompanyState companies;
  late ContractState cs;
  late OperationsState ops;
  late DisputeState ds;
  late DailyOpsState daily;
  late Company c;

  FinancialTx tx(double amount, TxCategory cat) => FinancialTx(
        id: 'T${DateTime.now().microsecondsSinceEpoch}',
        companyId: c.id,
        date: DateTime.now(),
        amount: amount,
        currency: AppCurrency.usd,
        category: cat,
        payee: 'مورد الأجهزة المكتبية',
        purpose: 'أجهزة',
        createdBy: 'm',
        createdAt: DateTime.now(),
      );

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
    daily = DailyOpsState()..auditSink = companies.log;
    await daily.load();
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
    final s = cs.createSession(
      companyId: c.id,
      companyName: c.legalName,
      companyType: c.companyType,
      currency: c.currency,
      capital: c.capital,
      partners: c.partners.map((m) => m.toSessionPartner()).toList(),
    );
    for (final r in s.records) {
      for (final p in cs.voters(s, r)) {
        cs.castVote(s, r, p.id, Ballot.agree, ConfirmMethod.manual);
      }
    }
    cs.complete(s);
    companies.inviteStaff(c.id, name: 'سالم المالي', phone: '771000009', role: CompanyRole.financialManager);
    ops.submit(cs, c, tx(1500, TxCategory.hospitality), actorName: 'المدير');
    final big = ops.submit(cs, c, tx(3500, TxCategory.purchase), actorName: 'المدير');
    final ex = ops.requestException(c, big, big.triggered.first, reason: 'عرض محدود', requestedBy: 'm');
    ops.voteException(c, ex, c.members.firstWhere((m) => m.id == 'a'), approve: true, method: 'manual');
    ops.submit(cs, c, tx(4000, TxCategory.purchase), actorName: 'المدير');
    daily.createBatch(c, '2026-10', by: 'u');
    daily.savePlan(
        c,
        OpsPlan(
          id: 'P1',
          companyId: c.id,
          category: PlanCategory.marketing,
          year: 2026,
          title: 'حملة التوسع في عدن',
          owner: 'سالم المالي',
          status: PlanStatus.pending,
          milestones: [Milestone(id: 'M1', title: 'عملاء جدد', period: 'الربع الأول', target: 100)],
          createdBy: 'u',
          createdAt: DateTime.now(),
        ));
    daily.saveLetter(
        c,
        Letter(
            id: 'LT1', companyId: c.id, reference: 'OUT-2026-001', outgoing: true, date: DateTime.now(),
            party: 'الغرفة التجارية الصناعية بصنعاء', subject: 'إخطار بتعديل العقد', createdBy: 'u'));
    daily.addLedger(
        c,
        LedgerEntry(
            id: 'L1', companyId: c.id, partnerId: 'm', kind: LedgerKind.opening, amount: 1000, currency: AppCurrency.sar,
            date: DateTime.now(), reference: 'افتتاحي', createdBy: 'u'));
  });

  Future<void> pump(WidgetTester t, Widget screen, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider.value(value: companies),
        ChangeNotifierProvider.value(value: cs),
        ChangeNotifierProvider.value(value: ops),
        ChangeNotifierProvider.value(value: ds),
        ChangeNotifierProvider.value(value: daily),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Directionality(textDirection: TextDirection.rtl, child: screen),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
  }

  final screens = <String, Widget Function()>{
    'O07 المصروفات والضيافة': () => const ExpenseLimitsMonitorScreen(),
    'O08 الحساب الجاري': () => const CurrentAccountScreen(),
    'O09 الرواتب': () => const PayrollScreen(),
    'O10 مركز الموافقات': () => const ApprovalCenterScreen(),
    'O11 تنفيذ القرارات': () => const DecisionExecutionScreen(),
    'O14 الخطط': () => const PlansScreen(),
    'O15 تفاصيل الخطة': () => const PlanDetailScreen(planId: 'P1'),
    'O16 المراسلات': () => const CorrespondenceScreen(),
    'O17 التنبيهات': () => const OpsAlertsScreen(),
    'P20 تقارير الشركاء': () => const ReportsScreen(),
    'O13 التقارير التشغيلية': () => const ReportsScreen(operational: true),
    'تقرير العمليات المالية': () => const ReportViewScreen(type: ReportType.financial),
    'تقرير الحوكمة': () => const ReportViewScreen(type: ReportType.governance),
    'P23 الملف الشخصي والأمان': () => const ProfileScreen(),
  };
  for (final (size, label) in [(const Size(1200, 2600), 'الحاسب'), (const Size(390, 2600), 'الجوال')]) {
    for (final e in screens.entries) {
      testWidgets('${e.key} على $label', (t) async {
        await pump(t, e.value(), size);
        expect(find.byType(Scaffold), findsWidgets);
      });
    }
  }

  testWidgets('O09 تفاصيل الدفعة تعرض الموظفين وزر الرفع', (t) async {
    await pump(t, PayrollBatchScreen(batchId: daily.payrollFor(c.id).single.id), const Size(390, 2600));
    expect(find.textContaining('أدخل كل الرواتب'), findsOneWidget);
  });

  testWidgets('O10 القرارات التي للشركاء تظهر في تبويب منفصل للإحالة', (t) async {
    await pump(t, const ApprovalCenterScreen(), const Size(1200, 2600));
    expect(find.textContaining('قرارات الشركاء'), findsOneWidget);
    expect(find.textContaining('خطة'), findsWidgets);
  });
}
