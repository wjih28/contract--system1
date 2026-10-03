import 'package:flutter/material.dart';

import 'questionnaire.dart';

/// البوابات الأربع في المنصة
enum Portal { partner, admin, operations, professional }

extension PortalX on Portal {
  String get label => switch (this) {
        Portal.partner => 'بوابة الشركاء',
        Portal.admin => 'إدارة النظام',
        Portal.operations => 'التشغيل والحوكمة',
        Portal.professional => 'الأطراف المهنية',
      };

  IconData get icon => switch (this) {
        Portal.partner => Icons.handshake_rounded,
        Portal.admin => Icons.admin_panel_settings_rounded,
        Portal.operations => Icons.business_center_rounded,
        Portal.professional => Icons.work_history_rounded,
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
      };

  Portal get portal => switch (this) {
        CompanyRole.managingPartner || CompanyRole.partner => Portal.partner,
        CompanyRole.systemAdmin || CompanyRole.legalAdmin => Portal.admin,
        CompanyRole.executiveManager ||
        CompanyRole.financialManager ||
        CompanyRole.departmentManager =>
          Portal.operations,
        CompanyRole.lawyer || CompanyRole.accountant || CompanyRole.witness => Portal.professional,
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
  approvals,
  transactions,
  disputes,
  notifications,
  profile,
  // إدارة النظام
  questionBank,
  clauseLibrary,
  logicRules,
  votingSettings,
  currencySettings,
  auditLog,
  // التشغيل
  operationsDashboard,
  opsTransactions,
  opsFrozen,
  opsViolations,
  ruleTest,
  expenseLimits,
  channels,
  integrations,
  // الأطراف المهنية
  professionalTasks,
}

extension AppModuleX on AppModule {
  String get label => switch (this) {
        AppModule.dashboard => 'لوحة الشركة',
        AppModule.partners => 'الشركاء والحصص',
        AppModule.establishment => 'التأسيس والعقد',
        AppModule.voting => 'مركز التصويت',
        AppModule.approvals => 'الموافقات والاستثناءات',
        AppModule.transactions => 'العمليات والمخالفات',
        AppModule.disputes => 'النزاعات',
        AppModule.notifications => 'الإشعارات',
        AppModule.profile => 'حسابي',
        AppModule.questionBank => 'بنك الأسئلة',
        AppModule.clauseLibrary => 'مكتبة البنود',
        AppModule.logicRules => 'القواعد المنطقية',
        AppModule.votingSettings => 'التصويت والنصاب',
        AppModule.currencySettings => 'العملات',
        AppModule.auditLog => 'سجل التدقيق',
        AppModule.operationsDashboard => 'لوحة التشغيل',
        AppModule.opsTransactions => 'العمليات المالية',
        AppModule.opsFrozen => 'العمليات المجمّدة',
        AppModule.opsViolations => 'المخالفات',
        AppModule.ruleTest => 'اختبار القواعد',
        AppModule.expenseLimits => 'حدود الصرف',
        AppModule.channels => 'القنوات والقوالب',
        AppModule.integrations => 'التكامل المحاسبي',
        AppModule.professionalTasks => 'مهامي المهنية',
      };

  IconData get icon => switch (this) {
        AppModule.dashboard => Icons.space_dashboard_rounded,
        AppModule.partners => Icons.pie_chart_rounded,
        AppModule.establishment => Icons.history_edu_rounded,
        AppModule.voting => Icons.how_to_vote_rounded,
        AppModule.approvals => Icons.fact_check_rounded,
        AppModule.transactions => Icons.receipt_long_rounded,
        AppModule.disputes => Icons.gavel_rounded,
        AppModule.notifications => Icons.notifications_active_rounded,
        AppModule.profile => Icons.person_rounded,
        AppModule.questionBank => Icons.library_books_rounded,
        AppModule.clauseLibrary => Icons.menu_book_rounded,
        AppModule.logicRules => Icons.account_tree_rounded,
        AppModule.votingSettings => Icons.tune_rounded,
        AppModule.currencySettings => Icons.currency_exchange_rounded,
        AppModule.auditLog => Icons.manage_search_rounded,
        AppModule.operationsDashboard => Icons.insights_rounded,
        AppModule.opsTransactions => Icons.receipt_long_rounded,
        AppModule.opsFrozen => Icons.ac_unit_rounded,
        AppModule.opsViolations => Icons.gpp_bad_rounded,
        AppModule.ruleTest => Icons.science_rounded,
        AppModule.expenseLimits => Icons.speed_rounded,
        AppModule.channels => Icons.campaign_rounded,
        AppModule.integrations => Icons.sync_alt_rounded,
        AppModule.professionalTasks => Icons.assignment_rounded,
      };

  /// وحدات مشتركة تظهر في أي بوابة لمن يملك صلاحيتها
  bool get shared => this == AppModule.profile || this == AppModule.auditLog || this == AppModule.notifications;

