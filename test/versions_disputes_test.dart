// اختبارات المرحلة 3: الإصدارات والتعديل (J03)، والجمود والنزاعات بمراحلها الخمس (J04)
import 'package:flutter_test/flutter_test.dart';
import 'package:mithaq_app/models/company.dart';
import 'package:mithaq_app/models/dispute.dart';
import 'package:mithaq_app/models/operations.dart';
import 'package:mithaq_app/models/questionnaire.dart';
import 'package:mithaq_app/providers/company_state.dart';
import 'package:mithaq_app/providers/contract_state.dart';
import 'package:mithaq_app/providers/dispute_state.dart';
import 'package:mithaq_app/providers/operations_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late CompanyState companies;
  late ContractState cs;
  late OperationsState ops;
  late DisputeState ds;
  late Company c;
  late ContractSession v1;
  var clock = DateTime(2026, 10, 1, 9);

  void agreeAll(ContractSession s, Iterable<ClauseRecord> recs) {
    for (final r in recs) {
      for (final p in cs.voters(s, r)) {
        cs.castVote(s, r, p.id, Ballot.agree, ConfirmMethod.manual);
      }
    }
  }

  void signAndComplete(ContractSession s) {
    for (final p in cs.signersOf(s)) {
      cs.signOff(s, PartnerSignOff(partnerId: p.id, signaturePng: 'sig-${p.id}', at: DateTime.now(), method: ConfirmMethod.manual));
    }
    cs.setWitnesses(s, [
      const Witness(name: 'شاهد 1', nationalId: '1', internal: false),
      const Witness(name: 'شاهد 2', nationalId: '2', internal: false),
    ]);
    cs.attestWitness(s, 0, signature: 'w1', method: ConfirmMethod.manual);
    cs.attestWitness(s, 1, signature: 'w2', method: ConfirmMethod.manual);
    expect(cs.finalizeBlockers(s), isEmpty);
    cs.complete(s);
  }

  FinancialTx tx(double amount) => FinancialTx(
        id: 'T${DateTime.now().microsecondsSinceEpoch}',
        companyId: c.id,
        date: DateTime(2026, 10, 5),
        amount: amount,
        currency: AppCurrency.usd,
        category: TxCategory.purchase,
        payee: 'مورد',
        purpose: 'اختبار',
        createdBy: 'm',
        createdAt: DateTime.now(),
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime(2026, 10, 1, 9);
    companies = CompanyState();
    await companies.load();
    cs = ContractState()..auditSink = companies.log;
    await cs.load();
    ops = OperationsState()..auditSink = companies.log;
    await ops.load();
    ds = DisputeState()
      ..auditSink = companies.log
      ..now = (() => clock)
      ..companyOf = ((id) => companies.companies.where((x) => x.id == id).firstOrNull)
      ..onCompanyStatus = companies.setStatus;
    await ds.load();
    cs
      ..amendmentLocked = ds.locked
      ..onVersionCompleted = (s) => companies.applyVersion(s.companyId!, s.version,
          equity: {for (final p in s.partners) p.id: p.equity});
    ops.exceptionsLocked = ds.arbitrationActive;

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
    agreeAll(v1, v1.records);
    signAndComplete(v1);
  });

  group('الإصدارات والتعديل (J03)', () {
    test('الإصدار الساري بعد التأسيس هو الإصدار 1، ورقم إصدار الشركة يتحدث', () {
      expect(cs.currentContract(c.id)?.id, v1.id);
      expect(c.contractVersion, 1);
      expect(cs.verifyHash(v1), isTrue);
    });

    test('التعديل يطرح البند المعدّل فقط للتصويت، والعقد الحالي يبقى سارياً حتى الاعتماد', () {
      final cap = v1.records.firstWhere((r) => r.key == 'F02');
      expect(cap.value, 2000);
      final v2 = cs.proposeAmendment(v1, changes: {'F02': 5000}, reason: 'توسع النشاط', proposedBy: 'm');
      expect(v2.version, 2);
      expect(v2.records.where((r) => r.amended).map((r) => r.key), ['F02']);
      expect(v2.records.firstWhere((r) => r.key == 'F02').previousValue, 2000);
      expect(v2.records.where((r) => !r.amended).every((r) => r.status != ClauseStatus.pending), isTrue);
      expect(cs.currentContract(c.id)?.id, v1.id); // لم يُعتمد بعد
      expect(cs.amendmentBlocker(c.id), isNotNull); // مقترح واحد في كل مرة

      // قبل الاعتماد: عملية بـ 3,500 تُجمّد حسب الإصدار 1
      expect(ops.submit(cs, c, tx(3500), actorName: 'المدير').status, TxStatus.frozen);
    });

    test('اعتماد الإصدار 2 يؤرشف الإصدار 1، ويحدّث قواعد الرقابة للعمليات القادمة فقط', () {
      final before = ops.submit(cs, c, tx(3500), actorName: 'المدير');
      expect(before.status, TxStatus.frozen);

      final v2 = cs.proposeAmendment(v1, changes: {'F02': 5000}, reason: 'توسع النشاط', proposedBy: 'm');
      agreeAll(v2, v2.records.where((r) => r.amended));
      expect(v2.allResolved, isTrue);
      signAndComplete(v2);

      expect(v1.archived, isTrue);
      expect(v1.supersededBy, v2.id);
      expect(cs.currentContract(c.id)?.id, v2.id);
      expect(c.contractVersion, 2);
      expect(cs.verifyHash(v2), isTrue);
      expect(cs.verifyHash(v1), isTrue); // الأرشفة لا تغيّر محتوى الإصدار السابق

      expect(ops.submit(cs, c, tx(3500), actorName: 'المدير').status, TxStatus.allowed);
      expect(ops.tx(before.id)!.status, TxStatus.frozen); // العمليات السابقة لا يُعاد تقييمها

      final diff = cs.compare(v1, v2);
      expect(diff, hasLength(1));
      expect(diff.single.before, contains('2,000'));
      expect(diff.single.after, contains('5,000'));
    });

    test('مقترح لم يُعتمد يُنهى ويبقى في سجل الإصدارات دون أن يمس العقد', () {
      final v2 = cs.proposeAmendment(v1, changes: {'F02': 9000}, reason: 'تجربة', proposedBy: 'a');
      final r = v2.records.firstWhere((x) => x.amended);
      cs.castVote(v2, r, 'm', Ballot.disagree, ConfirmMethod.manual);
      cs.castVote(v2, r, 'a', Ballot.agree, ConfirmMethod.manual);
      expect(r.status, isNot(ClauseStatus.agreed));
      cs.withdrawAmendment(v2, reason: 'لم يحصل على الأغلبية');
      expect(v2.status, SessionStatus.withdrawn);
      expect(cs.currentContract(c.id)?.id, v1.id);
      expect(cs.versionsFor(c.id), hasLength(2));
      expect(cs.amendmentBlocker(c.id), isNull);
    });
  });

  group('النزاعات (J04)', () {
    Dispute openDispute() => ds.open(c,
        trigger: DisputeTrigger.other, issue: 'خلاف على التوسع', openedBy: 'a', openedByName: 'أحمد');

    test('فتح النزاع يقفل التعديلات، ولا تتكرر التذكرة للمرجع نفسه', () {
      final d1 = ds.open(c,
          trigger: DisputeTrigger.deadlock, issue: 'جمود', relatedId: 'S1:F02:2', openedBy: 'system', openedByName: 'النظام');
      final d2 = ds.open(c,
          trigger: DisputeTrigger.deadlock, issue: 'جمود', relatedId: 'S1:F02:2', openedBy: 'system', openedByName: 'النظام');
      expect(d1.id, d2.id);
      expect(ds.disputesFor(c.id), hasLength(1));
      expect(d1.stage, DisputeStage.negotiation);
      expect(d1.deadline.difference(d1.openedAt).inDays, 14);
      expect(cs.amendmentBlocker(c.id), contains('نزاع'));
      // التعديل الناتج عن النزاع نفسه مسموح
      expect(cs.amendmentBlocker(c.id, disputeRef: d1.id), isNull);
    });

    test('الصلح بموافقة كل الأطراف يحسم النزاع ويرفع القفل', () {
      final d = openDispute();
      ds.proposeSettlement(c, d, 'نؤجل التوسع ستة أشهر', authorId: 'a', authorName: 'أحمد');
      expect(d.isOpen, isTrue);
      ds.approveSettlement(c, d, 'm', memberName: 'المدير', method: 'manual');
      expect(d.status, DisputeStatus.resolved);
      expect(ds.locked(c.id), isFalse);
      ds.close(c, d, byName: 'أحمد');
      expect(d.status, DisputeStatus.closed);
    });

    test('انقضاء المهل ينقل النزاع: تفاوض ثم وساطة ثم كسر الجمود', () {
      final d = openDispute();
      clock = clock.add(const Duration(days: 15));
      expect(ds.expireOverdue(), 1);
      expect(d.stage, DisputeStage.mediation);
      clock = clock.add(const Duration(days: 31));
      ds.expireOverdue();
      expect(d.stage, DisputeStage.deadlockBreak);
      expect(d.entries.where((e) => e.isSystem).length, greaterThanOrEqualTo(3));
    });

    test('عرض الشراء: اختيار البيع ينقل الحصة، والتنفيذ بإصدار جدول حصص جديد', () {
      final d = openDispute();
      ds.consentEscalate(c, d, 'm', memberName: 'المدير');
      ds.consentEscalate(c, d, 'a', memberName: 'أحمد');
      expect(d.stage, DisputeStage.mediation);
      ds.consentEscalate(c, d, 'm', memberName: 'المدير');
      ds.consentEscalate(c, d, 'a', memberName: 'أحمد');
      expect(d.stage, DisputeStage.deadlockBreak);

      expect(ds.submitBuyOut(c, d, offerorId: 'm', targetId: 'a', price: 40000, offerorName: 'المدير'), isNull);
      expect(d.status, DisputeStatus.awaitingParty);
      ds.chooseBuyOut(c, d, sell: true, method: 'manual');
      expect(d.status, DisputeStatus.resolved);
      expect(d.equityAfter, {'m': 100.0, 'a': 0.0});
      expect(d.needsAmendment, isTrue);

      final v2 = cs.proposeCapTable(cs.currentContract(c.id)!,
          equity: d.equityAfter!, reason: 'تنفيذ كسر الجمود', proposedBy: 'm', disputeRef: d.id);
      ds.linkAmendment(c, d, v2.id);
      expect(v2.allResolved, isTrue);
      expect(cs.signersOf(v2).map((p) => p.id), ['m']); // البائع لم يعد صاحب حصة
      signAndComplete(v2);
      expect(c.partners.firstWhere((m) => m.id == 'a').equity, 0);
      expect(c.partners.firstWhere((m) => m.id == 'm').equity, 100);
      expect(c.contractVersion, 2);
    });

    test('انقضاء مهلة عرض الشراء دون رد لا يُعدّ قبولاً ويحيل للتحكيم، والتحكيم يوقف الاستثناءات', () {
      final d = openDispute();
      for (var i = 0; i < 2; i++) {
        ds.consentEscalate(c, d, 'm', memberName: 'المدير');
        ds.consentEscalate(c, d, 'a', memberName: 'أحمد');
      }
      ds.submitBuyOut(c, d, offerorId: 'a', targetId: 'm', price: 70000, offerorName: 'أحمد');
      clock = clock.add(const Duration(hours: 73));
      ds.expireOverdue();
      expect(d.stage, DisputeStage.arbitration);
      expect(d.equityAfter, isNull);
      expect(ds.arbitrationActive(c.id), isTrue);

      final frozen = ops.submit(cs, c, tx(3500), actorName: 'المدير');
      expect(ops.exceptionBlocker(c.id), isNotNull);
      expect(() => ops.requestException(c, frozen, frozen.triggered.first, reason: 'ضرورة', requestedBy: 'm'),
          throwsStateError);
    });

    test('حكم بفض الشراكة ينقل للتصفية: الديون الممتازة أولاً ثم توزيع الصافي بالحصص', () {
      final d = openDispute();
      for (var i = 0; i < 3; i++) {
        ds.consentEscalate(c, d, 'm', memberName: 'المدير');
        ds.consentEscalate(c, d, 'a', memberName: 'أحمد');
      }
      expect(d.stage, DisputeStage.arbitration);
      ds.recordAward(c, d, text: 'فض الشراكة', outcome: AwardOutcome.dissolve, ref: 'ARB-1');
      expect(d.stage, DisputeStage.liquidation);
      expect(c.status, CompanyStatus.liquidation);

      ds.setLiquidation(c, d, liquidator: 'مكتب التصفية', assets: 50000);
      ds.addDebt(c, d, const LiquidationDebt(creditor: 'رواتب', amount: 10000, preferred: true));
      ds.addDebt(c, d, const LiquidationDebt(creditor: 'مورد', amount: 20000));
      final p = DisputeState.plan(c, d);
      expect(p.net, 20000);
      expect(p.distribution['m'], closeTo(12000, 0.01));
      expect(p.distribution['a'], closeTo(8000, 0.01));

      // أصول لا تكفي: الممتاز كاملاً والعادي بالمحاصّة ولا صافي
      ds.setLiquidation(c, d, assets: 20000);
      final q = DisputeState.plan(c, d);
      expect(q.payments.first.$2, 10000);
      expect(q.payments.last.$2, 10000);
      expect(q.net, 0);

      ds.closeLiquidation(c, d, method: 'manual');
      expect(d.status, DisputeStatus.closed);
      expect(c.status, CompanyStatus.archived);
    });
  });
}
