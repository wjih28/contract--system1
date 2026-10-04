import 'package:flutter/material.dart';

import 'admin.dart';
import 'questionnaire.dart';

/// البوابات الأربع في المنصة
enum Portal { partner, admin, operations, professional, family }

extension PortalX on Portal {
  String get label => switch (this) {
        Portal.partner => 'بوابة الشركاء',
        Portal.admin => 'إدارة النظام',
        Portal.operations => 'التشغيل والحوكمة',
        Portal.professional => 'الأطراف المهنية',
        Portal.family => 'الحوكمة العائلية',
      };

  IconData get icon => switch (this) {
        Portal.partner => Icons.handshake_rounded,
        Portal.admin => Icons.admin_panel_settings_rounded,
        Portal.operations => Icons.business_center_rounded,
        Portal.professional => Icons.work_history_rounded,
        Portal.family => Icons.family_restroom_rounded,
      };
}

/// الأدوار داخل الشركة. الدور التقني لا يمنح سلطة تجارية بذاته.
enum CompanyRole {
  managingPartner,
  partner,
  executiveManager,
  financialManager,
  departmentManager,
  systemAdmin,
  legalAdmin,
  lawyer,
  accountant,
  witness,
  familyMember,
}

extension CompanyRoleX on CompanyRole {
  String get label => switch (this) {
        CompanyRole.managingPartner => 'الشريك المدير',
        CompanyRole.partner => 'شريك',
        CompanyRole.executiveManager => 'المدير التنفيذي',
        CompanyRole.financialManager => 'المدير المالي',
        CompanyRole.departmentManager => 'مدير قسم',
        CompanyRole.systemAdmin => 'مسؤول النظام',
        CompanyRole.legalAdmin => 'المسؤول القانوني',
        CompanyRole.lawyer => 'محامٍ',
        CompanyRole.accountant => 'محاسب',
        CompanyRole.witness => 'شاهد',
        CompanyRole.familyMember => 'فرد من العائلة',
      };

  Portal get portal => switch (this) {
        CompanyRole.managingPartner || CompanyRole.partner => Portal.partner,
        CompanyRole.systemAdmin || CompanyRole.legalAdmin => Portal.admin,
        CompanyRole.executiveManager ||
        CompanyRole.financialManager ||
        CompanyRole.departmentManager =>
          Portal.operations,
        CompanyRole.lawyer || CompanyRole.accountant || CompanyRole.witness => Portal.professional,
        CompanyRole.familyMember => Portal.family,
      };

  bool get isPartner => this == CompanyRole.managingPartner || this == CompanyRole.partner;
}

/// الوحدات التي تظهر في القائمة، وكل وحدة تتبع بوابة
enum AppModule {
  // بوابة الشركاء
  dashboard,
  partners,
  establishment,
  voting,
  versions,
  approvals,
  transactions,
  disputes,
  partnerReports,
  notifications,
  profile,
  // إدارة النظام
  adminDashboard,
  companies,
  users,
  roles,
  controlPoints,
  securityMonitor,
  platformSettings,
  questionBank,
  clauseLibrary,
  logicRules,
  votingSettings,
  currencySettings,
  auditLog,
  versionManager,
  // التشغيل
  operationsDashboard,
  opsTransactions,
  opsFrozen,
  opsViolations,
  opsExpenses,
  currentAccount,
  payroll,
  approvalCenter,
  decisionExecution,
  plans,
  correspondence,
  opsAlerts,
  opsReports,
  ruleTest,
  expenseLimits,
  channels,
  integrations,
  // الأطراف المهنية
  professionalTasks,
  engagement,
  legalReview,
  accountingReview,
  proComments,
  proArchive,
  // المراجعات المهنية من جهة الشركة (الشركاء ومسؤول النظام)
  professionalReviews,
  // الامتثال القانوني (القانون اليمني)
  compliance,
  // الحوكمة العائلية
  familyDashboard,
  familyConstitution,
  familyTree,
  familyDistribution,
  familySuccession,
  familyDecisions,
}

