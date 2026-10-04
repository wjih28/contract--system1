// اختبارات المرحلة 0: الصلاحيات حسب الدور، الشركة، سجل التدقيق، ربط الجلسات بالشركة
import 'package:flutter_test/flutter_test.dart';
import 'package:mithaq_app/models/company.dart';
import 'package:mithaq_app/models/questionnaire.dart';
import 'package:mithaq_app/providers/company_state.dart';
import 'package:mithaq_app/providers/contract_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('الصلاحيات: كل دور يرى وحدات بوابته فقط', () {
    final partner = Permissions.modulesFor({CompanyRole.partner});
    expect(partner, contains(AppModule.voting));
    expect(partner, isNot(contains(AppModule.questionBank)));

    final lawyer = Permissions.modulesFor({CompanyRole.lawyer});
    expect(lawyer, isNot(contains(AppModule.voting))); // الطرف المهني لا يملك حق التصويت
    expect(Permissions.portalsFor({CompanyRole.lawyer}), [Portal.professional]);

    // دوران من بوابتين: تظهر البوابتان بترتيب ثابت
    expect(Permissions.portalsFor({CompanyRole.systemAdmin, CompanyRole.partner}),
        [Portal.partner, Portal.admin]);
  });

  test('إنشاء شركة يسجّل حدث تدقيق، وإجراءات الجلسة تُسجَّل في سجل الشركة', () async {
    SharedPreferences.setMockInitialValues({});
    final companies = CompanyState();
    await companies.load();
    final contracts = ContractState()..auditSink = companies.log;
    await contracts.load();

    final c = companies.createCompany(
      legalName: 'شركة الاختبار',
      companyType: 'شركة ذات مسؤولية محدودة',
      currency: AppCurrency.usd,
      capital: 50000,
      members: const [
        CompanyMember(id: 'a', name: 'أحمد', phone: '771000001', equity: 70, roles: {CompanyRole.managingPartner}),
        CompanyMember(id: 'b', name: 'بكر', phone: '771000002', equity: 30, roles: {CompanyRole.partner}),
      ],
    );
    expect(c.members.first.phone, '+967771000001'); // توحيد الرقم
    expect(companies.current?.id, c.id);
    expect(companies.audit, hasLength(1));
    // محلياً: المستخدم هو أول عضو، ومنشئ الشركة يحصل على دور مسؤول النظام
    expect(companies.myRoles, {CompanyRole.managingPartner, CompanyRole.systemAdmin});
    expect(c.members[1].roles, {CompanyRole.partner});

    final s = contracts.createSession(
      companyId: c.id,
      companyName: c.legalName,
      companyType: c.companyType,
      currency: c.currency,
      capital: c.capital,
      partners: c.partners.map((m) => m.toSessionPartner()).toList(),
    );
    expect(contracts.sessionsFor(c.id), [s]);

    final r = s.records.first;
    contracts.castVote(s, r, 'a', Ballot.agree, ConfirmMethod.biometric);
    contracts.defer(s, s.records[1]);
    expect(companies.audit, hasLength(3));
    expect(companies.audit.first.action, contains('تأجيل'));
    expect(companies.audit[1].evidenceRef, contains('بصمة حيوية'));

    // يبقى السجل بعد إعادة التحميل
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final again = CompanyState();
    await again.load();
    expect(again.audit, hasLength(3));
  });
}
