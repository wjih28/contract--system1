// اختبارات المرحلة 5: التكليف وقبوله، النطاق والمدة، التعليقات والردود، المراجعات، وإنهاء التكليف بموافقة الشركاء
import 'package:flutter_test/flutter_test.dart';
import 'package:mithaq_app/models/admin.dart';
import 'package:mithaq_app/models/company.dart';
import 'package:mithaq_app/models/professional.dart';
import 'package:mithaq_app/models/questionnaire.dart';
import 'package:mithaq_app/providers/company_state.dart';
import 'package:mithaq_app/providers/contract_state.dart';
import 'package:mithaq_app/providers/professional_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late CompanyState companies;
  late ContractState cs;
  late ProfessionalState pro;
  late Company c;
  late ContractSession s;
  late CompanyMember lawyer;
  var clock = DateTime(2026, 10, 4, 10);
  final notes = <String>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime(2026, 10, 4, 10);
    notes.clear();
    companies = CompanyState();
    await companies.load();
    cs = ContractState()..auditSink = companies.log;
    await cs.load();
    pro = ProfessionalState()
      ..auditSink = companies.log
      ..now = (() => clock)
      ..notifier = ((c, subject, id) => notes.add(subject))
      ..onAccessEnded = ((cid, mid) => companies.updateStaff(cid, mid, status: MemberStatus.suspended));
    await pro.load();
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
    s = cs.createSession(
      companyId: c.id,
      companyName: c.legalName,
      companyType: c.companyType,
      currency: c.currency,
      capital: c.capital,
      partners: c.partners.map((m) => m.toSessionPartner()).toList(),
    );
    companies.inviteStaff(c.id, name: 'المحامي سعيد', phone: '771000020', role: CompanyRole.lawyer);
    lawyer = c.staffMembers.single;
  });

  Engagement appoint({Set<EngagementScope> scope = const {EngagementScope.contract}}) {
    expect(
        pro.createEngagement(c, lawyer,
            scope: scope, start: clock, end: clock.add(const Duration(days: 90)), byName: 'المدير', byId: 'm'),
        isNull);
    return pro.engagementOf(c.id, lawyer.id)!;
  }

  ProComment comment(Engagement e, {CommentKind kind = CommentKind.comment}) => ProComment(
        id: 'PC${DateTime.now().microsecondsSinceEpoch}',
        companyId: c.id,
        engagementId: e.id,
        authorId: lawyer.id,
        authorName: lawyer.name,
        authorRole: ProRole.lawyer,
        targetType: 'clause',
        targetId: s.records.first.key,
        targetLabel: 'البند الأول',
        sessionId: s.id,
        version: s.version,
        kind: kind,
        category: kLegalCategories.first,
        text: 'الصياغة تحتمل أكثر من تفسير',
        createdAt: clock,
      );

  test('R01/R03: التكليف ينتظر القبول، ويُشعر الشركاء، ومعرّفه رقم الجوال', () {
    final e = appoint();
    expect(e.id, '+967771000020');
    expect(e.status, EngagementStatus.pending);
    expect(notes.single, contains('المحامي سعيد'));
    expect(pro.inScope(e, EngagementScope.contract), isFalse); // قبل القبول
    pro.respond(c, e, accept: true);
    expect(pro.inScope(e, EngagementScope.contract), isTrue);
    expect(pro.inScope(e, EngagementScope.financialRules), isFalse); // خارج النطاق
    expect(pro.createEngagement(c, lawyer, scope: {EngagementScope.contract}, start: clock, end: clock.add(const Duration(days: 1)), byName: '', byId: ''),
        contains('قائم'));
  });

  test('الاعتذار يُسجَّل ويوقف الوصول، وانتهاء المدة يغلق النطاق', () {
    final e = appoint();
    pro.respond(c, e, accept: false, reason: 'تعارض مصالح');
    expect(e.status, EngagementStatus.declined);
    expect(c.memberByPhone('+967771000020'), isNull);

    companies.updateStaff(c.id, lawyer.id, status: MemberStatus.active);
    final e2 = appoint();
    pro.respond(c, e2, accept: true);
    clock = clock.add(const Duration(days: 91));
    expect(e2.statusAt(clock), EngagementStatus.expired);
    expect(pro.inScope(e2, EngagementScope.contract), isFalse);
    expect(pro.addComment(c, e2, comment(e2)), contains('غير سارٍ'));
  });

  test('R04/R06: التعليق لا يغيّر النص، والردود تقلب الحالة، وطلب التعديل يُشعر الشركاء', () {
    final e = appoint();
    pro.respond(c, e, accept: true);
    final before = cs.renderClause(s, s.records.first);
    final x = comment(e, kind: CommentKind.changeRequest);
    expect(pro.addComment(c, e, x), isNull);
    expect(cs.renderClause(s, s.records.first), before);
    expect(notes.last, contains('يطلب تعديل'));
    pro.reply(c, x, authorId: 'a', authorName: 'أحمد', professional: false, text: 'سنعدّل الصياغة');
    expect(x.status, CommentStatus.awaitingResponse);
    pro.reply(c, x, authorId: lawyer.id, authorName: lawyer.name, professional: true, text: 'شكراً');
    expect(x.status, CommentStatus.open);
    pro.setCommentStatus(c, x, CommentStatus.resolved, byName: 'أحمد');
    expect(x.status.isOpen, isFalse);
    pro.setCommentStatus(c, x, CommentStatus.reopened, byName: lawyer.name);
    expect(x.status, CommentStatus.reopened);
  });

  test('R04: إكمال المراجعة يتطلب وسم كل البنود، والمكتملة لا تتغير', () {
    final e = appoint();
    pro.respond(c, e, accept: true);
    final r = pro.startReview(c, e, s);
    final keys = s.records.map((x) => x.key).toList();
    expect(pro.completeReview(c, r, keys, summary: 'سليم', byName: lawyer.name), contains('لم تُوسم'));
    for (final k in keys) {
      pro.toggleReviewed(c, r, k);
    }
    expect(pro.completeReview(c, r, keys, summary: 'سليم', byName: lawyer.name), isNull);
    expect(r.status, ReviewStatus.completed);
    pro.toggleReviewed(c, r, keys.first);
    expect(r.reviewedKeys, contains(keys.first));
  });

  test('R05: المراجعة المحاسبية تتطلب قائمة التحقق كاملة', () {
    companies.inviteStaff(c.id, name: 'المحاسب', phone: '771000030', role: CompanyRole.accountant);
    final acc = c.staffMembers.firstWhere((m) => m.roles.contains(CompanyRole.accountant));
    pro.createEngagement(c, acc,
        scope: {EngagementScope.financialRules}, start: clock, end: clock.add(const Duration(days: 30)), byName: 'المدير', byId: 'm');
    final e = pro.engagementOf(c.id, acc.id)!;
    expect(e.role, ProRole.accountant);
    pro.respond(c, e, accept: true);
    final r = pro.startReview(c, e, s);
    pro.setMapping(c, r, 'ضيافة', '5203 مصروفات ضيافة');
    expect(pro.completeReview(c, r, const [], summary: 'x', byName: 'المحاسب'), contains('قائمة التحقق'));
    for (final i in kAccountingChecklist) {
      pro.setChecklist(c, r, i, true);
    }
    expect(pro.completeReview(c, r, const [], summary: 'x', byName: 'المحاسب'), isNull);
    expect(r.accountMapping['ضيافة'], startsWith('5203'));
  });

  test('إنهاء التكليف بعد بدء العمل يحتاج موافقة شركاء بأكثر من نصف الحصص', () {
    final e = appoint();
    pro.respond(c, e, accept: true);
    pro.addComment(c, e, comment(e));
    pro.requestTermination(c, e, reason: 'انتهى الغرض', byId: 'm', byName: 'المدير');
    expect(e.status, EngagementStatus.active);
    pro.approveTermination(c, e, c.members.firstWhere((m) => m.id == 'a'), method: 'manual'); // 40%
    expect(e.status, EngagementStatus.active);
    pro.approveTermination(c, e, c.members.firstWhere((m) => m.id == 'm'), method: 'manual'); // 100%
    expect(e.status, EngagementStatus.terminated);
    expect(c.memberByPhone('+967771000020'), isNull);
  });

  test('إلغاء التكليف قبل بدء العمل فوري، والصلاحيات تمنع المحامي من التصويت', () {
    final e = appoint();
    pro.requestTermination(c, e, reason: 'خطأ في الاختيار', byId: 'm', byName: 'المدير');
    expect(e.status, EngagementStatus.terminated);
    expect(Permissions.effectiveModules({CompanyRole.lawyer}, c), isNot(contains(AppModule.voting)));
    expect(Permissions.effectiveModules({CompanyRole.lawyer}, c), contains(AppModule.legalReview));
  });
}