extension AppModuleX on AppModule {
  String get label => switch (this) {
        AppModule.dashboard => 'لوحة الشركة',
        AppModule.partners => 'الشركاء والحصص',
        AppModule.establishment => 'التأسيس والعقد',
        AppModule.voting => 'مركز التصويت',
        AppModule.versions => 'إصدارات العقد',
        AppModule.approvals => 'الموافقات والاستثناءات',
        AppModule.transactions => 'العمليات والمخالفات',
        AppModule.disputes => 'النزاعات',
        AppModule.partnerReports => 'التقارير',
        AppModule.notifications => 'الإشعارات',
        AppModule.profile => 'حسابي',
        AppModule.adminDashboard => 'لوحة الإدارة',
        AppModule.companies => 'إدارة الشركات',
        AppModule.users => 'مستخدمو النظام',
        AppModule.roles => 'الأدوار والصلاحيات',
        AppModule.controlPoints => 'نقاط الإفصاح',
        AppModule.securityMonitor => 'الأمان والتكامل',
        AppModule.platformSettings => 'إعدادات المنصة',
        AppModule.questionBank => 'بنك الأسئلة',
        AppModule.clauseLibrary => 'مكتبة البنود',
        AppModule.logicRules => 'القواعد المنطقية',
        AppModule.votingSettings => 'التصويت والنصاب',
        AppModule.currencySettings => 'العملات',
        AppModule.auditLog => 'سجل التدقيق',
        AppModule.versionManager => 'إدارة الإصدارات',
        AppModule.operationsDashboard => 'لوحة التشغيل',
        AppModule.opsTransactions => 'العمليات المالية',
        AppModule.opsFrozen => 'العمليات المجمّدة',
        AppModule.opsViolations => 'المخالفات',
        AppModule.opsExpenses => 'المصروفات والضيافة',
        AppModule.currentAccount => 'الحساب الجاري',
        AppModule.payroll => 'الرواتب',
        AppModule.approvalCenter => 'مركز الموافقات',
        AppModule.decisionExecution => 'تنفيذ القرارات',
        AppModule.plans => 'الخطط',
        AppModule.correspondence => 'المراسلات',
        AppModule.opsAlerts => 'التنبيهات',
        AppModule.opsReports => 'التقارير التشغيلية',
        AppModule.ruleTest => 'اختبار القواعد',
        AppModule.expenseLimits => 'حدود الصرف',
        AppModule.channels => 'القنوات والقوالب',
        AppModule.integrations => 'التكامل المحاسبي',
        AppModule.professionalTasks => 'مهامي المهنية',
        AppModule.engagement => 'ملف التكليف',
        AppModule.legalReview => 'المراجعة القانونية',
        AppModule.accountingReview => 'المراجعة المحاسبية',
        AppModule.proComments => 'التعليقات',
        AppModule.proArchive => 'أرشيف المستندات',
        AppModule.professionalReviews => 'المراجعات المهنية',
        AppModule.compliance => 'الامتثال القانوني',
        AppModule.familyDashboard => 'لوحة العائلة',
        AppModule.familyConstitution => 'الدستور العائلي',
        AppModule.familyTree => 'العائلة والورثة',
        AppModule.familyDistribution => 'توزيع الأرباح',
        AppModule.familySuccession => 'الخلافة',
        AppModule.familyDecisions => 'القرارات العائلية',
      };

  IconData get icon => switch (this) {
        AppModule.dashboard => Icons.space_dashboard_rounded,
        AppModule.partners => Icons.pie_chart_rounded,
        AppModule.establishment => Icons.history_edu_rounded,
        AppModule.voting => Icons.how_to_vote_rounded,
        AppModule.versions => Icons.layers_rounded,
        AppModule.approvals => Icons.fact_check_rounded,
        AppModule.transactions => Icons.receipt_long_rounded,
        AppModule.disputes => Icons.gavel_rounded,
        AppModule.partnerReports => Icons.summarize_rounded,
        AppModule.notifications => Icons.notifications_active_rounded,
        AppModule.profile => Icons.person_rounded,
        AppModule.adminDashboard => Icons.dashboard_customize_rounded,
        AppModule.companies => Icons.apartment_rounded,
        AppModule.users => Icons.group_rounded,
        AppModule.roles => Icons.admin_panel_settings_rounded,
        AppModule.controlPoints => Icons.policy_rounded,
        AppModule.securityMonitor => Icons.shield_rounded,
        AppModule.platformSettings => Icons.settings_rounded,
        AppModule.questionBank => Icons.library_books_rounded,
        AppModule.clauseLibrary => Icons.menu_book_rounded,
        AppModule.logicRules => Icons.account_tree_rounded,
        AppModule.votingSettings => Icons.tune_rounded,
        AppModule.currencySettings => Icons.currency_exchange_rounded,
        AppModule.auditLog => Icons.manage_search_rounded,
        AppModule.versionManager => Icons.account_tree_outlined,
        AppModule.operationsDashboard => Icons.insights_rounded,
        AppModule.opsTransactions => Icons.receipt_long_rounded,
        AppModule.opsFrozen => Icons.ac_unit_rounded,
        AppModule.opsViolations => Icons.gpp_bad_rounded,
        AppModule.opsExpenses => Icons.local_cafe_rounded,
        AppModule.currentAccount => Icons.account_balance_wallet_rounded,
        AppModule.payroll => Icons.payments_rounded,
        AppModule.approvalCenter => Icons.approval_rounded,
        AppModule.decisionExecution => Icons.task_alt_rounded,
        AppModule.plans => Icons.event_note_rounded,
        AppModule.correspondence => Icons.mail_rounded,
        AppModule.opsAlerts => Icons.notification_important_rounded,
        AppModule.opsReports => Icons.summarize_rounded,
        AppModule.ruleTest => Icons.science_rounded,
        AppModule.expenseLimits => Icons.speed_rounded,
        AppModule.channels => Icons.campaign_rounded,
        AppModule.integrations => Icons.sync_alt_rounded,
        AppModule.professionalTasks => Icons.assignment_rounded,
        AppModule.engagement => Icons.badge_rounded,
        AppModule.legalReview => Icons.balance_rounded,
        AppModule.accountingReview => Icons.calculate_rounded,
        AppModule.proComments => Icons.forum_rounded,
        AppModule.proArchive => Icons.inventory_2_rounded,
        AppModule.professionalReviews => Icons.rate_review_rounded,
        AppModule.compliance => Icons.verified_user_rounded,
        AppModule.familyDashboard => Icons.family_restroom_rounded,
        AppModule.familyConstitution => Icons.menu_book_rounded,
        AppModule.familyTree => Icons.account_tree_rounded,
        AppModule.familyDistribution => Icons.volunteer_activism_rounded,
        AppModule.familySuccession => Icons.swap_horiz_rounded,
        AppModule.familyDecisions => Icons.how_to_vote_outlined,
      };

