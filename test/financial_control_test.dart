// اختبارات المرحلة 2: بوابة الفحص، التجميد، الاستثناء لمرة واحدة، المخالفات، الإشعارات
import 'package:flutter_test/flutter_test.dart';
import 'package:mithaq_app/models/company.dart';
import 'package:mithaq_app/models/operations.dart';
import 'package:mithaq_app/models/questionnaire.dart';
import 'package:mithaq_app/providers/contract_state.dart';
import 'package:mithaq_app/providers/operations_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ContractState cs;
  late OperationsState ops;
  late Company c;

  final members = const [
    CompanyMember(id: 'm', name: 'المدير', phone: '771000001', equity: 50, roles: {CompanyRole.managingPartner}),
    CompanyMember(id: 'a', name: 'أ', phone: '771000002', equity: 30, roles: {CompanyRole.partner}),
    CompanyMember(id: 'b', name: 'ب', phone: '771000003', equity: 20, roles: {CompanyRole.partner}),
  ];

  FinancialTx draft(double amount, TxCategory cat, {DateTime? date}) => FinancialTx(
        id: 'T${DateTime.now().microsecondsSinceEpoch}',
        companyId: c.id,
        date: date ?? DateTime(2026, 10, 5),
        amount: amount,
        currency: AppCurrency.usd,
        category: cat,
        payee: 'مورد',
        purpose: 'اختبار',
        createdBy: 'm',
        createdAt: DateTime.now(),
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cs = ContractState();
    await cs.load();
    ops = OperationsState();
    await ops.load();
    c = Company(
      id: 'C1',
      legalName: 'شركة',
      companyType: 'ذ.م.م',
      currency: AppCurrency.usd,
      capital: 100000,
      members: members,
      createdAt: DateTime.now(),
      createdBy: 'm',
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
    cs.complete(s); // سقف العملية 2,000، والسقف الشهري 10,000، وعقد > 10,000 يحتاج توقيعين
  });

  test('قبل اعتماد العقد لا توجد قواعد سارية، وبعده تُستخرج من البنود المعتمدة', () {
    final rules = ops.activeRules(cs, c.id);
    expect(rules.map((r) => r.rule.id), containsAll(['R-F02', 'R-F03', 'R-F04', 'R-F07']));
  });

  test('عملية ضمن الحد مسموحة، وما يتجاوزه يُجمّد مع سبب واضح', () {
    final ok = ops.submit(cs, c, draft(1500, TxCategory.purchase), actorName: 'المدير');
    expect(ok.status, TxStatus.allowed);

    final big = ops.submit(cs, c, draft(3500, TxCategory.purchase), actorName: 'المدير');
    expect(big.status, TxStatus.frozen);
    final hit = big.triggered.single;
    expect(hit.ruleId, 'R-F02');
    expect(hit.observed, contains('3500'));
    expect(hit.expected, contains('2,000'));
    // يصل إشعار لكل الشركاء، وقنوات الرسائل مسجلة كغير مهيأة بلا ادعاء تسليم
    final n = ops.notificationsFor(c.id, 'a').single;
    expect(n.deliveries.firstWhere((d) => d.channel == NotifChannel.sms).status, DeliveryStatus.notConfigured);
  });

  test('السقف الشهري يجمع مصروفات الشهر المقبولة', () {
    for (var i = 0; i < 5; i++) {
      expect(ops.submit(cs, c, draft(1900, TxCategory.expense), actorName: 'م').status, TxStatus.allowed);
    }
    // 9,500 + 1,000 = 10,500 > 10,000
    final over = ops.submit(cs, c, draft(1000, TxCategory.expense), actorName: 'م');
    expect(over.status, TxStatus.frozen);
    expect(over.triggered.single.ruleId, 'R-F03');
    // شهر آخر يبدأ من الصفر
    expect(ops.submit(cs, c, draft(1000, TxCategory.expense, date: DateTime(2026, 11, 2)), actorName: 'م').status,
        TxStatus.allowed);
  });

  test('السلفة الشخصية تُسجَّل مخالفة مباشرة', () {
    final t = ops.submit(cs, c, draft(500, TxCategory.personalAdvance), actorName: 'م');
    expect(t.status, TxStatus.violation);
    expect(ops.violationsFor(c.id).single.origin, contains('تلقائية'));
  });

  test('الاستثناء لمرة واحدة: موافقة مرجّحة من غير مقدّم الطلب تفرج عن العملية دون تعديل الحد', () {
    final t = ops.submit(cs, c, draft(3500, TxCategory.purchase), actorName: 'م');
    final ex = ops.requestException(c, t, t.triggered.single, reason: 'أجهزة عاجلة', requestedBy: 'm');
    expect(t.status, TxStatus.exceptionPending);
    expect(ops.eligibleVoters(c, ex).map((p) => p.id), ['a', 'b']); // المدير لا يصوّت على طلبه

    ops.voteException(c, ex, members[1], approve: true, method: 'بصمة'); // 30 من 50 = 60%
    expect(ex.status, ExceptionStatus.approved);
    expect(t.status, TxStatus.releasedException);
    // القاعدة لم تتغير: عملية مماثلة جديدة تُجمّد أيضاً
    expect(ops.submit(cs, c, draft(3500, TxCategory.purchase), actorName: 'م').status, TxStatus.frozen);
  });

  test('رفض الاستثناء يسجّل مخالفة رسمية', () {
    final t = ops.submit(cs, c, draft(4000, TxCategory.purchase), actorName: 'م');
    final ex = ops.requestException(c, t, t.triggered.single, reason: 'سبب', requestedBy: 'm');
    ops.voteException(c, ex, members[1], approve: false, method: 'بصمة', reason: 'غير ضروري');
    expect(ex.status, ExceptionStatus.rejected);
    expect(t.status, TxStatus.violation);
    expect(ops.violationsFor(c.id).single.origin, contains('رفض'));
  });

  test('انتهاء مهلة الاستثناء دون قرار يبقي العملية مجمّدة', () {
    final t = ops.submit(cs, c, draft(3000, TxCategory.purchase), actorName: 'م');
    ops.requestException(c, t, t.triggered.single, reason: 'سبب', requestedBy: 'm');
    expect(ops.expireOverdue(c, now: DateTime.now().add(const Duration(days: 4))), isTrue);
    expect(t.status, TxStatus.frozen);
    expect(ops.exceptionsFor(c.id).single.status, ExceptionStatus.expired);
  });

  test('لا يمكن إيقاف الإشعارات الإلزامية', () {
    ops.setMuted(c.id, 'a', NotifCategory.legal, true);
    ops.setMuted(c.id, 'a', NotifCategory.approval, true);
    expect(ops.mutedByMember['a'], {NotifCategory.approval});
  });
}
