// اختبار عرض شاشات المرحلة 3 ببيانات حقيقية: إصدار ساري ومقترح تعديل، ونزاع في كل مرحلة
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithaq_app/models/company.dart';
import 'package:mithaq_app/models/dispute.dart';
import 'package:mithaq_app/models/questionnaire.dart';
import 'package:mithaq_app/providers/company_state.dart';
import 'package:mithaq_app/providers/contract_state.dart';
import 'package:mithaq_app/providers/dispute_state.dart';
import 'package:mithaq_app/providers/operations_state.dart';
import 'package:mithaq_app/screens/admin/version_manager_screen.dart';
import 'package:mithaq_app/screens/company/audit_log_screen.dart';
import 'package:mithaq_app/screens/disputes/dispute_detail_screen.dart';
import 'package:mithaq_app/screens/disputes/disputes_screen.dart';
import 'package:mithaq_app/screens/establishment/final_contract_screen.dart';
import 'package:mithaq_app/screens/versions/amendment_screens.dart';
import 'package:mithaq_app/screens/versions/versions_screen.dart';
import 'package:mithaq_app/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late CompanyState companies;
  late ContractState cs;
  late OperationsState ops;
  late DisputeState ds;
  late Company c;
  late ContractSession v1;
  late ContractSession v2;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    companies = CompanyState();
    await companies.load();
    cs = ContractState()..auditSink = companies.log;
    await cs.load();
    ops = OperationsState()..auditSink = companies.log;
    await ops.load();
    ds = DisputeState()
      ..auditSink = companies.log
      ..companyOf = ((id) => companies.companies.where((x) => x.id == id).firstOrNull);
    await ds.load();
    cs
      ..amendmentLocked = ds.locked
      ..onVersionCompleted = ((s) => companies.applyVersion(s.companyId!, s.version));

    c = companies.createCompany(
      legalName: 'شركة سبأ',
      companyType: 'ذ.م.م',
      currency: AppCurrency.usd,
      capital: 100000,
      members: const [
        CompanyMember(id: 'm', name: 'المدير', phone: '771000001', equity: 60, roles: {CompanyRole.managingPartner}),
        CompanyMember(id: 'a', name: 'أحمد', phone: '771000002', equity: 40, roles: {CompanyRole.partner}),
      ],
    );
    v1 = cs.createSession(
      companyId: c.id,
      companyName: c.legalName,
      companyType: c.companyType,
      currency: c.currency,
      capital: c.capital,
      partners: c.partners.map((m) => m.toSessionPartner()).toList(),
    );
    for (final r in v1.records) {
      for (final p in cs.voters(v1, r)) {
        cs.castVote(v1, r, p.id, Ballot.agree, ConfirmMethod.manual);
      }
    }
    cs.complete(v1);
    v2 = cs.proposeAmendment(v1, changes: {'F02': 5000}, reason: 'توسع النشاط', proposedBy: 'm');
  });

  Future<void> pump(WidgetTester t, Widget screen) async {
    t.view.physicalSize = const Size(1200, 2600);
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

  Dispute dispute() => ds.open(c, trigger: DisputeTrigger.other, issue: 'خلاف على التوسع', openedBy: 'a', openedByName: 'أحمد');

  void escalate(Dispute d, int times) {
    for (var i = 0; i < times; i++) {
      ds.consentEscalate(c, d, 'm', memberName: 'المدير');
      ds.consentEscalate(c, d, 'a', memberName: 'أحمد');
    }
  }

  testWidgets('P14 الإصدارات: الإصدار الساري ومقترح الإصدار 2', (t) async {
    await pump(t, const VersionsScreen());
    expect(t.takeException(), isNull);
    expect(find.text('الإصدار 2 · تعديل بنود'), findsOneWidget);
    expect(find.text('الإصدار الساري'), findsOneWidget);
  });

  testWidgets('P14 المقارنة تعرض الفرق قبل وبعد', (t) async {
    await pump(t, VersionCompareScreen(fromId: v1.id, toId: v2.id));
    expect(t.takeException(), isNull);
    expect(find.textContaining('1 فروق'), findsOneWidget);
  });

  testWidgets('J03 تفاصيل مقترح التعديل ومقترح جديد محجوب بوجود مقترح قائم', (t) async {
    await pump(t, AmendmentDetailScreen(sessionId: v2.id));
    expect(t.takeException(), isNull);
    expect(find.textContaining('التوقيع بعد حسم'), findsOneWidget);
    await pump(t, const AmendmentProposalScreen());
    expect(t.takeException(), isNull);
    expect(find.textContaining('مقترح تعديل قائم'), findsOneWidget);
  });

  testWidgets('P13 الإصدار المؤرشف يظهر للقراءة فقط', (t) async {
    for (final r in v2.records.where((r) => r.amended)) {
      for (final p in cs.voters(v2, r)) {
        cs.castVote(v2, r, p.id, Ballot.agree, ConfirmMethod.manual);
      }
    }
    cs.complete(v2);
    await pump(t, FinalContractScreen(sessionId: v1.id));
    expect(t.takeException(), isNull);
    expect(find.textContaining('إصدار مؤرشف'), findsOneWidget);
  });

  testWidgets('P18 قائمة النزاعات', (t) async {
    dispute();
    await pump(t, const DisputesScreen());
    expect(t.takeException(), isNull);
    expect(find.text('خلاف على التوسع'), findsOneWidget);
  });

  for (final (label, times) in [('التفاوض', 0), ('الوساطة', 1), ('كسر الجمود', 2), ('التحكيم', 3)]) {
    testWidgets('P19 تفاصيل النزاع في مرحلة $label', (t) async {
      final d = dispute();
      escalate(d, times);
      if (times == 2) ds.submitBuyOut(c, d, offerorId: 'a', targetId: 'm', price: 70000, offerorName: 'أحمد');
      await pump(t, DisputeDetailScreen(disputeId: d.id));
      expect(t.takeException(), isNull);
      expect(find.textContaining('إجراءات'), findsWidgets);
    });
  }

  testWidgets('P19 التصفية: جدول السداد والقسمة', (t) async {
    final d = dispute();
    escalate(d, 3);
    ds.recordAward(c, d, text: 'فض الشراكة', outcome: AwardOutcome.dissolve, ref: 'ARB-1');
    ds.setLiquidation(c, d, liquidator: 'مكتب التصفية', assets: 50000);
    await pump(t, DisputeDetailScreen(disputeId: d.id));
    expect(t.takeException(), isNull);
    expect(find.textContaining('الصافي للتوزيع'), findsOneWidget);
  });

  testWidgets('P19 بعد الشراء: زر إنشاء إصدار جدول الحصص', (t) async {
    final d = dispute();
    escalate(d, 2);
    ds.submitBuyOut(c, d, offerorId: 'm', targetId: 'a', price: 40000, offerorName: 'المدير');
    ds.chooseBuyOut(c, d, sell: true, method: 'manual');
    await pump(t, DisputeDetailScreen(disputeId: d.id));
    expect(t.takeException(), isNull);
    expect(find.text('إنشاء الإصدار الجديد لتنفيذ الحسم'), findsOneWidget);
  });

  testWidgets('P15 سجل التدقيق مع التصفية والتفاصيل', (t) async {
    dispute();
    await pump(t, const AuditLogScreen());
    expect(t.takeException(), isNull);
    await t.tap(find.textContaining('فتح تذكرة نزاع').first);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('مرجع الدليل'), findsOneWidget);
  });

  testWidgets('A19 إدارة الإصدارات', (t) async {
    await pump(t, const VersionManagerScreen());
    expect(t.takeException(), isNull);
    expect(find.text('البنود القانونية'), findsOneWidget);
  });
}