  /// وحدات مشتركة تظهر في أي بوابة لمن يملك صلاحيتها
  bool get shared =>
      this == AppModule.profile ||
      this == AppModule.auditLog ||
      this == AppModule.notifications ||
      this == AppModule.professionalReviews ||
      this == AppModule.compliance;

  Portal get portal => switch (this) {
        AppModule.adminDashboard ||
        AppModule.companies ||
        AppModule.users ||
        AppModule.roles ||
        AppModule.controlPoints ||
        AppModule.securityMonitor ||
        AppModule.platformSettings ||
        AppModule.questionBank ||
        AppModule.clauseLibrary ||
        AppModule.logicRules ||
        AppModule.votingSettings ||
        AppModule.currencySettings ||
        AppModule.auditLog ||
        AppModule.versionManager =>
          Portal.admin,
        AppModule.operationsDashboard ||
        AppModule.opsTransactions ||
        AppModule.opsFrozen ||
        AppModule.opsViolations ||
        AppModule.opsExpenses ||
        AppModule.currentAccount ||
        AppModule.payroll ||
        AppModule.approvalCenter ||
        AppModule.decisionExecution ||
        AppModule.plans ||
        AppModule.correspondence ||
        AppModule.opsAlerts ||
        AppModule.opsReports =>
          Portal.operations,
        AppModule.ruleTest || AppModule.expenseLimits || AppModule.channels || AppModule.integrations => Portal.admin,
        AppModule.professionalTasks ||
        AppModule.engagement ||
        AppModule.legalReview ||
        AppModule.accountingReview ||
        AppModule.proComments ||
        AppModule.proArchive =>
          Portal.professional,
        AppModule.familyDashboard ||
        AppModule.familyConstitution ||
        AppModule.familyTree ||
        AppModule.familyDistribution ||
        AppModule.familySuccession ||
        AppModule.familyDecisions =>
          Portal.family,
        _ => Portal.partner,
      };
}

/// وحدات الحوكمة العائلية: تظهر للشركاء المؤسسين وأفراد العائلة المدعوين، وللشركة العائلية فقط
const kFamilyModules = {
  AppModule.familyDashboard,
  AppModule.familyConstitution,
  AppModule.familyTree,
  AppModule.familyDistribution,
  AppModule.familySuccession,
  AppModule.familyDecisions,
};

/// صلاحيات الوصول حسب الدور. تُراجع بعد الدخول، فالدخول وحده لا يمنح حقاً في الشركة.
class Permissions {
  Permissions._();

