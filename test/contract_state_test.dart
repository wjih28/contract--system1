// اختبارات منطق محرك الاستبانة: النصاب المرجح، البنود الخاصة، التأجيل، الحفظ
import 'package:flutter_test/flutter_test.dart';
import 'package:mithaq_app/models/questionnaire.dart';
import 'package:mithaq_app/providers/contract_state.dart';
import 'package:mithaq_app/services/phone.dart';
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
        SessionPartner(id: 'a', name: 'أحمد', nationalId: '1', phone: '771000001', equity: 60),
        SessionPartner(id: 'b', name: 'بكر', nationalId: '2', phone: '771000002', equity: 30),
        SessionPartner(id: 'c', name: 'جمال', nationalId: '3', phone: '771000003', equity: 10),
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

  test('وضع الخادم: حالة البند تُشتق من أصوات الجولة الحالية فقط', () {
    final doc = state.sessionToRemote(s, uid: 'u1');
    expect(doc['memberPhones'], hasLength(3));
    // جولة ثانية على F02: الأصوات القديمة من الجولة الأولى تُهمل
    (doc['records'] as Map)['F02']['round'] = 2;
    (doc['records'] as Map)['L03']['flag'] = 'deferred';
    Map<String, dynamic> v(String key, String pid, String ballot, int round) => {
          'recordKey': key,
          'partnerId': pid,
          'ballot': ballot,
          'round': round,
          'method': 'biometric',
          'at': '2026-09-29T10:00:00Z',
        };
    final votes = [
      v('F02', 'a', 'disagree', 1),
      v('F02', 'a', 'agree', 2),
      v('F02', 'b', 'agree', 2),
      v('F02', 'c', 'neutral', 2),
      v('L01', 'a', 'agree', 1),
      v(ContractState.neutralKey('L02'), 'b', 'agree', 1),
    ];
    final r = state.sessionFromRemote('X', doc, votes, const []);
    ClauseRecord rec(String k) => r.records.firstWhere((x) => x.key == k);
    expect(rec('F02').status, ClauseStatus.agreed); // 90% ≥ الثلثين
    expect(rec('F02').votes['a']?.ballot, Ballot.agree);
    expect(rec('L01').status, ClauseStatus.pending); // صوت واحد من ثلاثة
    expect(rec('L03').status, ClauseStatus.deferred);
    expect(rec('L02').neutralConsents, {'b'});
    expect(r.records.map((x) => x.key).first, 'L00'); // ترتيب البنود محفوظ (الأغراض أولاً)
  });

  test('توحيد أرقام الجوال اليمنية', () {
    expect(normalizePhone('0771 234 567'), '+967771234567');
    expect(normalizePhone('00967771234567'), '+967771234567');
    expect(normalizePhone('+966 50 123 4567'), '+966501234567');
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