  Portal get portal => switch (this) {
        AppModule.questionBank ||
        AppModule.clauseLibrary ||
        AppModule.logicRules ||
        AppModule.votingSettings ||
        AppModule.currencySettings ||
        AppModule.auditLog =>
          Portal.admin,
        AppModule.operationsDashboard ||
        AppModule.opsTransactions ||
        AppModule.opsFrozen ||
        AppModule.opsViolations =>
          Portal.operations,
        AppModule.ruleTest || AppModule.expenseLimits || AppModule.channels || AppModule.integrations => Portal.admin,
        AppModule.professionalTasks => Portal.professional,
        _ => Portal.partner,
      };
}

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
      AppModule.dashboard,
      AppModule.partners,
      AppModule.establishment,
      AppModule.voting,
      AppModule.approvals,
      AppModule.transactions,
      AppModule.disputes,
      AppModule.notifications,
      AppModule.profile,
      AppModule.auditLog,
    },
    CompanyRole.partner: {
      AppModule.dashboard,
      AppModule.partners,
      AppModule.establishment,
      AppModule.voting,
      AppModule.approvals,
      AppModule.transactions,
      AppModule.disputes,
      AppModule.notifications,
      AppModule.profile,
      AppModule.auditLog,
    },
    CompanyRole.systemAdmin: {
      AppModule.questionBank,
      AppModule.clauseLibrary,
      AppModule.logicRules,
      AppModule.votingSettings,
      AppModule.currencySettings,
      AppModule.ruleTest,
      AppModule.expenseLimits,
      AppModule.channels,
      AppModule.integrations,
      AppModule.auditLog,
      AppModule.profile,
    },
    CompanyRole.legalAdmin: {
      AppModule.questionBank,
      AppModule.clauseLibrary,
      AppModule.logicRules,
      AppModule.auditLog,
      AppModule.profile,
    },
    CompanyRole.executiveManager: {
      AppModule.operationsDashboard,
      AppModule.opsTransactions,
      AppModule.opsFrozen,
      AppModule.opsViolations,
      AppModule.notifications,
      AppModule.profile,
    },
    CompanyRole.financialManager: {
      AppModule.operationsDashboard,
      AppModule.opsTransactions,
      AppModule.opsFrozen,
      AppModule.opsViolations,
      AppModule.notifications,
      AppModule.profile,
    },
    CompanyRole.departmentManager: {AppModule.operationsDashboard, AppModule.opsTransactions, AppModule.profile},
    CompanyRole.lawyer: {AppModule.professionalTasks, AppModule.profile},
    CompanyRole.accountant: {AppModule.professionalTasks, AppModule.profile},
    CompanyRole.witness: {AppModule.professionalTasks, AppModule.profile},
  };

  static Set<AppModule> modulesFor(Iterable<CompanyRole> roles) =>
      {for (final r in roles) ...?_byRole[r]};

  static bool can(Iterable<CompanyRole> roles, AppModule m) => modulesFor(roles).contains(m);

  /// البوابات المتاحة لمجموعة أدوار، بالترتيب الثابت للبوابات
  static List<Portal> portalsFor(Iterable<CompanyRole> roles) {
    final set = roles.map((r) => r.portal).toSet();
    return Portal.values.where(set.contains).toList();
  }
}

/// مرحلة الشركة في دورة حياتها
enum CompanyStatus { establishment, active, suspended, liquidation }

extension CompanyStatusX on CompanyStatus {
  String get label => switch (this) {
        CompanyStatus.establishment => 'قيد التأسيس',
        CompanyStatus.active => 'نشطة',
        CompanyStatus.suspended => 'موقوفة',
        CompanyStatus.liquidation => 'قيد التصفية',
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

  const CompanyMember({
    required this.id,
    required this.name,
    required this.phone,
    this.nationalId = '',
    required this.roles,
    this.equity = 0,
  });

  bool get isPartner => roles.any((r) => r.isPartner);

  SessionPartner toSessionPartner() =>
      SessionPartner(id: id, name: name, nationalId: nationalId, phone: phone, equity: equity);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'nationalId': nationalId,
        'roles': roles.map((r) => r.name).toList(),
        'equity': equity,
      };

  factory CompanyMember.fromJson(Map<String, dynamic> j) => CompanyMember(
        id: j['id'] as String,
        name: j['name'] as String,
        phone: j['phone'] as String? ?? '',
        nationalId: j['nationalId'] as String? ?? '',
        roles: (j['roles'] as List? ?? []).map((r) => CompanyRole.values.byName(r as String)).toSet(),
        equity: (j['equity'] as num?)?.toDouble() ?? 0,
      );
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
  });

  List<CompanyMember> get partners => members.where((m) => m.isPartner).toList();

  double get equityTotal => partners.fold(0, (a, m) => a + m.equity);

  CompanyMember? memberByPhone(String? phone) =>
      phone == null ? null : members.where((m) => m.phone == phone).firstOrNull;

  Map<String, dynamic> toJson() => {
        'id': id,
        'legalName': legalName,
        'companyType': companyType,
        'currency': currency.name,
        'capital': capital,
        'status': status.name,
        'members': members.map((m) => m.toJson()).toList(),
        'memberPhones': members.map((m) => m.phone).where((p) => p.isNotEmpty).toSet().toList(),
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
        members: (j['members'] as List)
            .map((m) => CompanyMember.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList(),
        contractVersion: (j['contractVersion'] as num?)?.toInt() ?? 0,
        votingSettings: VotingSettings.fromJson(
            j['votingSettings'] == null ? null : Map<String, dynamic>.from(j['votingSettings'] as Map)),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        createdBy: j['createdBy'] as String? ?? '',
      );
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
  });

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
      );
}