  static const Map<CompanyRole, Set<AppModule>> _byRole = {
    CompanyRole.managingPartner: {
      // الشريك المدير يدير العمليات اليومية في الشركات الصغيرة حتى يُعيَّن مدير تنفيذي
      AppModule.operationsDashboard,
      AppModule.opsTransactions,
      AppModule.opsFrozen,
      AppModule.opsViolations,
      AppModule.opsExpenses,
      AppModule.currentAccount,
      AppModule.payroll,
      AppModule.approvalCenter,
      AppModule.decisionExecution,
      AppModule.plans,
      AppModule.correspondence,
      AppModule.opsAlerts,
      AppModule.opsReports,
      AppModule.partnerReports,
      AppModule.professionalReviews,
      AppModule.compliance,
      ...kFamilyModules,
      AppModule.dashboard,
      AppModule.partners,
      AppModule.establishment,
      AppModule.voting,
      AppModule.versions,
      AppModule.approvals,
      AppModule.transactions,
      AppModule.disputes,
      AppModule.notifications,
      AppModule.profile,
      AppModule.auditLog,
    },
    CompanyRole.partner: {
      AppModule.partnerReports,
      AppModule.professionalReviews,
      AppModule.compliance,
      ...kFamilyModules,
      AppModule.dashboard,
      AppModule.partners,
      AppModule.establishment,
      AppModule.voting,
      AppModule.versions,
      AppModule.approvals,
      AppModule.transactions,
      AppModule.disputes,
      AppModule.notifications,
      AppModule.profile,
      AppModule.auditLog,
    },
    CompanyRole.systemAdmin: {
      AppModule.professionalReviews,
      AppModule.adminDashboard,
      AppModule.companies,
      AppModule.users,
      AppModule.roles,
      AppModule.controlPoints,
      AppModule.securityMonitor,
      AppModule.platformSettings,
      AppModule.questionBank,
      AppModule.clauseLibrary,
      AppModule.logicRules,
      AppModule.votingSettings,
      AppModule.currencySettings,
      AppModule.ruleTest,
      AppModule.expenseLimits,
      AppModule.channels,
      AppModule.integrations,
      AppModule.versionManager,
      AppModule.auditLog,
      AppModule.profile,
    },
    CompanyRole.legalAdmin: {
      AppModule.compliance,
      AppModule.adminDashboard,
      AppModule.questionBank,
      AppModule.clauseLibrary,
      AppModule.logicRules,
      AppModule.versionManager,
      AppModule.auditLog,
      AppModule.profile,
    },
    CompanyRole.executiveManager: {
      AppModule.operationsDashboard,
      AppModule.opsTransactions,
      AppModule.opsFrozen,
      AppModule.opsViolations,
      AppModule.opsExpenses,
      AppModule.approvalCenter,
      AppModule.decisionExecution,
      AppModule.plans,
      AppModule.correspondence,
      AppModule.opsAlerts,
      AppModule.opsReports,
      AppModule.notifications,
      AppModule.profile,
    },
    CompanyRole.financialManager: {
      AppModule.operationsDashboard,
      AppModule.opsTransactions,
      AppModule.opsFrozen,
      AppModule.opsViolations,
      AppModule.opsExpenses,
      AppModule.currentAccount,
      AppModule.payroll,
      AppModule.approvalCenter,
      AppModule.opsAlerts,
      AppModule.opsReports,
      AppModule.notifications,
      AppModule.profile,
    },
    CompanyRole.departmentManager: {
      AppModule.operationsDashboard,
      AppModule.opsTransactions,
      AppModule.plans,
      AppModule.opsAlerts,
      AppModule.profile,
    },
    CompanyRole.lawyer: {
      AppModule.professionalTasks,
      AppModule.engagement,
      AppModule.legalReview,
      AppModule.proComments,
      AppModule.proArchive,
      AppModule.profile,
    },
    CompanyRole.accountant: {
      AppModule.professionalTasks,
      AppModule.engagement,
      AppModule.accountingReview,
      AppModule.proComments,
      AppModule.proArchive,
      AppModule.profile,
    },
    CompanyRole.witness: {AppModule.professionalTasks, AppModule.profile},
    CompanyRole.familyMember: {...kFamilyModules, AppModule.profile},
  };

  static Set<AppModule> modulesFor(Iterable<CompanyRole> roles) =>
      {for (final r in roles) ...?_byRole[r]};

  static bool can(Iterable<CompanyRole> roles, AppModule m) => modulesFor(roles).contains(m);

  // ───────────── المصفوفة القابلة للتعديل (A04) ─────────────

  /// الإجراءات الافتراضية لدور على وحدة يملكها افتراضياً
  static Set<PermAction> defaultActions(CompanyRole role, AppModule m) {
    if (!(_byRole[role]?.contains(m) ?? false)) return const {};
    if (m == AppModule.profile || m == AppModule.notifications) return {PermAction.view, PermAction.respond};
    return switch (m.portal) {
      Portal.admin => {PermAction.view, PermAction.print, PermAction.configure},
      Portal.operations => {PermAction.view, PermAction.add, PermAction.respond, PermAction.print},
      Portal.professional => {PermAction.view, PermAction.respond},
      // في العائلة: الشريك المؤسس يضيف ويصوّت، والفرد المدعو يطّلع ويصوّت إن منحه الدستور وزناً
      Portal.family => role.isPartner
          ? {PermAction.view, PermAction.add, PermAction.respond, PermAction.print, PermAction.approve}
          : {PermAction.view, PermAction.respond},
      Portal.partner => role.isPartner
          ? {PermAction.view, PermAction.add, PermAction.respond, PermAction.print, PermAction.approve}
          : {PermAction.view},
    };
  }

