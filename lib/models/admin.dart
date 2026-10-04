import 'package:flutter/material.dart';

import 'company.dart';

/// بوابة الإدارة (المرحلة 4): الصلاحيات الدقيقة، ونقاط الإفصاح، وإعدادات المنصة، ومراقبة الأمان.
/// المبدأ: الصلاحية التقنية لا تمنح سلطة تجارية، ولا يستطيع المسؤول نزع حقوق الشريك الأساسية.

/// الإجراءات في مصفوفة الصلاحيات (A04)
enum PermAction { view, add, respond, print, approve, configure }

extension PermActionX on PermAction {
  String get label => switch (this) {
        PermAction.view => 'عرض',
        PermAction.add => 'إضافة',
        PermAction.respond => 'رد',
        PermAction.print => 'طباعة وتصدير',
        PermAction.approve => 'اعتماد',
        PermAction.configure => 'ضبط',
      };
}

/// حالة العضو: الموقوف يفقد الوصول دون حذف سجله
enum MemberStatus { active, suspended }

extension MemberStatusX on MemberStatus {
  String get label => this == MemberStatus.active ? 'نشط' : 'موقوف';
}

/// حساسية البيانات في نقاط الإفصاح (A05)
enum Sensitivity { internal, confidential, personal }

extension SensitivityX on Sensitivity {
  String get label => switch (this) {
        Sensitivity.internal => 'داخلي',
        Sensitivity.confidential => 'سري',
        Sensitivity.personal => 'بيانات شخصية للشريك',
      };

  Color get color => switch (this) {
        Sensitivity.internal => const Color(0xFF3498DB),
        Sensitivity.confidential => const Color(0xFFF39C12),
        Sensitivity.personal => const Color(0xFFE74C3C),
      };
}

/// نقطة إفصاح/تحكم: نوع بيانات محدد وما يُسمح به عليه لكل دور
class ControlPoint {
  final String id;
  final String label;
  final String dataType;
  final Sensitivity sensitivity;
  final Set<PermAction> actions; // الإجراءات المنطبقة على هذه النقطة
  final Map<CompanyRole, Set<PermAction>> defaults;

  const ControlPoint({
    required this.id,
    required this.label,
    required this.dataType,
    required this.sensitivity,
    required this.actions,
    required this.defaults,
  });

  /// البيانات الشخصية للشريك تتطلب موافقته المباشرة قبل إتاحتها لغير الشركاء
  bool get requiresConsent => sensitivity == Sensitivity.personal;

  static const _partners = {CompanyRole.managingPartner, CompanyRole.partner};

  static Map<CompanyRole, Set<PermAction>> _all(Set<CompanyRole> roles, Set<PermAction> a) => {for (final r in roles) r: a};

