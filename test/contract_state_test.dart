// اختبارات منطق محرك الاستبانة: النصاب المرجح، البنود الخاصة، التأجيل، الحفظ
import 'package:flutter_test/flutter_test.dart';
import 'package:mithaq_app/models/questionnaire.dart';
import 'package:mithaq_app/providers/contract_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ContractState state;
  late ContractSession s;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = ContractState();
    await state.load();
    s = state.createSession(
      companyName: 'شركة الاختبار',
      companyType: 'شركة ذات مسؤولية محدودة',
      currency: AppCurrency.usd,
      capital: 100000,
      partners: const [
        SessionPartner(id: 'a', name: 'أحمد', nationalId: '1', phone: '', equity: 60),
        SessionPartner(id: 'b', name: 'بكر', nationalId: '2', phone: '', equity: 30),
        SessionPartner(id: 'c', name: 'جمال', nationalId: '3', phone: '', equity: 10),
      ],
    );
  });

  ClauseRecord rec(String key) => s.records.firstWhere((r) => r.key == key);

  test('نص النصاب اللفظي يتحول إلى نسبة', () {
    expect(QuorumRule.parse('ثلثين').percent, 66.67);
    expect(QuorumRule.parse('إجماع').percent, 100);
    expect(QuorumRule.parse('75%').percent, 75);
  });

  test('البنود الخاصة تتكرر لكل شريك', () {
    expect(s.records.where((r) => r.questionId == 'P01').length, 3);
  });

  test('نصاب الثلثين مرجح بالحصص: 60% لا يكفي و70% يكفي', () {
    final r = rec('F02'); // ثلثين
    state.castVote(s, r, 'a', Ballot.agree, ConfirmMethod.manual);
    state.castVote(s, r, 'b', Ballot.disagree, ConfirmMethod.manual);
    expect(r.status, ClauseStatus.pending);
    state.castVote(s, r, 'c', Ballot.neutral, ConfirmMethod.manual);
    expect(r.status, ClauseStatus.rejected);

    state.revote(s, r);
    expect(r.round, 2);
    state.castVote(s, r, 'a', Ballot.agree, ConfirmMethod.manual);
    state.castVote(s, r, 'b', Ballot.disagree, ConfirmMethod.manual);
    state.castVote(s, r, 'c', Ballot.agree, ConfirmMethod.manual);
    expect(r.status, ClauseStatus.agreed);
  });

  test('البند الخاص يحسم بموافقة صاحبه فقط', () {
    final r = rec('P01:b');
    expect(state.voters(s, r).map((p) => p.id), ['b']);
    state.castVote(s, r, 'b', Ballot.agree, ConfirmMethod.manual);
    expect(r.status, ClauseStatus.agreed);
  });

  test('تغيير القيمة يلغي الأصوات السابقة', () {
    final r = rec('F02');
    state.castVote(s, r, 'a', Ballot.agree, ConfirmMethod.manual);
    state.setValue(s, r, 3000);
    expect(r.votes, isEmpty);
    expect(state.renderClause(s, r), contains('\$3,000'));
  });

  test('لا يكتمل العقد مع وجود بند مؤجل، والتحييد يحسمه', () {
    for (final r in s.records) {
      for (final p in state.voters(s, r)) {
        state.castVote(s, r, p.id, Ballot.agree, ConfirmMethod.manual);
      }
    }
    expect(s.allResolved, isTrue);
    state.defer(s, rec('L03'));
    expect(s.allResolved, isFalse);
    state.neutralize(s, rec('L03'));
    expect(s.allResolved, isTrue);
    expect(state.generatedRules(s), isNotEmpty);
  });

  test('بصمة العقد تثبت عند الاعتماد وتتغير بأي تعديل', () {
    for (final r in s.records) {
      for (final p in state.voters(s, r)) {
        state.castVote(s, r, p.id, Ballot.agree, ConfirmMethod.manual);
      }
    }
    state.complete(s);
    expect(s.contentHash, hasLength(64));
    expect(state.verifyHash(s), isTrue);

    // العبث بقيمة سقف الصرف بعد الاعتماد يكسر البصمة
    s.records.firstWhere((r) => r.key == 'F02').value = 999999;
    expect(state.verifyHash(s), isFalse);
  });

  test('الجلسة تُحفظ وتُستعاد بعد إعادة التحميل', () async {
    state.castVote(s, rec('L01'), 'a', Ballot.agree, ConfirmMethod.biometric);
    state.suspend(s);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final again = ContractState();
    await again.load();
    final restored = again.sessions.single;
    expect(restored.status, SessionStatus.suspended);
    expect(restored.records.firstWhere((r) => r.key == 'L01').votes['a']?.method,
        ConfirmMethod.biometric);
  });
}
