// اختبارات المرحلة 4 (التشغيل): الحساب الجاري، الرواتب وقاعدة راتب الشريك المدير، الخطط،
// المراسلات، تنفيذ القرارات، والتنبيهات
import 'package:flutter_test/flutter_test.dart';
import 'package:mithaq_app/models/company.dart';
import 'package:mithaq_app/models/operations.dart';
import 'package:mithaq_app/models/ops_extra.dart';
import 'package:mithaq_app/models/questionnaire.dart';
import 'package:mithaq_app/providers/company_state.dart';
import 'package:mithaq_app/providers/contract_state.dart';
import 'package:mithaq_app/providers/daily_ops_state.dart';
import 'package:mithaq_app/providers/dispute_state.dart';
import 'package:mithaq_app/providers/operations_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late CompanyState companies;
  late ContractState cs;
  late OperationsState ops;
  late DisputeState ds;
  late DailyOpsState daily;
  late Company c;

  FinancialTx tx(double amount, TxCategory cat, {AppCurrency cur = AppCurrency.usd}) => FinancialTx(
        id: 'T${DateTime.now().microsecondsSinceEpoch}',
        companyId: c.id,
        date: DateTime.now(),
        amount: amount,
        currency: cur,
        category: cat,
        payee: 'المدير',
        purpose: 'اختبار',
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
      legalName: 'شركة سبأ',
      companyType: 'ذ.م.م',
      currency: AppCurrency.usd,
      capital: 100000,
      members: const [
        CompanyMember(id: 'm', name: 'المدير', phone: '771000001', equity: 60, roles: {CompanyRole.managingPartner}),
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
    companies.inviteStaff(c.id, name: 'سالم', phone: '771000009', role: CompanyRole.financialManager);
  });

  test('O08: السلفة المقبولة تُرحَّل آلياً، والأرصدة لكل عملة منفصلة', () {
    // السلفة الشخصية تخضع لقاعدة العقد؛ نعتمد استثناءها لتصبح مقبولة
    final adv = ops.submit(cs, c, tx(500, TxCategory.personalAdvance), actorName: 'المدير');
    final ex = ops.requestException(c, adv, adv.triggered.first, reason: 'ضرورة', requestedBy: 'm');
    ops.voteException(c, ex, c.members.firstWhere((m) => m.id == 'a'), approve: true, method: 'manual');
    expect(ops.tx(adv.id)!.status, TxStatus.releasedException);

    daily.addLedger(
        c,
        LedgerEntry(
            id: 'L1', companyId: c.id, partnerId: 'm', kind: LedgerKind.settlement, amount: 200, currency: AppCurrency.usd,
            date: DateTime.now(), reference: 'سند 1', createdBy: 'u'));
    daily.addLedger(
        c,
        LedgerEntry(
            id: 'L2', companyId: c.id, partnerId: 'm', kind: LedgerKind.opening, amount: 1000, currency: AppCurrency.sar,
            date: DateTime.now(), reference: 'افتتاحي', createdBy: 'u'));
    final entries = daily.ledgerFor(c, ops);
    expect(entries.where((e) => e.automatic), hasLength(1));
    final b = daily.balances(c, ops)['m']!;
    expect(b[AppCurrency.usd], 300); // 500 سلفة − 200 تسوية
    expect(b[AppCurrency.sar], 1000); // لا تُجمع مع الدولار
  });

  test('O09: تغيير راتب الشريك المدير يمر بقاعدة العقد وينتظر قرار الشركاء', () {
    expect(daily.createBatch(c, '2026-09', by: 'u'), isNull);
    final b1 = daily.payrollFor(c.id).single;
    expect(b1.lines.map((l) => l.employee), containsAll(['المدير', 'سالم']));
    daily.updateLines(c, b1, [
      const PayrollLine(employee: 'المدير', role: 'الشريك المدير', salary: 2000, managingPartner: true),
      const PayrollLine(employee: 'سالم', role: 'المدير المالي', salary: 800),
    ]);
    daily.submitBatch(c, b1, ops, cs, by: 'u', byName: 'سالم');
    expect(b1.status, PayrollStatus.pendingApproval); // لا يوجد راتب معتمد سابق
    daily.decideBatch(c, b1, approve: true, byName: 'المدير');
    expect(b1.status, PayrollStatus.approved);

    expect(daily.createBatch(c, '2026-10', by: 'u'), isNull);
    expect(daily.createBatch(c, '2026-10', by: 'u'), isNotNull); // دفعة واحدة لكل فترة
    final b2 = daily.payrollFor(c.id).firstWhere((b) => b.period == '2026-10');
    daily.updateLines(c, b2, [
      const PayrollLine(employee: 'المدير', role: 'الشريك المدير', salary: 2500, managingPartner: true),
      const PayrollLine(employee: 'سالم', role: 'المدير المالي', salary: 800),
    ]);
    daily.submitBatch(c, b2, ops, cs, by: 'u', byName: 'سالم');
    expect(b2.status, PayrollStatus.awaitingPartners);
    final rt = ops.tx(b2.ruleTxId!)!;
    expect(rt.category, TxCategory.salaryChange);
    daily.decideBatch(c, b2, approve: true, byName: 'المدير');
    expect(b2.status, PayrollStatus.awaitingPartners); // لا يُعتمد قبل قرار الشركاء

    final ex = ops.requestException(c, rt, rt.triggered.first, reason: 'زيادة سنوية', requestedBy: 'm');
    ops.voteException(c, ex, c.members.firstWhere((m) => m.id == 'a'), approve: true, method: 'manual');
    daily.refreshPayroll(c, ops);
    expect(b2.status, PayrollStatus.pendingApproval);
  });

  test('O14/O15: الخطة تمر بالاعتماد، والتنفيذ يُحدَّث بعد الاعتماد فقط، والانحراف يظهر تنبيهاً', () {
    final p = OpsPlan(
      id: 'P1',
      companyId: c.id,
      category: PlanCategory.marketing,
      year: 2026,
      title: 'حملة الربع',
      owner: 'سالم',
      segment: PlanSegment.quarterly,
      milestones: [Milestone(id: 'M1', title: 'عملاء جدد', period: 'الربع الأول', target: 100)],
      createdBy: 'u',
      createdAt: DateTime.now(),
    );
    daily.savePlan(c, p);
    daily.updateMilestone(c, p, p.milestones.first, actual: 50);
    expect(p.milestones.first.actual, isNull); // ليست معتمدة بعد
    daily.setPlanStatus(c, p, PlanStatus.approved, byName: 'المدير');
    expect(p.status, PlanStatus.draft); // لا يُعتمد قبل الرفع
    daily.setPlanStatus(c, p, PlanStatus.pending, byName: 'سالم');
    daily.setPlanStatus(c, p, PlanStatus.approved, byName: 'المدير');
    expect(p.status, PlanStatus.approved);
    daily.updateMilestone(c, p, p.milestones.first, actual: 60, status: MilestoneStatus.delayed, deviation: 'تأخر المورد');
    expect(p.milestones.first.variance, -40);
    final alerts = daily.alerts(c, cs, ds, ops);
    expect(alerts.any((a) => a.type == 'انحراف عن الخطة'), isTrue);
    final copy = daily.clonePlan(c, p, by: 'u');
    expect(copy.year, 2027);
    expect(copy.milestones.single.actual, isNull);
  });

  test('O16: المراسلة الصادرة يُقفل نصها ولا تُحذف، والمسودة تُحذف', () {
    final l = Letter(
        id: 'LT1', companyId: c.id, reference: daily.nextReference(c.id, true), outgoing: true, date: DateTime.now(),
        party: 'الغرفة التجارية', subject: 'إخطار', createdBy: 'u');
    daily.saveLetter(c, l);
    expect(l.reference, startsWith('OUT-'));
    daily.setLetterStatus(c, l, LetterStatus.sent);
    expect(l.locked, isTrue);
    expect(daily.deleteDraft(c, l), isFalse);
    final d = Letter(
        id: 'LT2', companyId: c.id, reference: daily.nextReference(c.id, true), outgoing: true, date: DateTime.now(),
        party: 'س', subject: 'مسودة', createdBy: 'u');
    daily.saveLetter(c, d);
    expect(d.reference, isNot(l.reference));
    expect(daily.deleteDraft(c, d), isTrue);
  });

  test('O11: الاستثناء المعتمد يصبح قراراً للتنفيذ، والإكمال يتطلب دليلاً', () {
    final big = ops.submit(cs, c, tx(3500, TxCategory.purchase), actorName: 'المدير');
    final ex = ops.requestException(c, big, big.triggered.first, reason: 'عرض محدود', requestedBy: 'm');
    ops.voteException(c, ex, c.members.firstWhere((m) => m.id == 'a'), approve: true, method: 'manual');
    final d = daily.decisions(c, cs, ds, ops).single;
    expect(d.type, 'استثناء معتمد');
    daily.updateExecution(c, d, status: ExecStatus.completed);
    expect(daily.executionOf(d.id).status, ExecStatus.pending); // بلا دليل
    daily.updateExecution(c, d, evidence: 'سند صرف 55');
    daily.updateExecution(c, d, status: ExecStatus.completed);
    expect(daily.executionOf(d.id).status, ExecStatus.completed);
  });

  test('O17: العملية المجمّدة تظهر تنبيهاً، والتأجيل يعيده جديداً بعد انقضائه', () {
    ops.submit(cs, c, tx(3500, TxCategory.purchase), actorName: 'المدير');
    final a = daily.alerts(c, cs, ds, ops).firstWhere((a) => a.type == 'عملية مجمّدة');
    expect(daily.statusOf(a.id), AlertStatus.open);
    var t = DateTime(2026, 10, 1);
    daily.now = () => t;
    daily.setAlert(c, a, AlertStatus.acknowledged, snooze: const Duration(hours: 24));
    expect(daily.statusOf(a.id), AlertStatus.acknowledged);
    t = t.add(const Duration(hours: 25));
    expect(daily.statusOf(a.id), AlertStatus.open);
  });
}