  /// حقوق الشريك الأساسية: لا يستطيع المسؤول نزعها (حماية تعاقدية)
  static Set<PermAction> lockedActions(CompanyRole role, AppModule m) {
    // منع إقفال الإدارة على نفسها: مسؤول النظام يحتفظ دائماً بضبط الصلاحيات
    if (role == CompanyRole.systemAdmin && m == AppModule.roles) return {PermAction.view, PermAction.configure};
    if (!role.isPartner) return const {};
    return switch (m) {
      AppModule.dashboard || AppModule.establishment || AppModule.versions || AppModule.auditLog || AppModule.notifications =>
        {PermAction.view},
      AppModule.voting => {PermAction.view, PermAction.respond, PermAction.approve},
      AppModule.approvals => {PermAction.view, PermAction.approve},
      AppModule.disputes => {PermAction.view, PermAction.respond},
      _ => const {},
    };
  }

  /// الإجراءات الفعلية بعد تطبيق تخصيص الشركة، مع إبقاء الحقوق المقفلة دائماً
  static Set<PermAction> actionsFor(CompanyRole role, AppModule m, Company? c) {
    final o = c?.permissions[role.name]?[m.name];
    final base = o == null ? defaultActions(role, m) : o.map(PermAction.values.byName).toSet();
    return {...base, ...lockedActions(role, m)};
  }

  static Set<PermAction> actions(Iterable<CompanyRole> roles, AppModule m, Company? c) =>
      {for (final r in roles) ...actionsFor(r, m, c)};

  /// الوحدات الظاهرة: التي يملك عليها الدور إجراء العرض
  static Set<AppModule> effectiveModules(Iterable<CompanyRole> roles, Company? c) =>
      {for (final m in AppModule.values) if (actions(roles, m, c).contains(PermAction.view)) m};

  /// صلاحية نقطة إفصاح (A05): تخصيص الشركة أو الافتراضي. البيانات الشخصية لغير الشركاء
  /// لا تُتاح إلا بعد موافقة كل الشركاء المعنيين.
  static Set<PermAction> pointActions(Iterable<CompanyRole> roles, String pointId, Company? c) {
    final p = ControlPoint.byId(pointId);
    final out = <PermAction>{};
    for (final r in roles) {
      final o = c?.controlPoints[pointId]?[r.name];
      final a = o == null ? (p.defaults[r] ?? const {}) : o.map(PermAction.values.byName).toSet();
      if (p.requiresConsent && !r.isPartner && a.isNotEmpty && !(c?.consentComplete(pointId, r) ?? false)) continue;
      out.addAll(a);
    }
    return out;
  }

  /// البوابات المتاحة لمجموعة أدوار، بالترتيب الثابت للبوابات
  static List<Portal> portalsFor(Iterable<CompanyRole> roles) {
    final set = roles.map((r) => r.portal).toSet();
    return Portal.values.where(set.contains).toList();
  }
}

/// مرحلة الشركة في دورة حياتها
enum CompanyStatus { establishment, active, suspended, liquidation, archived }

extension CompanyStatusX on CompanyStatus {
  String get label => switch (this) {
        CompanyStatus.establishment => 'قيد التأسيس',
        CompanyStatus.active => 'نشطة',
        CompanyStatus.suspended => 'موقوفة',
        CompanyStatus.liquidation => 'قيد التصفية',
        CompanyStatus.archived => 'مؤرشفة بعد التصفية',
      };
}

/// عضو في الشركة: شريك أو موظف أو طرف مهني
class CompanyMember {
  final String id;
  final String name;
  final String phone;
  final String nationalId;
  final Set<CompanyRole> roles;
  final double equity; // نسبة الملكية، وهي وزن التصويت

  /// موظف أو طرف مدعو من الإدارة بلا حصص (ليس جزءاً من جدول الحصص في العقد)
  final bool staff;
  final MemberStatus status;

  /// الصفة القانونية (القانون اليمني): فئة الشريك في شركات التوصية، والجنسية، والولي للقاصر
  final String? partnerClass; // general / limited
  final bool yemeni;
  final String? guardianName;
  final String? guardianshipRef;

  /// البريد الإلكتروني: وسيلة دخول بديلة برقم سر مبدئي يسلّمه مدير النظام
  final String email;

  const CompanyMember({
    required this.id,
    required this.name,
    required this.phone,
    this.nationalId = '',
    required this.roles,
    this.equity = 0,
    this.staff = false,
    this.status = MemberStatus.active,
    this.partnerClass,
    this.yemeni = true,
    this.guardianName,
    this.guardianshipRef,
    this.email = '',
  });

