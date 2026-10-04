// اختبارات المرحلة 6: الحوكمة العائلية (التفعيل، الدستور بقرار عائلي، حصر الوراثة، التوزيع، الخلافة وانتقال الحصص)
import 'package:flutter_test/flutter_test.dart';
import 'package:mithaq_app/models/company.dart';
import 'package:mithaq_app/models/family.dart';
import 'package:mithaq_app/models/questionnaire.dart';
import 'package:mithaq_app/providers/company_state.dart';
import 'package:mithaq_app/providers/contract_state.dart';
import 'package:mithaq_app/providers/family_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late CompanyState companies;
  late ContractState cs;
  late FamilyState f;
  late Company c;
  var clock = DateTime(2026, 10, 4, 10);

  void approveAll(FamilyDecision d) {
    for (final id in d.weights.keys.toList()) {
      if (d.status == FamilyDecisionStatus.open) f.vote(c, d, id, approve: true, method: 'manual', name: id);
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime(2026, 10, 4, 10);
    companies = CompanyState();
    await companies.load();
    cs = ContractState()
      ..auditSink = companies.log
      ..onVersionCompleted = ((s) => companies.applyVersion(s.companyId!, s.version, equity: {for (final p in s.partners) p.id: p.equity}));
    await cs.load();
    f = FamilyState()
      ..auditSink = companies.log
      ..now = (() => clock);
    await f.load();
    c = companies.createCompany(
      legalName: 'مؤسسة آل سالم',
      companyType: 'ذ.م.م',
      currency: AppCurrency.usd,
      capital: 100000,
      members: const [
        CompanyMember(id: 'm', name: 'سالم الأب', phone: '771000001', equity: 60, roles: {CompanyRole.managingPartner}),
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
  });

  test('الوحدة مخفية حتى يفعّلها الشركاء، وبوابة العائلة للشركاء وأفراد العائلة المدعوين', () {
    expect(companies.myModules.any(kFamilyModules.contains), isFalse);
    expect(companies.myPortals, isNot(contains(Portal.family)));
    companies.setFamilyEnabled(c.id, true);
    expect(companies.myPortals, contains(Portal.family));
    companies.portal = Portal.family;
    expect(companies.myModules, containsAll(kFamilyModules));
    companies.inviteStaff(c.id, name: 'فاطمة', phone: '771000003', role: CompanyRole.familyMember);
    expect(c.toJson()['familyPhones'], contains('+967771000003'));
    expect(Permissions.effectiveModules({CompanyRole.familyMember}, c), isNot(contains(AppModule.voting)));
  });

  test('R10/R14: الدستور يُعتمد بقرار عائلي بعتبة التعديل، والسابق يُؤرشف', () {
    companies.setFamilyEnabled(c.id, true);
    final d1 = f.startDraft(c, by: 'm');
    expect(d1.version, 1);
    final dec = f.submitConstitution(c, d1, summary: 'الدستور الأول', by: 'm')!;
    expect(dec.threshold, 66.67);
    f.vote(c, dec, 'm', approve: true, method: 'manual', name: 'سالم'); // 60% أقل من 66.67%
    expect(dec.status, FamilyDecisionStatus.open);
    f.vote(c, dec, 'a', approve: true, method: 'manual', name: 'أحمد');
    expect(dec.status, FamilyDecisionStatus.approved);
    expect(f.current(c.id)!.version, 1);

    final d2 = f.startDraft(c, by: 'm');
    d2.sections = [...d2.sections, const ConstitutionSection('بند جديد', 'نص')];
    final dec2 = f.submitConstitution(c, d2, summary: 'إضافة بند', by: 'm')!;
    f.vote(c, dec2, 'a', approve: false, method: 'manual', name: 'أحمد'); // 40% رفض: لا يمكن بلوغ 66.67%
    expect(dec2.status, FamilyDecisionStatus.rejected);
    expect(f.current(c.id)!.version, 1);
    expect(d2.status, ConstitutionStatus.draft);
  });

  test('انتهاء مهلة القرار دون العتبة لا يُعدّ موافقة', () {
    companies.setFamilyEnabled(c.id, true);
    final d = f.openDecision(c, type: FamilyDecisionType.other, title: 'شراء عقار للعائلة', by: 'm');
    f.vote(c, d, 'a', approve: true, method: 'manual', name: 'أحمد');
    clock = clock.add(const Duration(days: 8));
    f.expireOverdue(c);
    expect(d.status, FamilyDecisionStatus.expired);
  });

  test('R11/R12: حصر الوراثة يُدخل كما ورد ويُعتمد بقرار، والتوزيع حسب قاعدة الدستور ثابت بعد الاعتماد', () {
    companies.setFamilyEnabled(c.id, true);
    f.seedFounders(c);
    final father = f.peopleFor(c.id).firstWhere((p) => p.memberId == 'm');
    final son = FamilyPerson(id: 'P1', companyId: c.id, name: 'خالد', relation: 'ابن', parentId: father.id, generation: 2);
    final daughter = FamilyPerson(id: 'P2', companyId: c.id, name: 'مريم', relation: 'بنت', parentId: father.id, generation: 2);
    f.savePerson(c, son);
    f.savePerson(c, daughter);
    final bad = InheritanceDeed(id: 'D1', companyId: c.id, deceasedId: father.id, reference: 'ح/1', court: 'محكمة غرب الأمانة', date: clock, shares: {'P1': 60, 'P2': 30});
    expect(f.submitDeed(c, bad, by: 'm'), contains('100%'));
    final deed = InheritanceDeed(
        id: 'D2', companyId: c.id, deceasedId: father.id, reference: 'ح/1', court: 'محكمة غرب الأمانة', date: clock, shares: {'P1': 66.67, 'P2': 33.33});
    expect(f.submitDeed(c, deed, by: 'm'), isNull);
    approveAll(f.decision(deed.decisionRef!)!);
    expect(deed.status, RecordStatus.approved);
    expect(f.person('P1')!.role, SuccessionRole.heir);

    final con = f.startDraft(c, by: 'm')..distributionRule = DistributionRule.heirShares;
    approveAll(f.submitConstitution(c, con, summary: 'التوزيع حسب حصر الوراثة', by: 'm')!);
    expect(f.createDistribution(c, period: '2026', available: 9000, by: 'm'), isNull);
    final x = f.distributionsFor(c.id).single;
    expect(x.allocations['P1'], closeTo(6000.3, 0.01));
    expect(x.constitutionVersion, 1);
    f.submitDistribution(c, x, by: 'm');
    approveAll(f.decision(x.decisionRef!)!);
    expect(x.status, DistributionStatus.approved);
    f.executeDistribution(c, x, reference: 'حوالة 77');
    expect(x.status, DistributionStatus.executed);
    expect(x.immutable, isTrue);
  });

  test('R13: الخلافة تحتاج دليلاً وقراراً، وحصة المتوفى تنتقل للورثة بإصدار عقد يضمهم شركاء', () {
    companies.setFamilyEnabled(c.id, true);
    f.seedFounders(c);
    companies.inviteStaff(c.id, name: 'خالد', phone: '771000005', role: CompanyRole.familyMember);
    companies.inviteStaff(c.id, name: 'مريم', phone: '771000006', role: CompanyRole.familyMember);
    final khalid = c.staffMembers.firstWhere((m) => m.name == 'خالد');
    final maryam = c.staffMembers.firstWhere((m) => m.name == 'مريم');
    final father = f.peopleFor(c.id).firstWhere((p) => p.memberId == 'm');
    f.savePerson(c, FamilyPerson(id: 'P1', companyId: c.id, name: 'خالد', relation: 'ابن', parentId: father.id, generation: 2, memberId: khalid.id));
    f.savePerson(c, FamilyPerson(id: 'P2', companyId: c.id, name: 'مريم', relation: 'بنت', parentId: father.id, generation: 2, memberId: maryam.id));

    expect(f.startSuccession(c, event: SuccessionEvent.death, subjectId: father.id, eventDate: clock, successorId: 'P1', by: 'a'), isNull);
    final x = f.successionsFor(c.id).single;
    expect(f.person(father.id)!.alive, isFalse);
    expect(f.submitSuccession(c, x, by: 'a'), contains('دليل'));
    f.addEvidence(c, x, 'شهادة وفاة رقم 123');
    expect(f.submitSuccession(c, x, by: 'a'), isNull);
    approveAll(f.decision(x.decisionRef!)!);
    expect(x.status, SuccessionStatus.effective);
    expect(f.equityAfterSuccession(c, x), isNull); // لا حصر وراثة معتمد بعد

    final deed = InheritanceDeed(
        id: 'D1', companyId: c.id, deceasedId: father.id, reference: 'ح/9', court: 'محكمة', date: clock, shares: {'P1': 50, 'P2': 50});
    f.submitDeed(c, deed, by: 'a');
    approveAll(f.decision(deed.decisionRef!)!);
    final (eq, missing) = f.equityAfterSuccession(c, x)!;
    expect(missing, isEmpty);
    expect(eq['m'], 0);
    expect(eq[khalid.id], 30);
    expect(eq[maryam.id], 30);
    expect(eq['a'], 40);

    final base = cs.currentContract(c.id)!;
    final v2 = cs.proposeCapTable(base, equity: eq, reason: 'خلافة', proposedBy: 'a', newPartners: [
      for (final mem in [khalid, maryam]) SessionPartner(id: mem.id, name: mem.name, nationalId: '', phone: mem.phone, equity: eq[mem.id]!),
    ]);
    expect(cs.signersOf(v2).map((p) => p.id), containsAll(['a', khalid.id, maryam.id]));
    for (final p in cs.signersOf(v2)) {
      cs.signOff(v2, PartnerSignOff(partnerId: p.id, signaturePng: 'sig', at: DateTime.now(), method: ConfirmMethod.manual));
    }
    cs.setWitnesses(v2, [const Witness(name: 'ش1', nationalId: '1', internal: false), const Witness(name: 'ش2', nationalId: '2', internal: false)]);
    cs.attestWitness(v2, 0, signature: 'w', method: ConfirmMethod.manual);
    cs.attestWitness(v2, 1, signature: 'w', method: ConfirmMethod.manual);
    cs.complete(v2);
    expect(c.partners.map((p) => p.name), containsAll(['خالد', 'مريم', 'أحمد']));
    expect(c.partners.firstWhere((p) => p.name == 'خالد').equity, 30);
    expect(c.equityTotal, 100);
  });
}
