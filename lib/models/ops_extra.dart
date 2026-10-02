import 'package:flutter/material.dart';

import 'questionnaire.dart';

/// التشغيل اليومي (المرحلة 4، الدفعة الثانية): الحساب الجاري، الرواتب، الخطط، المراسلات،
/// تنفيذ القرارات، والتنبيهات. كلها ضمن قواعد العقد ولا تتجاوزها.

DateTime _t(Object? v) => DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();
String _iso(DateTime d) => d.toUtc().toIso8601String();

// ───────────── O08 الحساب الجاري ─────────────

enum LedgerKind { opening, advance, salary, settlement, adjustment }

extension LedgerKindX on LedgerKind {
  String get label => switch (this) {
        LedgerKind.opening => 'رصيد افتتاحي',
        LedgerKind.advance => 'سلفة',
        LedgerKind.salary => 'راتب مستحق',
        LedgerKind.settlement => 'تسوية وسداد',
        LedgerKind.adjustment => 'قيد تسوية',
      };

  /// اتجاه القيد على الحساب: موجب = على الشريك للشركة، سالب = للشريك على الشركة
  int get sign => switch (this) {
        LedgerKind.advance || LedgerKind.opening || LedgerKind.adjustment => 1,
        LedgerKind.salary || LedgerKind.settlement => -1,
      };
}

class LedgerEntry {
  final String id;
  final String companyId;
  final String partnerId;
  final LedgerKind kind;
  final double amount; // قيمة موجبة، والاتجاه من النوع (والتسوية اليدوية قد تكون سالبة)
  final AppCurrency currency;
  final DateTime date;
  final String reference;
  final String note;
  final String createdBy;
  final String? txId; // مرحَّل آلياً من عملية سلفة
  final bool pending;

  const LedgerEntry({
    required this.id,
    required this.companyId,
    required this.partnerId,
    required this.kind,
    required this.amount,
    required this.currency,
    required this.date,
    this.reference = '',
    this.note = '',
    required this.createdBy,
    this.txId,
    this.pending = false,
  });

  double get signed => kind.sign * amount;
  bool get automatic => txId != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyId': companyId,
        'partnerId': partnerId,
        'kind': kind.name,
        'amount': amount,
        'currency': currency.name,
        'date': _iso(date),
        'reference': reference,
        'note': note,
        'createdBy': createdBy,
        'txId': txId,
        'pending': pending,
      };

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
        id: j['id'] as String,
        companyId: j['companyId'] as String,
        partnerId: j['partnerId'] as String,
        kind: LedgerKind.values.byName(j['kind'] as String),
        amount: (j['amount'] as num).toDouble(),
        currency: AppCurrency.values.byName(j['currency'] as String),
        date: _t(j['date']),
        reference: j['reference'] as String? ?? '',
        note: j['note'] as String? ?? '',
        createdBy: j['createdBy'] as String? ?? '',
        txId: j['txId'] as String?,
        pending: j['pending'] as bool? ?? false,
      );
}

// ───────────── O09 الرواتب ─────────────

enum PayrollStatus { draft, pendingApproval, awaitingPartners, approved, rejected }

extension PayrollStatusX on PayrollStatus {
  String get label => switch (this) {
        PayrollStatus.draft => 'مسودة',
        PayrollStatus.pendingApproval => 'بانتظار الاعتماد',
        PayrollStatus.awaitingPartners => 'بانتظار قرار الشركاء',
        PayrollStatus.approved => 'معتمدة',
        PayrollStatus.rejected => 'مرفوضة',
      };

  Color get color => switch (this) {
        PayrollStatus.draft => const Color(0xFFB7C0CF),
        PayrollStatus.pendingApproval => const Color(0xFF3498DB),
        PayrollStatus.awaitingPartners => const Color(0xFFF39C12),
        PayrollStatus.approved => const Color(0xFF2ECC71),
        PayrollStatus.rejected => const Color(0xFFE74C3C),
      };
}