  /// قاصر أو ناقص أهلية يمثّله وليّه أو وصيّه
  bool get minor => guardianName != null && guardianName!.isNotEmpty;

  bool get isPartner => roles.any((r) => r.isPartner);
  bool get active => status == MemberStatus.active;

  CompanyMember copyWith({Set<CompanyRole>? roles, MemberStatus? status, double? equity}) => CompanyMember(
        id: id,
        name: name,
        phone: phone,
        nationalId: nationalId,
        roles: roles ?? this.roles,
        equity: equity ?? this.equity,
        staff: staff,
        status: status ?? this.status,
        partnerClass: partnerClass,
        yemeni: yemeni,
        guardianName: guardianName,
        guardianshipRef: guardianshipRef,
        email: email,
      );

  SessionPartner toSessionPartner() => SessionPartner(
      id: id,
      name: name,
      nationalId: nationalId,
      phone: phone,
      equity: equity,
      partnerClass: partnerClass,
      guardianName: guardianName,
      guardianshipRef: guardianshipRef,
      email: email);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'nationalId': nationalId,
        'roles': roles.map((r) => r.name).toList(),
        'equity': equity,
        if (staff) 'staff': true,
        if (status != MemberStatus.active) 'status': status.name,
        if (partnerClass != null) 'partnerClass': partnerClass,
        if (!yemeni) 'yemeni': false,
        if (guardianName != null) 'guardianName': guardianName,
        if (guardianshipRef != null) 'guardianshipRef': guardianshipRef,
        if (email.isNotEmpty) 'email': email,
      };

  factory CompanyMember.fromJson(Map<String, dynamic> j) => CompanyMember(
        id: j['id'] as String,
        name: j['name'] as String,
        phone: j['phone'] as String? ?? '',
        nationalId: j['nationalId'] as String? ?? '',
        roles: (j['roles'] as List? ?? []).map((r) => CompanyRole.values.byName(r as String)).toSet(),
        equity: (j['equity'] as num?)?.toDouble() ?? 0,
        staff: j['staff'] as bool? ?? false,
        status: MemberStatus.values.byName(j['status'] as String? ?? 'active'),
        partnerClass: j['partnerClass'] as String?,
        yemeni: j['yemeni'] as bool? ?? true,
        guardianName: j['guardianName'] as String?,
        guardianshipRef: j['guardianshipRef'] as String?,
        email: j['email'] as String? ?? '',
      );

  /// مفاتيح هوية العضو: رقم الجوال، ومفتاح البريد إن وُجد
  List<String> identityKeys([String? emailOverride]) => [
        if (phone.isNotEmpty) phone,
        if ((emailOverride ?? email).isNotEmpty) 'email:${(emailOverride ?? email).trim().toLowerCase()}',
      ];
}

/// الشركة: الكيان الذي تُبنى حوله الجلسات والعقد والحوكمة
class Company {
  final String id;
  String legalName;
  String companyType;
  AppCurrency currency;
  double capital;
  CompanyStatus status;
  List<CompanyMember> members;
  int contractVersion; // 0 = لا يوجد عقد موقّع بعد
  VotingSettings votingSettings; // A11: تُنسخ إلى جلسة التأسيس عند إنشائها
  final DateTime createdAt;
  final String createdBy;

  // ───── الإدارة (المرحلة 4) ─────
  /// الحوكمة العائلية مفعّلة (شركة عائلية): وحدة اختيارية يفعّلها الشركاء
  bool familyEnabled;

  /// أغراض الشركة (بند جوهري في عقد التأسيس)
  String purpose;

  /// سعر الصرف المعتمد بالريال اليمني لكل وحدة من عملة العقد (للتحقق من الحد الأدنى لرأس المال)
  double? yerRate;

  /// خطوات الشهر والاستيفاء القانوني: الخطوة ← {done, ref, at}
  Map<String, Map<String, dynamic>> compliance;

  /// بريد دخول يضيفه مدير النظام لعضو لاحقاً دون المساس بجدول الحصص: العضو ← البريد
  Map<String, String> memberEmails;

  String emailOf(CompanyMember m) => memberEmails[m.id] ?? m.email;

  List<String> keysOf(CompanyMember m) => m.identityKeys(emailOf(m));

  /// تخصيص مصفوفة الصلاحيات: الدور ← الوحدة ← الإجراءات
  Map<String, Map<String, List<String>>> permissions;

  /// تخصيص نقاط الإفصاح: النقطة ← الدور ← الإجراءات
  Map<String, Map<String, List<String>>> controlPoints;

  /// موافقات الشركاء على إتاحة بياناتهم الشخصية: "النقطة|الدور" ← العضو ← الوقت
  Map<String, Map<String, String>> consents;

