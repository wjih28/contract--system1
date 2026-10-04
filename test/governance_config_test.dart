// اختبارات إعدادات الحوكمة: إصدارات البنود، القواعد، الأسئلة المشروطة، العملات
import 'package:flutter_test/flutter_test.dart';
import 'package:mithaq_app/models/governance_config.dart';
import 'package:mithaq_app/models/questionnaire.dart';
import 'package:mithaq_app/providers/contract_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ContractState st;

  ContractSession newSession() => st.createSession(
        companyName: 'ش',
        companyType: 'ذ.م.م',
        currency: AppCurrency.usd,
        capital: 1000,
        partners: const [
          SessionPartner(id: 'a', name: 'أ', nationalId: '', phone: '', equity: 60),
          SessionPartner(id: 'b', name: 'ب', nationalId: '', phone: '', equity: 40),
        ],
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    st = ContractState();
    await st.load();
  });

  test('المكتبة تُبذر من بنك الأسئلة، والبند والقاعدة كائنان منفصلان', () {
    expect(st.publishedClause('F02')?.version, 1);
    expect(st.publishedRule('F02')?.clauseId, 'CL-F02');
    expect(st.publishedRule('L01'), isNull); // بند نصي بلا قاعدة
  });

  test('تعديل البند ينشئ إصداراً جديداً ولا يغيّر الجلسات القائمة', () {
    final old = newSession();
    final r = old.records.firstWhere((x) => x.key == 'L03');
    final before = st.renderClause(old, r);

    st.saveClauseDraft('L03', title: 'حظر المنافسة', text: 'نص جديد لمدة {value} شهراً.');
    expect(st.latestClause('L03')?.status, ConfigStatus.draft);
    expect(st.publishedClause('L03')?.version, 1); // المسودة لا تُستخدم قبل النشر
    st.publishClause('L03');
    expect(st.publishedClause('L03')?.version, 2);

    expect(st.renderClause(old, r), before); // الجلسة القديمة تحتفظ بلقطتها
    final fresh = newSession();
    expect(st.renderClause(fresh, fresh.records.firstWhere((x) => x.key == 'L03')), startsWith('نص جديد'));
  });

  test('القاعدة لا تُنشر قبل التحقق', () {
    final cur = st.publishedRule('F02')!;
    st.saveRuleDraft(cur.copyWith(actions: []));
    expect(st.publishRule('F02'), contains('أضف إجراءً واحداً على الأقل'));
    st.saveRuleDraft(cur.copyWith(actions: ['تجميد', 'تنبيه الشركاء']));
    expect(st.publishRule('F02'), isEmpty);
    expect(st.publishedRule('F02')!.version, 2);
  });

  test('السؤال المشروط: غير منطبق إذا لم يتحقق شرطه، ويمنع الاعتماد الدائري', () {
    expect(st.setCondition('F03', const QuestionCondition(sourceQuestionId: 'F02', kind: ConditionKind.agreed)), isNull);
    expect(st.setCondition('F02', const QuestionCondition(sourceQuestionId: 'F03', kind: ConditionKind.agreed)),
        contains('دائري'));

    final s = newSession();
    final src = s.records.firstWhere((x) => x.key == 'F02');
    final dep = s.records.firstWhere((x) => x.key == 'F03');
    st.castVote(s, src, 'a', Ballot.disagree, ConfirmMethod.manual);
    st.castVote(s, src, 'b', Ballot.disagree, ConfirmMethod.manual);
    expect(src.status, ClauseStatus.rejected);
    expect(dep.status, ClauseStatus.notApplicable);

    st.revote(s, src); // يعود المصدر معلقاً فيعود البند المشروط للحسم
    expect(dep.status, ClauseStatus.pending);
  });

  test('تبقى عملة واحدة مفعّلة على الأقل', () {
    st.setCurrency(const CurrencySetting(currency: AppCurrency.yer, enabled: false));
    st.setCurrency(const CurrencySetting(currency: AppCurrency.sar, enabled: false));
    st.setCurrency(const CurrencySetting(currency: AppCurrency.usd, enabled: false));
    expect(st.enabledCurrencies, [AppCurrency.usd]);
  });
}