class PayrollLine {
  final String employee;
  final String role;
  final double salary;
  final double adjustment;
  final String note;

  /// راتب الشريك المدير محمي بالعقد: تغييره يمر بقاعدة العقد وقرار الشركاء
  final bool managingPartner;

  const PayrollLine({
    required this.employee,
    required this.role,
    required this.salary,
    this.adjustment = 0,
    this.note = '',
    this.managingPartner = false,
  });

  double get total => salary + adjustment;

  Map<String, dynamic> toJson() => {
        'employee': employee,
        'role': role,
        'salary': salary,
        'adjustment': adjustment,
        'note': note,
        'managingPartner': managingPartner,
      };

  factory PayrollLine.fromJson(Map<String, dynamic> j) => PayrollLine(
        employee: j['employee'] as String,
        role: j['role'] as String? ?? '',
        salary: (j['salary'] as num).toDouble(),
        adjustment: (j['adjustment'] as num?)?.toDouble() ?? 0,
        note: j['note'] as String? ?? '',
        managingPartner: j['managingPartner'] as bool? ?? false,
      );
}

class PayrollBatch {
  final String id;
  final String companyId;
  final String period; // YYYY-MM
  final AppCurrency currency;
  List<PayrollLine> lines;
  PayrollStatus status;
  final String createdBy;
  final DateTime createdAt;
  String? decidedBy;
  DateTime? decidedAt;
  String? reason;

  /// عملية "تعديل راتب" المرتبطة عند تغيّر راتب الشريك المدير (تمر ببوابة الفحص)
  String? ruleTxId;

  PayrollBatch({
    required this.id,
    required this.companyId,
    required this.period,
    required this.currency,
    required this.lines,
    this.status = PayrollStatus.draft,
    required this.createdBy,
    required this.createdAt,
    this.decidedBy,
    this.decidedAt,
    this.reason,
    this.ruleTxId,
  });

  double get total => lines.fold(0, (a, l) => a + l.total);

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyId': companyId,
        'period': period,
        'currency': currency.name,
        'lines': lines.map((l) => l.toJson()).toList(),
        'status': status.name,
        'createdBy': createdBy,
        'createdAt': _iso(createdAt),
        'decidedBy': decidedBy,
        'decidedAt': decidedAt == null ? null : _iso(decidedAt!),
        'reason': reason,
        'ruleTxId': ruleTxId,
      };

  factory PayrollBatch.fromJson(Map<String, dynamic> j) => PayrollBatch(
        id: j['id'] as String,
        companyId: j['companyId'] as String,
        period: j['period'] as String,
        currency: AppCurrency.values.byName(j['currency'] as String),
        lines: (j['lines'] as List).map((e) => PayrollLine.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        status: PayrollStatus.values.byName(j['status'] as String),
        createdBy: j['createdBy'] as String? ?? '',
        createdAt: _t(j['createdAt']),
        decidedBy: j['decidedBy'] as String?,
        decidedAt: j['decidedAt'] == null ? null : _t(j['decidedAt']),
        reason: j['reason'] as String?,
        ruleTxId: j['ruleTxId'] as String?,
      );
}

// ───────────── O14 / O15 الخطط ─────────────

enum PlanCategory { financial, administrative, technical, marketing }

extension PlanCategoryX on PlanCategory {
  String get label => switch (this) {
        PlanCategory.financial => 'مالية',
        PlanCategory.administrative => 'إدارية',
        PlanCategory.technical => 'تقنية',
        PlanCategory.marketing => 'تسويقية',
      };
}

enum PlanSegment { monthly, quarterly, semiannual, annual }

extension PlanSegmentX on PlanSegment {
  String get label => switch (this) {
        PlanSegment.monthly => 'شهري',
        PlanSegment.quarterly => 'ربع سنوي',
        PlanSegment.semiannual => 'نصف سنوي',
        PlanSegment.annual => 'سنوي',
      };