  /// إعدادات المنصة غير التعاقدية (A21)
  Map<String, Object?> settings;

  /// معالجة أحداث الأمان (A20): معرّف الحدث ← المعالجة
  Map<String, Map<String, dynamic>> triage;

  /// آخر دخول لكل عضو؛ العضو الذي لم يدخل بعد دعوته معلّقة
  Map<String, String> lastSeen;

  Company({
    required this.id,
    required this.legalName,
    required this.companyType,
    required this.currency,
    required this.capital,
    this.status = CompanyStatus.establishment,
    required this.members,
    this.contractVersion = 0,
    this.votingSettings = VotingSettings.defaults,
    required this.createdAt,
    required this.createdBy,
    Map<String, Map<String, List<String>>>? permissions,
    Map<String, Map<String, List<String>>>? controlPoints,
    Map<String, Map<String, String>>? consents,
    Map<String, Object?>? settings,
    Map<String, Map<String, dynamic>>? triage,
    Map<String, String>? lastSeen,
    this.familyEnabled = false,
    this.purpose = '',
    this.yerRate,
    Map<String, Map<String, dynamic>>? compliance,
    Map<String, String>? memberEmails,
  })  : compliance = compliance ?? {},
        memberEmails = memberEmails ?? {},
        permissions = permissions ?? {},
        controlPoints = controlPoints ?? {},
        consents = consents ?? {},
        settings = settings ?? {},
        triage = triage ?? {},
        lastSeen = lastSeen ?? {};

  /// قيمة إعداد المنصة أو قيمته الافتراضية
  T setting<T>(String key) => (settings[key] ?? PlatformSetting.byKey(key).defaultValue) as T;

  /// هل وافق كل الشركاء على إتاحة نقطة بيانات شخصية لهذا الدور؟
  bool consentComplete(String pointId, CompanyRole role) {
    final given = consents['$pointId|${role.name}'] ?? const {};
    return partners.every((p) => given.containsKey(p.id));
  }

  List<CompanyMember> get partners => members.where((m) => m.isPartner && !m.staff).toList();

  List<CompanyMember> get staffMembers => members.where((m) => m.staff).toList();

  double get equityTotal => partners.fold(0, (a, m) => a + m.equity);

  CompanyMember? memberByPhone(String? phone) =>
      phone == null ? null : members.where((m) => m.active && keysOf(m).contains(phone)).firstOrNull;

  Map<String, dynamic> toJson() => {
        'id': id,
        'legalName': legalName,
        'companyType': companyType,
        'currency': currency.name,
        'capital': capital,
        'status': status.name,
        // الشركاء وأعضاء التأسيس في "members"، والموظفون المدعوون في "staff" منفصلين
        'members': members.where((m) => !m.staff).map((m) => m.toJson()).toList(),
        'staff': members.where((m) => m.staff).map((m) => m.toJson()).toList(),
        // الموقوف يفقد الوصول للقراءة فوراً
        // قوائم الوصول تضم رقم الجوال ومفتاح البريد لكل عضو
        'memberPhones': members.where((m) => m.active).expand(keysOf).toSet().toList(),
        'partnerPhones': members.where((m) => !m.staff).expand(keysOf).toSet().toList(),
        'memberEmails': memberEmails,
        'permissions': permissions,
        'controlPoints': controlPoints,
        'consents': consents,
        // مسؤولو النظام: يضبطون الصلاحيات والإعدادات ويدعون الموظفين (تتحقق منها قواعد الأمان)
        'adminPhones': members.where((m) => m.active && m.roles.contains(CompanyRole.systemAdmin)).expand(keysOf).toSet().toList(),
        'settings': settings,
        'triage': triage,
        'lastSeen': lastSeen,
        'familyEnabled': familyEnabled,
        'purpose': purpose,
        'yerRate': yerRate,
        'compliance': compliance,
        // من يصل إلى بيانات العائلة (تتحقق منها قواعد الأمان): الشركاء وأفراد العائلة المدعوون
        'familyPhones': familyEnabled
            ? members
                .where((m) => m.active && (m.isPartner || m.roles.contains(CompanyRole.familyMember)))
                .expand(keysOf)
                .toSet()
                .toList()
            : <String>[],
        'contractVersion': contractVersion,
        'votingSettings': votingSettings.toJson(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'createdBy': createdBy,
      };

  factory Company.fromJson(Map<String, dynamic> j) => Company(
        id: j['id'] as String,
        legalName: j['legalName'] as String,
        companyType: j['companyType'] as String,
        currency: AppCurrency.values.byName(j['currency'] as String),
        capital: (j['capital'] as num).toDouble(),
        status: CompanyStatus.values.byName(j['status'] as String? ?? 'establishment'),
        members: [
          for (final m in [...(j['members'] as List), ...(j['staff'] as List? ?? [])])
            CompanyMember.fromJson(Map<String, dynamic>.from(m as Map)),
        ],
        contractVersion: (j['contractVersion'] as num?)?.toInt() ?? 0,
        votingSettings: VotingSettings.fromJson(
            j['votingSettings'] == null ? null : Map<String, dynamic>.from(j['votingSettings'] as Map)),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        createdBy: j['createdBy'] as String? ?? '',
        permissions: _nested(j['permissions']),
        controlPoints: _nested(j['controlPoints']),
        consents: Map<String, dynamic>.from(j['consents'] as Map? ?? {})
            .map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map).map((a, b) => MapEntry(a, '$b')))),
        settings: Map<String, Object?>.from(j['settings'] as Map? ?? {}),
        triage: Map<String, dynamic>.from(j['triage'] as Map? ?? {})
            .map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map))),
        lastSeen: Map<String, dynamic>.from(j['lastSeen'] as Map? ?? {}).map((k, v) => MapEntry(k, '$v')),
        familyEnabled: j['familyEnabled'] as bool? ?? false,
        purpose: j['purpose'] as String? ?? '',
        yerRate: (j['yerRate'] as num?)?.toDouble(),
        memberEmails: Map<String, dynamic>.from(j['memberEmails'] as Map? ?? {}).map((k, v) => MapEntry(k, '$v')),
        compliance: Map<String, dynamic>.from(j['compliance'] as Map? ?? {})
            .map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map))),
      );

  static Map<String, Map<String, List<String>>> _nested(Object? raw) =>
      Map<String, dynamic>.from(raw as Map? ?? {}).map((k, v) => MapEntry(
          k,
          Map<String, dynamic>.from(v as Map)
              .map((a, b) => MapEntry(a, (b as List).map((e) => '$e').toList()))));
}

