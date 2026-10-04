// اختبار عرض شاشات المرحلة 2 ببيانات حقيقية: عملية مسموحة، مجمّدة، استثناء معلّق، مخالفة، إشعارات
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithaq_app/models/company.dart';
import 'package:mithaq_app/models/operations.dart';
import 'package:mithaq_app/models/questionnaire.dart';
import 'package:mithaq_app/providers/company_state.dart';
import 'package:mithaq_app/providers/contract_state.dart';
import 'package:mithaq_app/providers/operations_state.dart';
import 'package:mithaq_app/screens/admin/channels_screen.dart';
import 'package:mithaq_app/screens/admin/expense_limits_screen.dart';
import 'package:mithaq_app/screens/admin/integrations_screen.dart';
import 'package:mithaq_app/screens/admin/rule_test_screen.dart';
import 'package:mithaq_app/screens/operations/approvals_screen.dart';
import 'package:mithaq_app/screens/operations/expense_entry_screen.dart';
import 'package:mithaq_app/screens/operations/notifications_center_screen.dart';
import 'package:mithaq_app/screens/operations/ops_dashboard_screen.dart';
import 'package:mithaq_app/screens/operations/transactions_screen.dart';
import 'package:mithaq_app/screens/operations/tx_detail_screen.dart';
import 'package:mithaq_app/screens/operations/violations_screen.dart';
import 'package:mithaq_app/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late CompanyState companies;
  late ContractState contracts;
  late OperationsState ops;
  late Company c;
  late FinancialTx frozen;

  FinancialTx draft(double amount, TxCategory cat) => FinancialTx(
        id: 'T${DateTime.now().microsecondsSinceEpoch}',
        companyId: c.id,
        date: DateTime.now(),
        amount: amount,
        currency: AppCurrency.usd,
        category: cat,
        payee: 'مورد الأجهزة',
        purpose: 'أجهزة',
        createdBy: c.members.first.id,
        createdAt: DateTime.now(),
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    companies = CompanyState();
    await companies.load();
    contracts = ContractState()..auditSink = companies.log;
    await contracts.load();
    ops = OperationsState()..auditSink = companies.log;
    await ops.load();
    c = companies.createCompany(
      legalName: 'شركة سبأ',
      companyType: 'شركة ذات مسؤولية محدودة',
      currency: AppCurrency.usd,
      capital: 100000,
      members: const [
        CompanyMember(id: 'm', name: 'المدير', phone: '771000001', equity: 50, roles: {CompanyRole.managingPartner}),
        CompanyMember(id: 'a', name: 'أحمد', phone: '771000002', equity: 30, roles: {CompanyRole.partner}),
        CompanyMember(id: 'b', name: 'بكر', phone: '771000003', equity: 20, roles: {CompanyRole.partner}),
      ],
    );
    final s = contracts.createSession(
      companyId: c.id,
      companyName: c.legalName,
      companyType: c.companyType,
      currency: c.currency,
      capital: c.capital,
      partners: c.partners.map((m) => m.toSessionPartner()).toList(),
    );
    for (final r in s.records) {
      for (final p in contracts.voters(s, r)) {
        contracts.castVote(s, r, p.id, Ballot.agree, ConfirmMethod.manual);
      }
    }
    contracts.complete(s);

    ops.submit(contracts, c, draft(1500, TxCategory.purchase), actorName: 'المدير');
    frozen = ops.submit(contracts, c, draft(3500, TxCategory.purchase), actorName: 'المدير');
    final big = ops.submit(contracts, c, draft(2500, TxCategory.purchase), actorName: 'المدير');
    ops.requestException(c, frozen, frozen.triggered.first, reason: 'عرض سعر محدود', requestedBy: 'm');
    final ex = ops.requestException(c, big, big.triggered.first, reason: 'ضرورة', requestedBy: 'm');
    for (final v in c.members.where((m) => m.id != 'm')) {
      ops.voteException(c, ex, v, approve: false, method: 'manual');
    }
  });

  Future<void> pump(WidgetTester t, Widget screen) async {
    t.view.physicalSize = const Size(1200, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: companies),
        ChangeNotifierProvider.value(value: contracts),
        ChangeNotifierProvider.value(value: ops),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Directionality(textDirection: TextDirection.rtl, child: screen),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
  }

  test('بيانات السيناريو: مجمّدة باستثناء معلّق، ومخالفة من استثناء مرفوض', () {
    expect(ops.tx(frozen.id)!.status, TxStatus.exceptionPending);
    expect(ops.violationsFor(c.id), hasLength(1));
    expect(ops.notificationsFor(c.id, 'a'), isNotEmpty);
  });

  final screens = <String, Widget Function()>{
    'O01 لوحة التشغيل': () => const OpsDashboardScreen(),
    'O02 العمليات': () => const TransactionsScreen(),
    'O05 المجمّدة': () => const TransactionsScreen(frozenOnly: true),
    'O03 إدخال مصروف': () => const ExpenseEntryScreen(),
    'O12 المخالفات': () => const ViolationsScreen(),
    'P16 الموافقات': () => const ApprovalsScreen(),
    'P21 الإشعارات': () => const NotificationsCenterScreen(),
    'P22 تفضيلات الإشعار': () => const NotificationPrefsScreen(),
    'A10 اختبار القواعد': () => const RuleTestScreen(),
    'A13 حدود الصرف': () => const ExpenseLimitsScreen(),
    'A14 القنوات': () => const ChannelsScreen(),
    'A16 التكامل': () => const IntegrationsScreen(),
  };
  for (final e in screens.entries) {
    testWidgets('تعرض شاشة ${e.key} دون أخطاء', (t) async {
      await pump(t, e.value());
      expect(t.takeException(), isNull);
      expect(find.byType(Scaffold), findsWidgets);
    });
  }

  testWidgets('O04 تفاصيل العملية المجمّدة تعرض سبب التجميد والقاعدة', (t) async {
    await pump(t, TxDetailScreen(txId: frozen.id));
    expect(t.takeException(), isNull);
    expect(find.textContaining('R-F02'), findsWidgets);
  });

  testWidgets('A10 تشغيل اختبار مبلغ يتجاوز السقف يُظهر نتيجة التجميد', (t) async {
    await pump(t, const RuleTestScreen());
    await t.tap(find.text('تشغيل الاختبار'));
    await t.pump();
    expect(find.textContaining('النتيجة'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('A16 الاستيراد يمنع تكرار نفس المرجع', (t) async {
    await pump(t, const IntegrationsScreen());
    final before = ops.txFor(c.id).length;
    await t.tap(find.text('استيراد وتمرير بالفحص'));
    await t.pump();
    expect(ops.txFor(c.id).length, before + 2);
    await t.tap(find.text('استيراد وتمرير بالفحص'));
    await t.pump();
    expect(ops.txFor(c.id).length, before + 2);
  });
}