  static final catalog = <ControlPoint>[
    ControlPoint(
      id: 'partner.identity',
      label: 'هوية الشريك (رقم الهوية)',
      dataType: 'بيانات الشركاء',
      sensitivity: Sensitivity.personal,
      actions: {PermAction.view, PermAction.print},
      defaults: _all(_partners, {PermAction.view, PermAction.print}),
    ),
    ControlPoint(
      id: 'partner.phone',
      label: 'جوال الشريك',
      dataType: 'بيانات الشركاء',
      sensitivity: Sensitivity.personal,
      actions: {PermAction.view},
      defaults: _all(_partners, {PermAction.view}),
    ),
    ControlPoint(
      id: 'partner.equity',
      label: 'حصص الشركاء',
      dataType: 'جدول الحصص',
      sensitivity: Sensitivity.confidential,
      actions: {PermAction.view, PermAction.print},
      defaults: {
        ..._all(_partners, {PermAction.view, PermAction.print}),
        CompanyRole.systemAdmin: {PermAction.view},
        CompanyRole.legalAdmin: {PermAction.view},
      },
    ),
    ControlPoint(
      id: 'contract.document',
      label: 'مستند العقد النهائي',
      dataType: 'العقد',
      sensitivity: Sensitivity.confidential,
      actions: {PermAction.view, PermAction.print},
      defaults: {
        ..._all(_partners, {PermAction.view, PermAction.print}),
        CompanyRole.legalAdmin: {PermAction.view},
        CompanyRole.lawyer: {PermAction.view},
      },
    ),
    ControlPoint(
      id: 'tx.details',
      label: 'تفاصيل العمليات المالية',
      dataType: 'العمليات',
      sensitivity: Sensitivity.internal,
      actions: {PermAction.view, PermAction.add, PermAction.respond, PermAction.print},
      defaults: {
        ..._all(_partners, {PermAction.view, PermAction.respond, PermAction.print}),
        CompanyRole.managingPartner: {PermAction.view, PermAction.add, PermAction.respond, PermAction.print},
        CompanyRole.executiveManager: {PermAction.view, PermAction.add, PermAction.respond, PermAction.print},
        CompanyRole.financialManager: {PermAction.view, PermAction.add, PermAction.respond, PermAction.print},
        CompanyRole.departmentManager: {PermAction.view, PermAction.add},
        CompanyRole.accountant: {PermAction.view, PermAction.print},
      },
    ),
    ControlPoint(
      id: 'payroll.salaries',
      label: 'الرواتب الفردية',
      dataType: 'الرواتب',
      sensitivity: Sensitivity.confidential,
      actions: {PermAction.view, PermAction.add, PermAction.print},
      defaults: {
        ..._all(_partners, {PermAction.view}),
        // الشريك المدير يدير الرواتب حتى يُعيَّن مدير مالي؛ تغيير راتبه هو يمر بقاعدة العقد
        CompanyRole.managingPartner: {PermAction.view, PermAction.add, PermAction.print},
        CompanyRole.financialManager: {PermAction.view, PermAction.add, PermAction.print},
      },
    ),
    ControlPoint(
      id: 'partner.currentAccount',
      label: 'الحساب الجاري للشريك المدير',
      dataType: 'الحساب الجاري',
      sensitivity: Sensitivity.personal,
      actions: {PermAction.view, PermAction.add, PermAction.print},
      defaults: _all(_partners, {PermAction.view, PermAction.print}),
    ),
    ControlPoint(
      id: 'audit.export',
      label: 'تصدير سجل التدقيق',
      dataType: 'سجل التدقيق',
      sensitivity: Sensitivity.internal,
      actions: {PermAction.view, PermAction.print},
      defaults: {
        ..._all(_partners, {PermAction.view, PermAction.print}),
        CompanyRole.systemAdmin: {PermAction.view, PermAction.print},
        CompanyRole.legalAdmin: {PermAction.view, PermAction.print},
      },
    ),
    ControlPoint(
      id: 'dispute.case',
      label: 'ملفات النزاعات',
      dataType: 'النزاعات',
      sensitivity: Sensitivity.confidential,
      actions: {PermAction.view, PermAction.respond, PermAction.print},
      defaults: {
        ..._all(_partners, {PermAction.view, PermAction.respond, PermAction.print}),
        CompanyRole.lawyer: {PermAction.view},
      },
    ),
  ];

  static ControlPoint byId(String id) => catalog.firstWhere((p) => p.id == id);
}

/// إعداد منصة غير تعاقدي (A21)
enum SettingKind { integer, toggle, choice }

class PlatformSetting {
  final String key;
  final String label;
  final String category;
  final SettingKind kind;
  final Object defaultValue;
  final int? min;
  final int? max;
  final Map<String, String>? choices;
  final String impact;

  /// لا يسري إلا بعد ربط خدمة خارجية (مثل مزوّد الرسائل)
  final bool requiresService;

  /// من شروط الشركاء (مهل الاستثناء والنزاعات): يعدّلها الشركاء وحدهم لا مسؤول النظام
  final bool partnerGoverned;

  const PlatformSetting({
    required this.key,
    required this.label,
    required this.category,
    required this.kind,
    required this.defaultValue,
    this.min,
    this.max,
    this.choices,
    required this.impact,
    this.requiresService = false,
    this.partnerGoverned = false,
  });

  String? validate(Object? v) {
    switch (kind) {
      case SettingKind.integer:
        final n = v is int ? v : int.tryParse('$v');
        if (n == null) return 'أدخل رقماً صحيحاً';
        if (min != null && n < min!) return 'الحد الأدنى $min';
        if (max != null && n > max!) return 'الحد الأعلى $max';
        return null;
      case SettingKind.toggle:
        return v is bool ? null : 'قيمة غير صالحة';
      case SettingKind.choice:
        return choices!.containsKey(v) ? null : 'اختر من القيم المسموحة';
    }
  }

  String display(Object? v) => switch (kind) {
        SettingKind.toggle => v == true ? 'مفعّل' : 'موقوف',
        SettingKind.choice => choices![v] ?? '$v',
        SettingKind.integer => '$v',
      };