  /// أسماء الفترات داخل السنة
  List<String> periods() => switch (this) {
        PlanSegment.monthly => [for (var i = 1; i <= 12; i++) 'الشهر $i'],
        PlanSegment.quarterly => ['الربع الأول', 'الربع الثاني', 'الربع الثالث', 'الربع الرابع'],
        PlanSegment.semiannual => ['النصف الأول', 'النصف الثاني'],
        PlanSegment.annual => ['السنة كاملة'],
      };
}

enum PlanStatus { draft, pending, approved, rejected, archived }

extension PlanStatusX on PlanStatus {
  String get label => switch (this) {
        PlanStatus.draft => 'مسودة',
        PlanStatus.pending => 'بانتظار الاعتماد',
        PlanStatus.approved => 'معتمدة',
        PlanStatus.rejected => 'مرفوضة',
        PlanStatus.archived => 'مؤرشفة',
      };
}

enum MilestoneStatus { onTrack, atRisk, delayed, completed, blocked }

extension MilestoneStatusX on MilestoneStatus {
  String get label => switch (this) {
        MilestoneStatus.onTrack => 'على المسار',
        MilestoneStatus.atRisk => 'معرّض للتأخر',
        MilestoneStatus.delayed => 'متأخر',
        MilestoneStatus.completed => 'مكتمل',
        MilestoneStatus.blocked => 'متعثر',
      };

  Color get color => switch (this) {
        MilestoneStatus.onTrack => const Color(0xFF3498DB),
        MilestoneStatus.atRisk => const Color(0xFFF39C12),
        MilestoneStatus.delayed => const Color(0xFFE67E22),
        MilestoneStatus.completed => const Color(0xFF2ECC71),
        MilestoneStatus.blocked => const Color(0xFFE74C3C),
      };
}

class Milestone {
  final String id;
  final String title;
  final String period;
  final double? target;
  double? actual;
  MilestoneStatus status;
  List<String> evidence;
  String? deviation;
  String? corrective;

  Milestone({
    required this.id,
    required this.title,
    required this.period,
    this.target,
    this.actual,
    this.status = MilestoneStatus.onTrack,
    List<String>? evidence,
    this.deviation,
    this.corrective,
  }) : evidence = evidence ?? [];

  /// الفرق بين الفعلي والمستهدف (لا يُحوَّل إلى درجة تقييم ذاتية)
  double? get variance => target == null || actual == null ? null : actual! - target!;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'period': period,
        'target': target,
        'actual': actual,
        'status': status.name,
        'evidence': evidence,
        'deviation': deviation,
        'corrective': corrective,
      };

  factory Milestone.fromJson(Map<String, dynamic> j) => Milestone(
        id: j['id'] as String,
        title: j['title'] as String,
        period: j['period'] as String? ?? '',
        target: (j['target'] as num?)?.toDouble(),
        actual: (j['actual'] as num?)?.toDouble(),
        status: MilestoneStatus.values.byName(j['status'] as String? ?? 'onTrack'),
        evidence: (j['evidence'] as List? ?? []).map((e) => '$e').toList(),
        deviation: j['deviation'] as String?,
        corrective: j['corrective'] as String?,
      );
}

class OpsPlan {
  final String id;
  final String companyId;
  PlanCategory category;
  int year;
  String title;
  String owner;
  String objectives;
  double? budget;
  PlanSegment segment;
  PlanStatus status;
  List<Milestone> milestones;
  final String createdBy;
  final DateTime createdAt;
  String? decidedBy;
  String? reason;

