// عرض شاشات الحوكمة العائلية (المرحلة 6) على الحاسب والجوال ببيانات حقيقية
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithaq_app/models/company.dart';
import 'package:mithaq_app/models/family.dart';
import 'package:mithaq_app/models/questionnaire.dart';
import 'package:mithaq_app/providers/company_state.dart';
import 'package:mithaq_app/providers/contract_state.dart';
import 'package:mithaq_app/providers/family_state.dart';
import 'package:mithaq_app/screens/family/constitution_screen.dart';
import 'package:mithaq_app/screens/family/distribution_succession_screens.dart';
import 'package:mithaq_app/screens/family/family_dashboard_screen.dart';
import 'package:mithaq_app/screens/family/family_decisions_screen.dart';
import 'package:mithaq_app/screens/family/family_tree_screen.dart';
import 'package:mithaq_app/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late CompanyState companies;
  late ContractState cs;
  late FamilyState f;
  late Company c;
  late FamilyDecision dec;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    companies = CompanyState();
    await companies.load();
    cs = ContractState();
    await cs.load();
    f = FamilyState()..auditSink = companies.log;
    await f.load();
    c = companies.createCompany(
      legalName: 'مؤسسة آل سالم التجارية العائلية',
      companyType: 'ذ.م.م',
      currency: AppCurrency.usd,
      capital: 100000,
      members: const [
        CompanyMember(id: 'm', name: 'سالم عبدالله الأب', phone: '771000001', equity: 60, roles: {CompanyRole.managingPartner}),
        CompanyMember(id: 'a', name: 'أحمد سالم', phone: '771000002', equity: 40, roles: {CompanyRole.partner}),
      ],
    );
    companies.setFamilyEnabled(c.id, true);
    f.seedFounders(c);
    final father = f.peopleFor(c.id).first;
    f.savePerson(c, FamilyPerson(id: 'P1', companyId: c.id, name: 'خالد سالم', relation: 'ابن', parentId: father.id, generation: 2));
    f.savePerson(c, FamilyPerson(id: 'P2', companyId: c.id, name: 'مريم سالم', relation: 'بنت', parentId: father.id, generation: 2));
    final d = f.startDraft(c, by: 'm');
    final k = f.submitConstitution(c, d, summary: 'الدستور الأول', by: 'm')!;
    f.vote(c, k, 'm', approve: true, method: 'manual', name: 'سالم');
    f.vote(c, k, 'a', approve: true, method: 'manual', name: 'أحمد');
    f.createDistribution(c, period: '2026', available: 12000, by: 'm');
    f.startSuccession(c, event: SuccessionEvent.resignation, subjectId: father.id, eventDate: DateTime.now(), successorId: 'P1', by: 'm');
    dec = f.openDecision(c, type: FamilyDecisionType.other, title: 'شراء مقر جديد للعائلة', by: 'm');
  });

  Future<void> pump(WidgetTester t, Widget screen, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: companies),
        ChangeNotifierProvider.value(value: cs),
        ChangeNotifierProvider.value(value: f),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Directionality(textDirection: TextDirection.rtl, child: screen),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
  }

  final screens = <String, Widget Function()>{
    'R09 لوحة العائلة': () => const FamilyDashboardScreen(),
    'R10 الدستور': () => const ConstitutionScreen(),
    'R11 العائلة والورثة': () => const FamilyTreeScreen(),
    'R12 التوزيع': () => const DistributionScreen(),
    'R13 الخلافة': () => const SuccessionScreen(),
    'R14 القرارات': () => const FamilyDecisionsScreen(),
  };
  for (final (size, label) in [(const Size(1280, 2600), 'الحاسب'), (const Size(390, 2600), 'الجوال')]) {
    for (final e in screens.entries) {
      testWidgets('${e.key} على $label', (t) async {
        await pump(t, e.value(), size);
        expect(find.byType(Scaffold), findsWidgets);
      });
    }
    testWidgets('R14 تفاصيل القرار على $label', (t) async {
      await pump(t, FamilyDecisionScreen(decisionId: dec.id), size);
      expect(find.text('موافق'), findsWidgets);
    });
  }

  testWidgets('بطاقة التفعيل تظهر للشريك المدير قبل التفعيل فقط', (t) async {
    companies.setFamilyEnabled(c.id, false);
    await pump(t, const Scaffold(body: FamilyEnableCard()), const Size(390, 800));
    expect(find.text('تفعيل'), findsOneWidget);
    companies.setFamilyEnabled(c.id, true);
    await t.pump();
    expect(find.text('تفعيل'), findsNothing);
  });
}