  static const catalog = <PlatformSetting>[
    PlatformSetting(
      key: 'locale',
      label: 'لغة الواجهة',
      category: 'التوطين',
      kind: SettingKind.choice,
      defaultValue: 'ar',
      choices: {'ar': 'العربية'},
      impact: 'الواجهة والعقود باللغة العربية. لغات أخرى تُضاف لاحقاً.',
    ),
    PlatformSetting(
      key: 'exception.deadlineDays',
      label: 'مهلة التصويت على طلب الاستثناء (أيام)',
      category: 'الرقابة المالية',
      kind: SettingKind.integer,
      defaultValue: 3,
      min: 1,
      max: 14,
      partnerGoverned: true,
      impact: 'تسري على طلبات الاستثناء الجديدة فقط.',
    ),
    PlatformSetting(
      key: 'dispute.negotiationDays',
      label: 'مهلة التفاوض المباشر في النزاع (أيام)',
      category: 'النزاعات',
      kind: SettingKind.integer,
      defaultValue: 14,
      min: 7,
      max: 30,
      partnerGoverned: true,
      impact: 'تسري على النزاعات الجديدة فقط. مخطط النزاعات يحددها بـ 14 يوماً.',
    ),
    PlatformSetting(
      key: 'dispute.mediationDays',
      label: 'مهلة الوساطة (أيام)',
      category: 'النزاعات',
      kind: SettingKind.integer,
      defaultValue: 30,
      min: 15,
      max: 30,
      partnerGoverned: true,
      impact: 'تسري على النزاعات التي تدخل الوساطة بعد الحفظ. المخطط يحددها بين 15 و30 يوماً.',
    ),
    PlatformSetting(
      key: 'dispute.buyOutHours',
      label: 'مهلة الرد على عرض الشراء (ساعات)',
      category: 'النزاعات',
      kind: SettingKind.integer,
      defaultValue: 72,
      min: 48,
      max: 72,
      partnerGoverned: true,
      impact: 'تسري على العروض الجديدة فقط. المخطط يحددها بين 48 و72 ساعة.',
    ),
    PlatformSetting(
      key: 'audit.retentionYears',
      label: 'مدة الاحتفاظ بسجل التدقيق (سنوات)',
      category: 'الاحتفاظ',
      kind: SettingKind.integer,
      defaultValue: 10,
      min: 10,
      max: 30,
      impact: 'لا يمكن تقليلها عن 10 سنوات. السجل لا يُحذف خلالها بأي حال.',
    ),
    PlatformSetting(
      key: 'notify.sms',
      label: 'إرسال الإشعارات القانونية برسائل SMS',
      category: 'الإشعارات',
      kind: SettingKind.toggle,
      defaultValue: false,
      impact: 'يحتاج ربط مزوّد رسائل يدعم اليمن. حتى ذلك تُسجَّل القناة "غير مهيأة".',
      requiresService: true,
    ),
  ];

  static PlatformSetting byKey(String k) => catalog.firstWhere((s) => s.key == k);
}

/// شدّة الحدث الأمني: تسميات نصية بجانب اللون حتى لا يُعتمد على اللون وحده
enum Severity { info, low, medium, high }

extension SeverityX on Severity {
  String get label => switch (this) {
        Severity.info => 'معلومة',
        Severity.low => 'منخفضة',
        Severity.medium => 'متوسطة',
        Severity.high => 'مرتفعة',
      };

  Color get color => switch (this) {
        Severity.info => const Color(0xFF7C8CA3),
        Severity.low => const Color(0xFF3498DB),
        Severity.medium => const Color(0xFFF39C12),
        Severity.high => const Color(0xFFE74C3C),
      };
}

enum TriageState { open, investigating, resolved, suppressed }

extension TriageStateX on TriageState {
  String get label => switch (this) {
        TriageState.open => 'جديد',
        TriageState.investigating => 'قيد التحقيق',
        TriageState.resolved => 'محلول',
        TriageState.suppressed => 'مكتوم حسب السياسة',
      };
}

/// حدث أمني أو تكاملي (A20) مشتق من سجل التدقيق ودليل تسليم الإشعارات
class SecurityEvent {
  final String id;
  final String type;
  final String component;
  final Severity severity;
  final DateTime at;
  final String description;
  final String correlationId;

  const SecurityEvent({
    required this.id,
    required this.type,
    required this.component,
    required this.severity,
    required this.at,
    required this.description,
    required this.correlationId,
  });
}

/// معالجة الحدث: الحالة والمسؤول والملاحظة
class Triage {
  final TriageState state;
  final String? assignee;
  final String? note;
  final DateTime at;

  const Triage({required this.state, this.assignee, this.note, required this.at});

  Map<String, dynamic> toJson() =>
      {'state': state.name, 'assignee': assignee, 'note': note, 'at': at.toUtc().toIso8601String()};

  factory Triage.fromJson(Map<String, dynamic> j) => Triage(
        state: TriageState.values.byName(j['state'] as String),
        assignee: j['assignee'] as String?,
        note: j['note'] as String?,
        at: DateTime.tryParse(j['at']?.toString() ?? '') ?? DateTime.now(),
      );
}
