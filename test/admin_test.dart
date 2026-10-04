// اختبارات المرحلة 4 (الإدارة): الصلاحيات القابلة للتعديل مع حقوق الشريك المقفلة، دعوة الموظفين،
// نقاط الإفصاح وموافقة الشريك، إعدادات المنصة، ومراقبة الأمان
import 'package:flutter_test/flutter_test.dart';
import 'package:mithaq_app/models/admin.dart';
import 'package:mithaq_app/models/company.dart';
import 'package:mithaq_app/models/dispute.dart';
import 'package:mithaq_app/models/questionnaire.dart';
import 'package:mithaq_app/providers/company_state.dart';
import 'package:mithaq_app/providers/dispute_state.dart';
import 'package:mithaq_app/services/security_monitor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late CompanyState cs;
  late Company c;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cs = CompanyState();
    await cs.load();
    c = cs.createCompany(
      legalName: 'شركة سبأ',
      companyType: 'ذ.م.م',
      currency: AppCurrency.usd,
      capital: 100000,
      members: const [
        CompanyMember(id: 'm', name: 'المدير', phone: '771000001', equity: 60, roles: {CompanyRole.managingPartner}),
        CompanyMember(id: 'a', name: 'أحمد', phone: '771000002', equity: 40, roles: {CompanyRole.partner}),
      ],
    );
  });

  group('الصلاحيات (A04)', () {
    test('الافتراضي يطابق الأدوار، وصلاحيات الشركاء يحددها العقد ولا تُعدَّل من الإدارة', () {
      expect(Permissions.actionsFor(CompanyRole.partner, AppModule.voting, c), contains(PermAction.approve));
      final before = Permissions.effectiveModules({CompanyRole.partner}, c);
      final logs = cs.audit.length;
      cs.savePermissions(c.id, CompanyRole.partner, {AppModule.voting: {}, AppModule.transactions: {}});
      cs.savePermissions(c.id, CompanyRole.managingPartner, {AppModule.voting: {}});
      expect(Permissions.actionsFor(CompanyRole.partner, AppModule.voting, c),
          containsAll([PermAction.view, PermAction.respond, PermAction.approve]));
      expect(Permissions.effectiveModules({CompanyRole.partner}, c), before);
      expect(c.permissions.containsKey('partner'), isFalse);
      expect(c.permissions.containsKey('managingPartner'), isFalse);
      expect(cs.audit.length, logs);
    });

    test('نقاط الإفصاح لا تُضبط لأدوار الشركاء من الإدارة', () {
      final p = ControlPoint.catalog.first;
      cs.saveControlPoint(c.id, p.id, CompanyRole.partner, {});
      expect(c.controlPoints[p.id]?.containsKey('partner') ?? false, isFalse);
    });

    test('إضافة وحدة لدور، ثم استعادة الافتراضي', () {
      cs.savePermissions(c.id, CompanyRole.accountant, {AppModule.auditLog: {PermAction.view, PermAction.print}});
      expect(Permissions.effectiveModules({CompanyRole.accountant}, c), contains(AppModule.auditLog));
      cs.resetPermissions(c.id, CompanyRole.accountant);
      expect(Permissions.effectiveModules({CompanyRole.accountant}, c), isNot(contains(AppModule.auditLog)));
    });

    test('مسؤول النظام لا يستطيع إقفال ضبط الصلاحيات على نفسه', () {
      cs.savePermissions(c.id, CompanyRole.systemAdmin, {AppModule.roles: {}});
      expect(Permissions.actionsFor(CompanyRole.systemAdmin, AppModule.roles, c), contains(PermAction.configure));
    });
  });

  group('المستخدمون (A03)', () {
    test('دعوة موظف بلا حصص لا تغيّر الشركاء ولا مجموع الحصص', () {
      expect(cs.inviteStaff(c.id, name: 'سالم', phone: '771000009', role: CompanyRole.executiveManager), isNull);
      expect(c.partners, hasLength(2));
      expect(c.equityTotal, 100);
      final s = c.staffMembers.single;
      expect(s.equity, 0);
      expect(s.phone, '+967771000009');
      expect(c.toJson()['memberPhones'], contains('+967771000009'));
      expect(c.toJson()['partnerPhones'], isNot(contains('+967771000009')));
      expect(Company.fromJson(c.toJson()).staffMembers.single.roles, {CompanyRole.executiveManager});
    });

    test('لا تُمنح صفة الشريك بالدعوة، ولا يتكرر الرقم', () {
      expect(cs.inviteStaff(c.id, name: 'س', phone: '771000009', role: CompanyRole.partner), isNotNull);
      expect(cs.inviteStaff(c.id, name: 'س', phone: '771000002', role: CompanyRole.accountant), contains('عضو'));
    });

    test('إيقاف الموظف يسحب وصوله فوراً، والشريك لا يُوقَف من الإدارة', () {
      cs.inviteStaff(c.id, name: 'سالم', phone: '771000009', role: CompanyRole.financialManager);
      final s = c.staffMembers.single;
      expect(cs.updateStaff(c.id, s.id, status: MemberStatus.suspended), isNull);
      expect(c.memberByPhone('+967771000009'), isNull);
      expect(c.toJson()['memberPhones'], isNot(contains('+967771000009')));
      expect(cs.updateStaff(c.id, 'a', status: MemberStatus.suspended), contains('الشريك'));
    });
  });

  group('نقاط الإفصاح وموافقة الشريك (A05)', () {
    test('إتاحة جوال الشريك لموظف لا تسري حتى يوافق كل الشركاء', () {
      cs.saveControlPoint(c.id, 'partner.phone', CompanyRole.executiveManager, {PermAction.view});
      expect(Permissions.pointActions({CompanyRole.executiveManager}, 'partner.phone', c), isEmpty);
      expect(cs.pendingConsents(c, 'm'), [('partner.phone', CompanyRole.executiveManager)]);

      cs.giveConsent(c.id, 'partner.phone', CompanyRole.executiveManager, 'm', method: 'manual');
      expect(Permissions.pointActions({CompanyRole.executiveManager}, 'partner.phone', c), isEmpty);
      cs.giveConsent(c.id, 'partner.phone', CompanyRole.executiveManager, 'a', method: 'manual');
      expect(Permissions.pointActions({CompanyRole.executiveManager}, 'partner.phone', c), {PermAction.view});
      expect(cs.pendingConsents(c, 'a'), isEmpty);
    });

    test('البيانات غير الشخصية تسري فوراً دون موافقة', () {
      cs.saveControlPoint(c.id, 'tx.details', CompanyRole.accountant, {PermAction.view});
      expect(Permissions.pointActions({CompanyRole.accountant}, 'tx.details', c), {PermAction.view});
    });
  });

  group('إعدادات المنصة (A21)', () {
    test('القيم خارج المسموح مرفوضة، والمحفوظ يسري على النزاعات الجديدة', () {
      expect(cs.setSetting(c.id, 'audit.retentionYears', 5), contains('10'));
      expect(cs.setSetting(c.id, 'dispute.negotiationDays', 10), isNull);
      expect(c.setting<int>('dispute.negotiationDays'), 10);
      final ds = DisputeState();
      final d = ds.open(c, trigger: DisputeTrigger.other, issue: 'خلاف', openedBy: 'a', openedByName: 'أحمد');
      expect(d.deadline.difference(d.openedAt).inDays, 10);
    });
  });

  group('مراقبة الأمان (A20)', () {
    test('تغيير الصلاحيات والإعدادات يظهر حدثاً أمنياً، والمعالجة تُحفظ', () {
      cs.savePermissions(c.id, CompanyRole.accountant, {AppModule.auditLog: {PermAction.view}});
      cs.setSetting(c.id, 'exception.deadlineDays', 5);
      final ev = SecurityMonitor.events(c, cs.audit, const []);
      expect(ev.map((e) => e.type), containsAll(['تغيير صلاحيات', 'تغيير إعداد']));
      cs.triageEvent(c.id, ev.first.id, TriageState.investigating, assignee: 'المدير');
      expect(Triage.fromJson(c.triage[ev.first.id]!).state, TriageState.investigating);
    });
  });

  group('فصل مسؤول النظام عن حقوق الشركاء', () {
    void actAsStaffAdmin() {
      expect(cs.inviteStaff(c.id, name: 'مسؤول', phone: '771000009', role: CompanyRole.systemAdmin), isNull);
      cs.myPhone = '+967771000009';
      expect(cs.me?.isPartner, isFalse);
    }

    test('المسؤول من غير الشركاء لا يغيّر النصاب ولا مهل الاستثناء والنزاعات', () {
      actAsStaffAdmin();
      expect(cs.canGovern, isFalse);
      final v = c.votingSettings;
      cs.updateVotingSettings(c.id, VotingSettings(quorum: 10, deadlineDays: 1, deadlockAfter: 1));
      expect(c.votingSettings.quorum, v.quorum);
      expect(cs.setSetting(c.id, 'dispute.negotiationDays', 20), CompanyState.governanceOnly);
      expect(cs.setSetting(c.id, 'exception.deadlineDays', 5), CompanyState.governanceOnly);
      // الإعدادات التشغيلية تبقى له
      expect(cs.setSetting(c.id, 'audit.retentionYears', 12), isNull);
    });

    test('الشريك يعدّل شروط الحوكمة', () {
      expect(cs.canGovern, isTrue);
      cs.updateVotingSettings(c.id, VotingSettings(quorum: 60, deadlineDays: 5, deadlockAfter: 3));
      expect(c.votingSettings.quorum, 60);
      expect(cs.setSetting(c.id, 'dispute.negotiationDays', 20), isNull);
    });

    test('المسؤول من غير الشركاء ليس ناخباً في الشركاء', () {
      actAsStaffAdmin();
      expect(c.partners.map((p) => p.id), isNot(contains(cs.me!.id)));
      expect(c.toJson()['partnerPhones'], isNot(contains('+967771000009')));
    });
  });
}
