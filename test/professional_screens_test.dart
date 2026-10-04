// عرض شاشات الأطراف المهنية (المرحلة 5) على الحاسب والجوال: من منظور المحامي والمحاسب والشركاء
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithaq_app/models/company.dart';
import 'package:mithaq_app/models/professional.dart';
import 'package:mithaq_app/models/questionnaire.dart';
import 'package:mithaq_app/providers/company_state.dart';
import 'package:mithaq_app/providers/contract_state.dart';
import 'package:mithaq_app/providers/daily_ops_state.dart';
import 'package:mithaq_app/providers/dispute_state.dart';
import 'package:mithaq_app/providers/operations_state.dart';
import 'package:mithaq_app/providers/professional_state.dart';
import 'package:mithaq_app/screens/professional/accounting_review_screen.dart';
import 'package:mithaq_app/screens/professional/invitation_screen.dart';
import 'package:mithaq_app/screens/professional/legal_review_screen.dart';
import 'package:mithaq_app/screens/professional/pro_archive_screen.dart';
import 'package:mithaq_app/screens/professional/pro_comments_screen.dart';
import 'package:mithaq_app/screens/professional/pro_dashboard_screen.dart';
import 'package:mithaq_app/screens/professional/professional_reviews_screen.dart';
import 'package:mithaq_app/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late CompanyState companies;
  late ContractState cs;
  late OperationsState ops;
  late DisputeState ds;
  late DailyOpsState daily;
  late ProfessionalState pro;
  late Company c;
  late Engagement lawyerE;
  late Engagement accE;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    companies = CompanyState();
    await companies.load();
    cs = ContractState()..auditSink = companies.log;
    await cs.load();
    ops = OperationsState();
    await ops.load();
    ds = DisputeState();
    await ds.load();
    daily = DailyOpsState();
    await daily.load();
    pro = ProfessionalState()..auditSink = companies.log;
    await pro.load();
    c = companies.createCompany(
      legalName: 'شركة سبأ للتجارة والاستثمار',
      companyType: 'ذ.م.م',
      currency: AppCurrency.usd,
      capital: 100000,
      members: const [
        CompanyMember(id: 'm', name: 'المدير العام', phone: '771000001', equity: 60, roles: {CompanyRole.managingPartner}),
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
    companies.inviteStaff(c.id, name: 'المحامي سعيد الحكيمي', phone: '771000020', role: CompanyRole.lawyer);
    companies.inviteStaff(c.id, name: 'المحاسب خالد', phone: '771000030', role: CompanyRole.accountant);
    final now = DateTime.now();
    for (final m in c.staffMembers) {
      pro.createEngagement(c, m,
          scope: m.roles.contains(CompanyRole.lawyer)
              ? {EngagementScope.contract, EngagementScope.disputes}
              : {EngagementScope.financialRules, EngagementScope.correspondence},
          start: now,
          end: now.add(const Duration(days: 90)),
          organization: 'مكتب الحكيمي للمحاماة والاستشارات',
          byName: 'المدير',
          byId: 'm');
    }
    lawyerE = pro.engagementOf(c.id, c.staffMembers.first.id)!;
    accE = pro.engagementOf(c.id, c.staffMembers.last.id)!;
    pro.respond(c, accE, accept: true);
    pro.respond(c, lawyerE, accept: true);
    pro.addComment(
        c,
        lawyerE,
        ProComment(
          id: 'PC1',
          companyId: c.id,
          engagementId: lawyerE.id,
          authorId: lawyerE.memberId,
          authorName: lawyerE.name,
          authorRole: ProRole.lawyer,
          targetType: 'clause',
          targetId: s.records.first.key,
          targetLabel: 'البند الأول من عقد التأسيس',
          sessionId: s.id,
          version: 1,
          kind: CommentKind.changeRequest,
          category: kLegalCategories.first,
          severity: Severity3.high,
          text: 'الصياغة تحتمل أكثر من تفسير ويجب تحديد المدة بوضوح',
          createdAt: now,
          dueDate: now.add(const Duration(days: 7)),
        ));
  });

  Future<void> pump(WidgetTester t, Widget screen, Size size, {String? asPhone}) async {
    companies.myPhone = asPhone;
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: companies),
        ChangeNotifierProvider.value(value: cs),
        ChangeNotifierProvider.value(value: ops),
        ChangeNotifierProvider.value(value: ds),
        ChangeNotifierProvider.value(value: daily),
        ChangeNotifierProvider.value(value: pro),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Directionality(textDirection: TextDirection.rtl, child: screen),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
  }

  const lawyerPhone = '+967771000020';
  const accPhone = '+967771000030';
  final screens = <String, (Widget Function(), String?)>{
    'R02 لوحة المحامي': (() => const ProDashboardScreen(), lawyerPhone),
    'R03 ملف التكليف': (() => const EngagementScreen(), lawyerPhone),
    'R04 المراجعة القانونية': (() => const LegalReviewScreen(), lawyerPhone),
    'R05 المراجعة المحاسبية': (() => const AccountingReviewScreen(), accPhone),
    'R06 تعليقات المحامي': (() => const ProCommentsScreen(), lawyerPhone),
    'R06 تعليقات من جهة الشريك': (() => const ProCommentsScreen(), null),
    'R08 أرشيف المحاسب': (() => const ProArchiveScreen(), accPhone),
    'المراجعات المهنية للشركاء': (() => const ProfessionalReviewsScreen(), null),
  };
  for (final (size, label) in [(const Size(1280, 2600), 'الحاسب'), (const Size(390, 2600), 'الجوال')]) {
    for (final e in screens.entries) {
      testWidgets('${e.key} على $label', (t) async {
        await pump(t, e.value.$1(), size, asPhone: e.value.$2);
        expect(find.byType(Scaffold), findsWidgets);
      });
    }
  }

  testWidgets('R01 الدعوة المعلّقة تظهر قبل أي وحدة، والمحامي لا يرى زر التكليف', (t) async {
    lawyerE.status = EngagementStatus.pending;
    await pump(t, const ProfessionalGate(child: Text('محتوى')), const Size(390, 2600), asPhone: lawyerPhone);
    expect(find.text('قبول التكليف'), findsOneWidget);
    expect(find.text('محتوى'), findsNothing);
  });

  testWidgets('الشريك يرى طلب التعديل وزر فتح مقترح التعديل', (t) async {
    await pump(t, const ProCommentsScreen(), const Size(1280, 2600));
    await t.tap(find.textContaining('طلب تعديل: البند الأول'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('فتح مقترح تعديل'), findsOneWidget);
  });
}
