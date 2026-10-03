// اختبارات منطق القرار في المرحلة 1: المهلة، النصاب، الجمود، ربط التوقيع بالمسودة، الشهود
import 'package:flutter_test/flutter_test.dart';
import 'package:mithaq_app/models/questionnaire.dart';
import 'package:mithaq_app/providers/contract_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ContractState st;
  late ContractSession s;
  var clock = DateTime(2026, 10, 1, 9);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime(2026, 10, 1, 9);
    st = ContractState()..now = () => clock;
    await st.load();
    s = st.createSession(
      companyName: 'شركة',
      companyType: 'ذات مسؤولية محدودة',
      currency: AppCurrency.usd,
      capital: 1000,
      settings: const VotingSettings(quorum: 50, deadlineDays: 3, deadlockAfter: 2),
      partners: const [
        SessionPartner(id: 'a', name: 'أ', nationalId: '', phone: '', equity: 40),
        SessionPartner(id: 'b', name: 'ب', nationalId: '', phone: '', equity: 35),
        SessionPartner(id: 'c', name: 'ج', nationalId: '', phone: '', equity: 25),
      ],
    );
  });

  ClauseRecord rec(String k) => s.records.firstWhere((r) => r.key == k);

  test('أول صوت يبدأ المهلة، والبند يبقى معلقاً قبل انتهائها', () {
    final r = rec('F02'); // عتبة الثلثين
    st.castVote(s, r, 'a', Ballot.agree, ConfirmMethod.manual);
    expect(r.openedAt, clock);
    expect(st.quorum(s, r).deadline, clock.add(const Duration(days: 3)));
    expect(r.status, ClauseStatus.pending);
  });

  test('بعد المهلة: مشاركة أقل من النصاب = تعذّر النصاب، وليست موافقة', () {
    final r = rec('F02');
    st.castVote(s, r, 'a', Ballot.agree, ConfirmMethod.manual); // 40% فقط شاركت
    clock = clock.add(const Duration(days: 4));
    expect(st.refreshDeadlines(), isTrue);
    expect(r.status, ClauseStatus.quorumFailed);
  });

  test('بعد المهلة مع نصاب مكتمل: عدم التصويت لا يُحتسب موافقة', () {
    final r = rec('F02'); // العتبة 66.67% من إجمالي الحصص
    st.castVote(s, r, 'a', Ballot.agree, ConfirmMethod.manual);
    st.castVote(s, r, 'b', Ballot.agree, ConfirmMethod.manual); // 75% مشاركة و75% موافقة
    clock = clock.add(const Duration(days: 4));
    st.refreshDeadlines();
    expect(r.status, ClauseStatus.agreed);

    final r2 = rec('F03');
    st.castVote(s, r2, 'b', Ballot.agree, ConfirmMethod.manual);
    st.castVote(s, r2, 'c', Ballot.agree, ConfirmMethod.manual); // 60% موافقة < الثلثين
    clock = clock.add(const Duration(days: 4));
    st.refreshDeadlines();
    expect(r2.status, ClauseStatus.rejected);
  });

  test('فشل متكرر = جمود', () {
    final r = rec('F02');
    for (final p in ['a', 'b', 'c']) {
      st.castVote(s, r, p, p == 'a' ? Ballot.agree : Ballot.disagree, ConfirmMethod.manual);
    }
    expect(r.status, ClauseStatus.rejected);
    st.revote(s, r);
    expect(r.failures, 1);
    for (final p in ['a', 'b', 'c']) {
      st.castVote(s, r, p, Ballot.disagree, ConfirmMethod.manual);
    }
    expect(r.status, ClauseStatus.deadlock);
  });

  test('التوقيع مرتبط بالمسودة: أي تعديل بعده يبطله', () {
    for (final r in s.records) {
      for (final p in st.voters(s, r)) {
        st.castVote(s, r, p.id, Ballot.agree, ConfirmMethod.manual);
      }
    }
    expect(st.signingBlockers(s), isEmpty);
    st.signOff(s, PartnerSignOff(partnerId: 'a', signaturePng: 'x', at: clock, method: ConfirmMethod.manual));
    expect(st.signOffValid(s, s.signOffs['a']!), isTrue);

    st.reopen(s, rec('L02')); // تغيّرت المسودة
    expect(st.signOffValid(s, s.signOffs['a']!), isFalse);
    expect(st.signingBlockers(s), isNotEmpty);
  });

  test('الشاهد يشهد على الإصدار الحالي، ويحتاج الاعتماد شاهدين صالحين', () {
    for (final r in s.records) {
      for (final p in st.voters(s, r)) {
        st.castVote(s, r, p.id, Ballot.agree, ConfirmMethod.manual);
      }
    }
    for (final id in ['a', 'b', 'c']) {
      st.signOff(s, PartnerSignOff(partnerId: id, signaturePng: 's', at: clock, method: ConfirmMethod.manual));
    }
    st.setWitnesses(s, const [
      Witness(name: 'ش1', nationalId: '1', internal: false, phone: '+967700000001'),
      Witness(name: 'ش2', nationalId: '2', internal: true, phone: '+967700000002'),
    ]);
    expect(st.finalizeBlockers(s).single, contains('الشهود: 0 من 2'));
    st.attestWitness(s, 0, signature: 'w', method: ConfirmMethod.biometric);
    st.attestWitness(s, 1, signature: 'w', method: ConfirmMethod.biometric);
    expect(st.finalizeBlockers(s), isEmpty);
  });

  test('الملاحظات تُحفظ على البند ولا تغيّر الأصوات', () {
    final r = rec('L01');
    st.castVote(s, r, 'a', Ballot.agree, ConfirmMethod.manual);
    st.addNote(s, r, 'نقترح مراجعة الصياغة', author: 'أ');
    expect(r.notes.single.text, 'نقترح مراجعة الصياغة');
    expect(r.votes, hasLength(1));
  });
}