/// نوع الفاعل في سجل التدقيق: يجب التمييز بين فعل المستخدم وفعل النظام
enum ActorType { user, system, ruleEngine, integration }

extension ActorTypeX on ActorType {
  String get label => switch (this) {
        ActorType.user => 'مستخدم',
        ActorType.system => 'النظام',
        ActorType.ruleEngine => 'محرك القواعد',
        ActorType.integration => 'تكامل خارجي',
      };

  IconData get icon => switch (this) {
        ActorType.user => Icons.person_rounded,
        ActorType.system => Icons.settings_suggest_rounded,
        ActorType.ruleEngine => Icons.rule_rounded,
        ActorType.integration => Icons.sync_alt_rounded,
      };
}

/// حدث تدقيق: سجل للإضافة فقط، لا يُعدَّل ولا يُحذف
class AuditEvent {
  final String id;
  final String companyId;
  final DateTime at;
  final ActorType actorType;
  final String actorId;
  final String actorName;
  final String action; // وصف الإجراء بالعربية
  final String objectType; // session / clause / contract / company ...
  final String objectId;
  final String result;
  final String? evidenceRef; // مرجع الدليل: بصمة، معرّف رسالة، رقم إصدار

  /// إصدار العقد الساري وقت الحدث (سياق الإصدار في P15)
  final int? contractVersion;

  const AuditEvent({
    required this.id,
    required this.companyId,
    required this.at,
    required this.actorType,
    required this.actorId,
    required this.actorName,
    required this.action,
    required this.objectType,
    required this.objectId,
    required this.result,
    this.evidenceRef,
    this.contractVersion,
  });

  /// حدث نظام (آلي) مقابل فعل مستخدم: يجب التمييز بينهما في العرض
  bool get isSystem => actorType != ActorType.user;

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyId': companyId,
        'at': at.toUtc().toIso8601String(),
        'actorType': actorType.name,
        'actorId': actorId,
        'actorName': actorName,
        'action': action,
        'objectType': objectType,
        'objectId': objectId,
        'result': result,
        'evidenceRef': evidenceRef,
        'contractVersion': contractVersion,
      };

  factory AuditEvent.fromJson(Map<String, dynamic> j) => AuditEvent(
        id: j['id'] as String,
        companyId: j['companyId'] as String,
        at: DateTime.tryParse(j['at']?.toString() ?? '') ?? DateTime.now(),
        actorType: ActorType.values.byName(j['actorType'] as String),
        actorId: j['actorId'] as String? ?? '',
        actorName: j['actorName'] as String? ?? '',
        action: j['action'] as String,
        objectType: j['objectType'] as String? ?? '',
        objectId: j['objectId'] as String? ?? '',
        result: j['result'] as String? ?? '',
        evidenceRef: j['evidenceRef'] as String?,
        contractVersion: (j['contractVersion'] as num?)?.toInt(),
      );
}
