// اختبارات المحتوى القانوني اليمني: شروط الأشكال القانونية، البنود الجوهرية، النصاب المشدد والإجماع،
// تعارض المصالح، وعرض شاشتي التأسيس والامتثال
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithaq_app/data/yemen_law.dart';
import 'package:mithaq_app/models/company.dart';
import 'package:mithaq_app/models/operations.dart';
import 'package:mithaq_app/models/questionnaire.dart';
import 'package:mithaq_app/providers/app_state.dart';
import 'package:mithaq_app/providers/company_state.dart';
import 'package:mithaq_app/providers/contract_state.dart';
import 'package:mithaq_app/providers/operations_state.dart';
import 'package:mithaq_app/screens/company/compliance_screen.dart';
import 'package:mithaq_app/screens/contract/new_session_screen.dart';
import 'package:mithaq_app/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('شروط الأشكال القانونية', () {
    test('الأشكال السبعة موجودة، والمحاصة بلا شخصية اعتبارية', () {
      expect(kCompanyForms, hasLength(7));
      expect(formSpec(CompanyForm.jointVenture).legalPersonality, isFalse);
      expect(formSpecOf('شركة تضامن').form, CompanyForm.generalPartnership);
      expect(formSpecOf('غير معروف').form, CompanyForm.llc); // الشركات القديمة
    });

    List<String> v(CompanyForm f,
            {int partners = 2, int g = 2, int l = 0, int nonYemeni = 0, int minor = 0, double capital = 10000, double? rate}) =>
        formViolations(formSpec(f),
            partners: partners,
            generalPartners: g,
            limitedPartners: l,
            nonYemeniGeneral: nonYemeni,
            minorGeneral: minor,
            capital: capital,
            yerRate: rate);

    test('ذات المسؤولية المحدودة: 2–30 شريكاً وحد أدنى 3 ملايين ريال', () {
      expect(v(CompanyForm.llc), isEmpty);
      expect(v(CompanyForm.llc, partners: 31).single, contains('30'));
      expect(v(CompanyForm.llc, capital: 5000, rate: 530).single, contains('3000000'));
      expect(v(CompanyForm.llc, capital: 6000, rate: 530), isEmpty);
    });

    test('المساهمة: 5 مؤسسين على الأقل، والعامة 50 مليوناً', () {
      expect(v(CompanyForm.closedJointStock, partners: 3, capital: 1e9, rate: 1).single, contains('5'));
      expect(v(CompanyForm.publicJointStock, partners: 5, capital: 20000000, rate: 1).single, contains('50000000'));
    });

    test('التوصية: متضامن وموصٍ على الأقل، والمتضامن يمني بالغ', () {
      expect(v(CompanyForm.limitedPartnership, g: 2, l: 0).single, contains('موصياً'));
      expect(v(CompanyForm.limitedPartnership, g: 1, l: 1), isEmpty);
      expect(v(CompanyForm.generalPartnership, nonYemeni: 1).single, contains('يمني'));
      expect(v(CompanyForm.generalPartnership, minor: 1).single, contains('18'));
    });
  });

  group('قواعد الحسم في العقد', () {
    late CompanyState companies;
    late ContractState cs;
    late OperationsState ops;
    late Company c;
    late ContractSession s;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      companies = CompanyState();
      await companies.load();
      cs = ContractState();
      await cs.load();
      ops = OperationsState();
      await ops.load();
      c = companies.createCompany(
        legalName: 'شركة سبأ',
        companyType: 'شركة توصية بسيطة',
        currency: AppCurrency.usd,
        capital: 100000,
        purpose: 'تجارة المواد الغذائية',
        members: const [
          CompanyMember(id: 'm', name: 'المدير', phone: '771000001', equity: 60, roles: {CompanyRole.managingPartner}, partnerClass: 'general'),
          CompanyMember(id: 'a', name: 'أحمد', phone: '771000002', equity: 30, roles: {CompanyRole.partner}, partnerClass: 'limited'),
          CompanyMember(
              id: 'k',
              name: 'خالد',
              phone: '771000003',
              equity: 10,
              roles: {CompanyRole.partner},
              partnerClass: 'limited',
              guardianName: 'عمه سعيد',
              guardianshipRef: 'و/12'),
        ],
      );
      s = cs.createSession(
        companyId: c.id,
        companyName: c.legalName,
        companyType: c.companyType,
        currency: c.currency,
        capital: c.capital,
        partners: c.partners.map((m) => m.toSessionPartner()).toList(),
        purpose: c.purpose,
      );
    });

    test('بند الشكل القانوني يذكر الشكل المختار والأغراض في بندها، والولي محفوظ في الجلسة', () {
      final l01 = s.records.firstWhere((r) => r.questionId == 'L01');
      final l00 = s.records.firstWhere((r) => r.questionId == 'L00');
      expect(cs.renderClause(s, l01), contains('شركة توصية بسيطة'));
      expect(cs.renderClause(s, l01), contains('المحاكم التجارية'));
      expect(cs.renderClause(s, l00), contains('تجارة المواد الغذائية'));
      expect(s.partners.firstWhere((p) => p.id == 'k').guardianName, 'عمه سعيد');
      expect(Company.fromJson(c.toJson()).partners.firstWhere((p) => p.id == 'k').minor, isTrue);
    });

    test('البند الجوهري لا يُحيَّد، وتأجيله يمنع إصدار العقد', () {
      final f01 = s.records.firstWhere((r) => r.questionId == 'F01');
      expect(cs.canNeutralize(f01), isFalse);
      cs.neutralize(s, f01);
      expect(f01.status, isNot(ClauseStatus.neutralized));
      cs.defer(s, f01, reason: 'لاحقاً');
      expect(cs.signingBlockers(s).join(), contains('البند الجوهري'));
      final l03 = s.records.firstWhere((r) => r.questionId == 'L03');
      expect(cs.canNeutralize(l03), isTrue);
    });

    test('تعديل العقد يتطلب 75% على الأقل، وزيادة الأعباء تتطلب الإجماع', () {
      for (final r in s.records) {
        for (final p in cs.voters(s, r)) {
          cs.castVote(s, r, p.id, Ballot.agree, ConfirmMethod.manual);
        }
      }
      cs.complete(s);
      final v2 = cs.proposeAmendment(s, changes: {'F02': 5000}, reason: 'توسع', proposedBy: 'm');
      final r = v2.records.firstWhere((x) => x.amended);
      cs.castVote(v2, r, 'm', Ballot.agree, ConfirmMethod.manual); // 60%
      cs.castVote(v2, r, 'k', Ballot.agree, ConfirmMethod.manual); // 70%
      expect(cs.quorum(v2, r).required, greaterThanOrEqualTo(kSupermajority));
      expect(cs.quorum(v2, r).passed, isFalse);
      cs.withdrawAmendment(v2, reason: 'اختبار');
      final v3 = cs.proposeAmendment(s, changes: {'F02': 5000}, reason: 'زيادة حصص نقدية', proposedBy: 'm', burdenIncrease: true);
      expect(cs.quorum(v3, v3.records.firstWhere((x) => x.amended)).required, 100);
    });

    test('تعارض المصالح: المفصح يُستبعد من التصويت والوزن', () {
      for (final r in s.records) {
        for (final p in cs.voters(s, r)) {
          cs.castVote(s, r, p.id, Ballot.agree, ConfirmMethod.manual);
        }
      }
      cs.complete(s);
      final tx = ops.submit(
          cs,
          c,
          FinancialTx(
              id: 'T1',
              companyId: c.id,
              date: DateTime.now(),
              amount: 3500,
              currency: AppCurrency.usd,
              category: TxCategory.purchase,
              payee: 'مورد قريب لأحمد',
              purpose: 'شراء',
              createdBy: 'm',
              createdAt: DateTime.now()),
          actorName: 'المدير');
      final ex = ops.requestException(c, tx, tx.triggered.first, reason: 'ضرورة', requestedBy: 'm');
      final ahmed = c.members.firstWhere((m) => m.id == 'a');
      ops.declareConflict(c, ex, ahmed, note: 'المورد قريبه');
      expect(ops.eligibleVoters(c, ex).map((p) => p.id), ['k']);
      ops.voteException(c, ex, c.members.firstWhere((m) => m.id == 'k'), approve: true, method: 'manual');
      expect(ex.status, ExceptionStatus.approved);
      expect(ExceptionRequest.fromJson(ex.toJson()).conflicts, {'a'});
    });
  });

  group('الشاشات', () {
    late CompanyState companies;
    late ContractState cs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      companies = CompanyState();
      await companies.load();
      cs = ContractState();
      await cs.load();
      final c = companies.createCompany(
        legalName: 'شركة سبأ للتجارة',
        companyType: 'شركة ذات مسؤولية محدودة',
        currency: AppCurrency.usd,
        capital: 100000,
        purpose: 'التجارة العامة',
        yerRate: 530,
        members: const [
          CompanyMember(id: 'm', name: 'المدير', phone: '771000001', equity: 60, roles: {CompanyRole.managingPartner}),
          CompanyMember(id: 'a', name: 'أحمد', phone: '771000002', equity: 40, roles: {CompanyRole.partner}),
        ],
      );
      companies.setCompliance(c.id, 'bank', done: true, ref: 'شهادة 77');
    });

    Future<void> pump(WidgetTester t, Widget screen, Size size) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppState()),
          ChangeNotifierProvider.value(value: companies),
          ChangeNotifierProvider.value(value: cs),
        ],
        child: MaterialApp(theme: AppTheme.darkTheme, home: Directionality(textDirection: TextDirection.rtl, child: screen)),
      ));
      await t.pump(const Duration(milliseconds: 300));
    }

    for (final (size, label) in [(const Size(1280, 3200), 'الحاسب'), (const Size(390, 3200), 'الجوال')]) {
      testWidgets('الامتثال القانوني على $label', (t) async {
        await pump(t, const ComplianceScreen(), size);
        expect(find.text('خطوات الشهر والاستيفاء القانوني'), findsOneWidget);
        expect(find.textContaining('شهادة 77'), findsOneWidget);
      });
      testWidgets('تأسيس شركة بالأشكال اليمنية على $label', (t) async {
        await pump(t, const NewSessionScreen(), size);
        expect(find.textContaining('الحد الأدنى لرأس المال'), findsWidgets);
        expect(find.text('أغراض الشركة (بند جوهري)'), findsOneWidget);
      });
    }
  });
}