  OpsPlan({
    required this.id,
    required this.companyId,
    required this.category,
    required this.year,
    required this.title,
    required this.owner,
    this.objectives = '',
    this.budget,
    this.segment = PlanSegment.quarterly,
    this.status = PlanStatus.draft,
    List<Milestone>? milestones,
    required this.createdBy,
    required this.createdAt,
    this.decidedBy,
    this.reason,
  }) : milestones = milestones ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyId': companyId,
        'category': category.name,
        'year': year,
        'title': title,
        'owner': owner,
        'objectives': objectives,
        'budget': budget,
        'segment': segment.name,
        'status': status.name,
        'milestones': milestones.map((m) => m.toJson()).toList(),
        'createdBy': createdBy,
        'createdAt': _iso(createdAt),
        'decidedBy': decidedBy,
        'reason': reason,
      };

  factory OpsPlan.fromJson(Map<String, dynamic> j) => OpsPlan(
        id: j['id'] as String,
        companyId: j['companyId'] as String,
        category: PlanCategory.values.byName(j['category'] as String),
        year: (j['year'] as num).toInt(),
        title: j['title'] as String,
        owner: j['owner'] as String? ?? '',
        objectives: j['objectives'] as String? ?? '',
        budget: (j['budget'] as num?)?.toDouble(),
        segment: PlanSegment.values.byName(j['segment'] as String? ?? 'quarterly'),
        status: PlanStatus.values.byName(j['status'] as String? ?? 'draft'),
        milestones: (j['milestones'] as List? ?? []).map((e) => Milestone.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        createdBy: j['createdBy'] as String? ?? '',
        createdAt: _t(j['createdAt']),
        decidedBy: j['decidedBy'] as String?,
        reason: j['reason'] as String?,
      );
}

// ───────────── O16 المراسلات ─────────────

enum LetterStatus { draft, sent, delivered, failed, archived }

extension LetterStatusX on LetterStatus {
  String get label => switch (this) {
        LetterStatus.draft => 'مسودة',
        LetterStatus.sent => 'صادرة (مسجّلة)',
        LetterStatus.delivered => 'مستلمة',
        LetterStatus.failed => 'تعذّر التسليم',
        LetterStatus.archived => 'مؤرشفة',
      };
}

class Letter {
  final String id;
  final String companyId;
  final String reference;
  final bool outgoing;
  final DateTime date;
  String party;
  String subject;
  String body;
  String? relatedType;
  String? relatedId;
  String? relatedLabel;
  LetterStatus status;
  List<String> attachments;
  final String createdBy;

  /// المراسلة الرسمية: لا تُحذف ولا يُعدَّل نصها بعد إصدارها
  bool official;

  Letter({
    required this.id,
    required this.companyId,
    required this.reference,
    required this.outgoing,
    required this.date,
    required this.party,
    required this.subject,
    this.body = '',
    this.relatedType,
    this.relatedId,
    this.relatedLabel,
    this.status = LetterStatus.draft,
    List<String>? attachments,
    required this.createdBy,
    this.official = true,
  }) : attachments = attachments ?? [];

  /// بعد الإصدار يصبح النص مقفلاً
  bool get locked => status != LetterStatus.draft;

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyId': companyId,
        'reference': reference,
        'outgoing': outgoing,
        'date': _iso(date),
        'party': party,
        'subject': subject,
        'body': body,
        'relatedType': relatedType,
        'relatedId': relatedId,
        'relatedLabel': relatedLabel,
        'status': status.name,
        'attachments': attachments,
        'createdBy': createdBy,
        'official': official,
      };

  factory Letter.fromJson(Map<String, dynamic> j) => Letter(
        id: j['id'] as String,
        companyId: j['companyId'] as String,
        reference: j['reference'] as String,
        outgoing: j['outgoing'] as bool? ?? true,
        date: _t(j['date']),
        party: j['party'] as String? ?? '',
        subject: j['subject'] as String? ?? '',
        body: j['body'] as String? ?? '',
        relatedType: j['relatedType'] as String?,
        relatedId: j['relatedId'] as String?,
        relatedLabel: j['relatedLabel'] as String?,
        status: LetterStatus.values.byName(j['status'] as String? ?? 'draft'),
        attachments: (j['attachments'] as List? ?? []).map((e) => '$e').toList(),
        createdBy: j['createdBy'] as String? ?? '',
        official: j['official'] as bool? ?? true,
      );
}

// ───────────── O11 تنفيذ القرارات ─────────────

enum ExecStatus { pending, inProgress, completed, blocked }

extension ExecStatusX on ExecStatus {
  String get label => switch (this) {
        ExecStatus.pending => 'بانتظار التنفيذ',
        ExecStatus.inProgress => 'قيد التنفيذ',
        ExecStatus.completed => 'منفّذ',
        ExecStatus.blocked => 'متعثر',
      };

  Color get color => switch (this) {
        ExecStatus.pending => const Color(0xFFB7C0CF),
        ExecStatus.inProgress => const Color(0xFF3498DB),
        ExecStatus.completed => const Color(0xFF2ECC71),
        ExecStatus.blocked => const Color(0xFFE74C3C),
      };
}

/// قرار معتمد مشتق من سجلات الحوكمة (إصدار عقد، حسم نزاع، استثناء معتمد)
class ApprovedDecision {
  final String id;
  final String type;
  final String result;
  final DateTime effective;
  final String requiredAction;

  const ApprovedDecision(
      {required this.id, required this.type, required this.result, required this.effective, required this.requiredAction});
}

/// حالة تنفيذ قرار: لا تغيّر نتيجة القرار نفسه
class Execution {
  final String decisionId;
  String owner;
  DateTime? deadline;
  ExecStatus status;
  List<String> evidence;
  String? issue;
  DateTime updatedAt;

  Execution({
    required this.decisionId,
    this.owner = '',
    this.deadline,
    this.status = ExecStatus.pending,
    List<String>? evidence,
    this.issue,
    required this.updatedAt,
  }) : evidence = evidence ?? [];

  Map<String, dynamic> toJson() => {
        'decisionId': decisionId,
        'owner': owner,
        'deadline': deadline == null ? null : _iso(deadline!),
        'status': status.name,
        'evidence': evidence,
        'issue': issue,
        'updatedAt': _iso(updatedAt),
      };

  factory Execution.fromJson(Map<String, dynamic> j) => Execution(
        decisionId: j['decisionId'] as String,
        owner: j['owner'] as String? ?? '',
        deadline: j['deadline'] == null ? null : _t(j['deadline']),
        status: ExecStatus.values.byName(j['status'] as String? ?? 'pending'),
        evidence: (j['evidence'] as List? ?? []).map((e) => '$e').toList(),
        issue: j['issue'] as String?,
        updatedAt: _t(j['updatedAt']),
      );
}

// ───────────── O17 التنبيهات ─────────────

enum AlertStatus { open, acknowledged, escalated, resolved }

extension AlertStatusX on AlertStatus {
  String get label => switch (this) {
        AlertStatus.open => 'جديد',
        AlertStatus.acknowledged => 'تم الاطلاع',
        AlertStatus.escalated => 'مصعّد',
        AlertStatus.resolved => 'محلول',
      };
}

/// تنبيه تشغيلي مشتق من حالة العمليات والمهل؛ لا يحل محل سجل التدقيق والإشعارات الرسمية
class OpsAlert {
  final String id;
  final String type;
  final String title;
  final String detail;
  final DateTime created;
  final DateTime? deadline;
  final String relatedType;
  final String relatedId;
  final String role;

  const OpsAlert({
    required this.id,
    required this.type,
    required this.title,
    required this.detail,
    required this.created,
    this.deadline,
    required this.relatedType,
    required this.relatedId,
    required this.role,
  });
}

class AlertState {
  final AlertStatus status;
  final String? assignedRole;
  final DateTime? snoozeUntil;
  final DateTime at;

  const AlertState({required this.status, this.assignedRole, this.snoozeUntil, required this.at});

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'assignedRole': assignedRole,
        'snoozeUntil': snoozeUntil == null ? null : _iso(snoozeUntil!),
        'at': _iso(at),
      };

  factory AlertState.fromJson(Map<String, dynamic> j) => AlertState(
        status: AlertStatus.values.byName(j['status'] as String),
        assignedRole: j['assignedRole'] as String?,
        snoozeUntil: j['snoozeUntil'] == null ? null : _t(j['snoozeUntil']),
        at: _t(j['at']),
      );
}
