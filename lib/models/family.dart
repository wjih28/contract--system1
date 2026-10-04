import 'package:flutter/material.dart';

import 'questionnaire.dart';

/// الحوكمة العائلية (المرحلة 6). وحدة اختيارية للشركات العائلية، منفصلة عن عقد التأسيس:
/// الدستور العائلي بإصداراته، والأفراد والورثة، وتوزيع الأرباح، والخلافة، والقرارات العائلية.
/// أنصبة الورثة تُدخل من وثيقة حصر الوراثة الرسمية ولا يحسبها التطبيق.

DateTime _t(Object? v) => DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();
String _iso(DateTime d) => d.toUtc().toIso8601String();
Map<String, double> _dm(Object? v) =>
    Map<String, dynamic>.from(v as Map? ?? {}).map((k, x) => MapEntry(k, (x as num).toDouble()));

// ───────────── R10 الدستور العائلي ─────────────

enum ConstitutionStatus { draft, pendingApproval, current, archived }

extension ConstitutionStatusX on ConstitutionStatus {
  String get label => switch (this) {
        ConstitutionStatus.draft => 'مسودة تعديل',
        ConstitutionStatus.pendingApproval => 'بانتظار القرار العائلي',
        ConstitutionStatus.current => 'الساري',
        ConstitutionStatus.archived => 'مؤرشف',
      };
}

/// نموذج الأوزان في القرارات العائلية
enum WeightMode { equity, custom }

extension WeightModeX on WeightMode {
  String get label => this == WeightMode.equity ? 'حسب نسب الملكية' : 'أوزان يحددها الدستور';
}

/// قاعدة توزيع الأرباح العائلية
enum DistributionRule { equity, heirShares, custom }

extension DistributionRuleX on DistributionRule {
  String get label => switch (this) {
        DistributionRule.equity => 'حسب نسب الملكية في العقد',
        DistributionRule.heirShares => 'حسب أنصبة حصر الوراثة المعتمد',
        DistributionRule.custom => 'نسب يحددها الدستور',
      };
}

class ConstitutionSection {
  final String title;
  final String text;
  const ConstitutionSection(this.title, this.text);
  Map<String, dynamic> toJson() => {'title': title, 'text': text};
  factory ConstitutionSection.fromJson(Map<String, dynamic> j) => ConstitutionSection(j['title'] as String, j['text'] as String? ?? '');
}

class Constitution {
  final String id;
  final String companyId;
  final int version;
  ConstitutionStatus status;
  List<ConstitutionSection> sections;
  WeightMode weightMode;
  Map<String, double> customWeights; // العضو ← الوزن
  DistributionRule distributionRule;
  Map<String, double> customShares; // الفرد ← النسبة
  /// عتبة القرارات العائلية العادية، وعتبة تعديل الدستور (أعلى)
  double threshold;
  double amendmentThreshold;
  final String createdBy;
  final DateTime createdAt;
  DateTime? effectiveAt;
  String? decisionRef;
  String? changeSummary;

  Constitution({
    required this.id,
    required this.companyId,
    required this.version,
    this.status = ConstitutionStatus.draft,
    required this.sections,
    this.weightMode = WeightMode.equity,
    Map<String, double>? customWeights,
    this.distributionRule = DistributionRule.equity,
    Map<String, double>? customShares,
    this.threshold = 50.01,
    this.amendmentThreshold = 66.67,
    required this.createdBy,
    required this.createdAt,
    this.effectiveAt,
    this.decisionRef,
    this.changeSummary,
  })  : customWeights = customWeights ?? {},
        customShares = customShares ?? {};

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyId': companyId,
        'version': version,
        'status': status.name,
        'sections': sections.map((s) => s.toJson()).toList(),
        'weightMode': weightMode.name,
        'customWeights': customWeights,
        'distributionRule': distributionRule.name,
        'customShares': customShares,
        'threshold': threshold,
        'amendmentThreshold': amendmentThreshold,
        'createdBy': createdBy,
        'createdAt': _iso(createdAt),
        'effectiveAt': effectiveAt == null ? null : _iso(effectiveAt!),
        'decisionRef': decisionRef,
        'changeSummary': changeSummary,
      };

  factory Constitution.fromJson(Map<String, dynamic> j) => Constitution(
        id: j['id'] as String,
        companyId: j['companyId'] as String,
        version: (j['version'] as num).toInt(),
        status: ConstitutionStatus.values.byName(j['status'] as String),
        sections: (j['sections'] as List? ?? []).map((e) => ConstitutionSection.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        weightMode: WeightMode.values.byName(j['weightMode'] as String? ?? 'equity'),
        customWeights: _dm(j['customWeights']),
        distributionRule: DistributionRule.values.byName(j['distributionRule'] as String? ?? 'equity'),
        customShares: _dm(j['customShares']),
        threshold: (j['threshold'] as num?)?.toDouble() ?? 50.01,
        amendmentThreshold: (j['amendmentThreshold'] as num?)?.toDouble() ?? 66.67,
        createdBy: j['createdBy'] as String? ?? '',
        createdAt: _t(j['createdAt']),
        effectiveAt: j['effectiveAt'] == null ? null : _t(j['effectiveAt']),
        decisionRef: j['decisionRef'] as String?,
        changeSummary: j['changeSummary'] as String?,
      );

  /// أقسام افتتاحية لمسودة الدستور الأول
  static const starterSections = [
    ConstitutionSection('الرؤية والقيم', 'تلتزم العائلة بالحفاظ على وحدة الملكية واستمرار النشاط عبر الأجيال.'),
    ConstitutionSection('مجلس العائلة', 'يتكون من الشركاء المؤسسين، ويجتمع دورياً، ويتولى الوساطة في نزاعات العائلة قبل أي مسار آخر.'),
    ConstitutionSection('توظيف أفراد العائلة', 'يُعيَّن أفراد العائلة في الشركة وفق الكفاءة وبالشروط نفسها المطبقة على غيرهم.'),
    ConstitutionSection('توزيع الأرباح', 'تُوزَّع الأرباح العائلية دورياً وفق القاعدة المعتمدة في هذا الدستور، بعد الاحتياطيات النظامية.'),
    ConstitutionSection('الخلافة', 'لا تبدأ الخلافة إلا بحدث موثَّق، وتُنفَّذ أنصبة الورثة وفق حصر الوراثة الرسمي.'),
  ];
}

// ───────────── R11 الأفراد والورثة ─────────────

enum SuccessionRole { founder, heir, successor, member }

extension SuccessionRoleX on SuccessionRole {
  String get label => switch (this) {
        SuccessionRole.founder => 'مؤسس',
        SuccessionRole.heir => 'وارث',
        SuccessionRole.successor => 'خلف معيَّن',
        SuccessionRole.member => 'فرد من العائلة',
      };
}

class FamilyPerson {
  final String id;
  final String companyId;
  String name;
  String relation; // صلة القرابة كما تُكتب (ابن، بنت، زوجة، أخ...)
  String? parentId;
  int generation;
  bool alive;
  String? memberId; // عضو في التطبيق (شريك أو فرد مدعو)
  SuccessionRole role;
  String notes;

  FamilyPerson({
    required this.id,
    required this.companyId,
    required this.name,
    required this.relation,
    this.parentId,
    this.generation = 1,
    this.alive = true,
    this.memberId,
    this.role = SuccessionRole.member,
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyId': companyId,
        'name': name,
        'relation': relation,
        'parentId': parentId,
        'generation': generation,
        'alive': alive,
        'memberId': memberId,
        'role': role.name,
        'notes': notes,
      };

  factory FamilyPerson.fromJson(Map<String, dynamic> j) => FamilyPerson(
        id: j['id'] as String,
        companyId: j['companyId'] as String,
        name: j['name'] as String,
        relation: j['relation'] as String? ?? '',
        parentId: j['parentId'] as String?,
        generation: (j['generation'] as num?)?.toInt() ?? 1,
        alive: j['alive'] as bool? ?? true,
        memberId: j['memberId'] as String?,
        role: SuccessionRole.values.byName(j['role'] as String? ?? 'member'),
        notes: j['notes'] as String? ?? '',
      );
}

enum RecordStatus { draft, pendingApproval, approved, rejected }

extension RecordStatusX on RecordStatus {
  String get label => switch (this) {
        RecordStatus.draft => 'مسودة',
        RecordStatus.pendingApproval => 'بانتظار القرار العائلي',
        RecordStatus.approved => 'معتمد',
        RecordStatus.rejected => 'مرفوض',
      };
}

/// وثيقة حصر الوراثة الرسمية: الأنصبة كما وردت فيها، ويعتمدها قرار عائلي
class InheritanceDeed {
  final String id;
  final String companyId;
  final String deceasedId;
  final String reference;
  final String court;
  final DateTime date;
  final Map<String, double> shares; // الفرد ← النصيب من 100
  RecordStatus status;
  String? decisionRef;

  InheritanceDeed({
    required this.id,
    required this.companyId,
    required this.deceasedId,
    required this.reference,
    required this.court,
    required this.date,
    required this.shares,
    this.status = RecordStatus.draft,
    this.decisionRef,
  });

  double get total => shares.values.fold(0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyId': companyId,
        'deceasedId': deceasedId,
        'reference': reference,
        'court': court,
        'date': _iso(date),
        'shares': shares,
        'status': status.name,
        'decisionRef': decisionRef,
      };

  factory InheritanceDeed.fromJson(Map<String, dynamic> j) => InheritanceDeed(
        id: j['id'] as String,
        companyId: j['companyId'] as String,
        deceasedId: j['deceasedId'] as String,
        reference: j['reference'] as String,
        court: j['court'] as String? ?? '',
        date: _t(j['date']),
        shares: _dm(j['shares']),
        status: RecordStatus.values.byName(j['status'] as String? ?? 'draft'),
        decisionRef: j['decisionRef'] as String?,
      );
}

// ───────────── R12 توزيع الأرباح ─────────────

enum DistributionStatus { draft, pendingApproval, approved, executed, rejected, disputed }

extension DistributionStatusX on DistributionStatus {
  String get label => switch (this) {
        DistributionStatus.draft => 'مسودة',
        DistributionStatus.pendingApproval => 'بانتظار القرار العائلي',
        DistributionStatus.approved => 'معتمد',
        DistributionStatus.executed => 'منفّذ',
        DistributionStatus.rejected => 'مرفوض',
        DistributionStatus.disputed => 'محل نزاع',
      };

  Color get color => switch (this) {
        DistributionStatus.draft => const Color(0xFFB7C0CF),
        DistributionStatus.pendingApproval => const Color(0xFF3498DB),
        DistributionStatus.approved => const Color(0xFF2ECC71),
        DistributionStatus.executed => const Color(0xFF1ABC9C),
        DistributionStatus.rejected => const Color(0xFF7C8CA3),
        DistributionStatus.disputed => const Color(0xFFE74C3C),
      };
}

class FamilyDistribution {
  final String id;
  final String companyId;
  final String period;
  final double available;
  final AppCurrency currency;
  final DistributionRule rule;
  final int constitutionVersion;
  final Map<String, double> allocations; // المستفيد ← المبلغ
  DistributionStatus status;
  String? decisionRef;
  DateTime? executedAt;
  String? executionRef;
  final String createdBy;
  final DateTime createdAt;

  FamilyDistribution({
    required this.id,
    required this.companyId,
    required this.period,
    required this.available,
    required this.currency,
    required this.rule,
    required this.constitutionVersion,
    required this.allocations,
    this.status = DistributionStatus.draft,
    this.decisionRef,
    this.executedAt,
    this.executionRef,
    required this.createdBy,
    required this.createdAt,
  });

  /// المعتمد والمنفّذ لا يتغيران
  bool get immutable => status == DistributionStatus.approved || status == DistributionStatus.executed;

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyId': companyId,
        'period': period,
        'available': available,
        'currency': currency.name,
        'rule': rule.name,
        'constitutionVersion': constitutionVersion,
        'allocations': allocations,
        'status': status.name,
        'decisionRef': decisionRef,
        'executedAt': executedAt == null ? null : _iso(executedAt!),
        'executionRef': executionRef,
        'createdBy': createdBy,
        'createdAt': _iso(createdAt),
      };

  factory FamilyDistribution.fromJson(Map<String, dynamic> j) => FamilyDistribution(
        id: j['id'] as String,
        companyId: j['companyId'] as String,
        period: j['period'] as String,
        available: (j['available'] as num).toDouble(),
        currency: AppCurrency.values.byName(j['currency'] as String),
        rule: DistributionRule.values.byName(j['rule'] as String),
        constitutionVersion: (j['constitutionVersion'] as num?)?.toInt() ?? 1,
        allocations: _dm(j['allocations']),
        status: DistributionStatus.values.byName(j['status'] as String? ?? 'draft'),
        decisionRef: j['decisionRef'] as String?,
        executedAt: j['executedAt'] == null ? null : _t(j['executedAt']),
        executionRef: j['executionRef'] as String?,
        createdBy: j['createdBy'] as String? ?? '',
        createdAt: _t(j['createdAt']),
      );
}

// ───────────── R13 الخلافة ─────────────

enum SuccessionEvent { death, incapacity, resignation }

extension SuccessionEventX on SuccessionEvent {
  String get label => switch (this) {
        SuccessionEvent.death => 'وفاة',
        SuccessionEvent.incapacity => 'عجز أو فقدان أهلية',
        SuccessionEvent.resignation => 'تنازل أو اعتزال',
      };
}

enum SuccessionStatus { pendingEvidence, pendingApproval, effective, rejected, disputed }

extension SuccessionStatusX on SuccessionStatus {
  String get label => switch (this) {
        SuccessionStatus.pendingEvidence => 'بانتظار الأدلة',
        SuccessionStatus.pendingApproval => 'بانتظار القرار العائلي',
        SuccessionStatus.effective => 'نافذة',
        SuccessionStatus.rejected => 'مرفوضة',
        SuccessionStatus.disputed => 'محل نزاع',
      };
}

class SuccessionCase {
  final String id;
  final String companyId;
  final SuccessionEvent event;
  final String subjectId; // الفرد صاحب الحدث
  final DateTime eventDate;
  final String currentAuthority;
  String successorId;
  List<String> evidence;
  SuccessionStatus status;
  String? decisionRef;
  String? deedRef;
  String? amendmentRef;

  /// ممثل واحد عن الورثة لممارسة حقوق التصويت (القانون اليمني)
  String? representativeId;
  final String createdBy;
  final DateTime createdAt;
  DateTime? effectiveAt;

  SuccessionCase({
    required this.id,
    required this.companyId,
    required this.event,
    required this.subjectId,
    required this.eventDate,
    required this.currentAuthority,
    required this.successorId,
    List<String>? evidence,
    this.status = SuccessionStatus.pendingEvidence,
    this.decisionRef,
    this.deedRef,
    this.amendmentRef,
    this.representativeId,
    required this.createdBy,
    required this.createdAt,
    this.effectiveAt,
  }) : evidence = evidence ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyId': companyId,
        'event': event.name,
        'subjectId': subjectId,
        'eventDate': _iso(eventDate),
        'currentAuthority': currentAuthority,
        'successorId': successorId,
        'evidence': evidence,
        'status': status.name,
        'decisionRef': decisionRef,
        'deedRef': deedRef,
        'amendmentRef': amendmentRef,
        'representativeId': representativeId,
        'createdBy': createdBy,
        'createdAt': _iso(createdAt),
        'effectiveAt': effectiveAt == null ? null : _iso(effectiveAt!),
      };

  factory SuccessionCase.fromJson(Map<String, dynamic> j) => SuccessionCase(
        id: j['id'] as String,
        companyId: j['companyId'] as String,
        event: SuccessionEvent.values.byName(j['event'] as String),
        subjectId: j['subjectId'] as String,
        eventDate: _t(j['eventDate']),
        currentAuthority: j['currentAuthority'] as String? ?? '',
        successorId: j['successorId'] as String? ?? '',
        evidence: (j['evidence'] as List? ?? []).map((e) => '$e').toList(),
        status: SuccessionStatus.values.byName(j['status'] as String? ?? 'pendingEvidence'),
        decisionRef: j['decisionRef'] as String?,
        deedRef: j['deedRef'] as String?,
        amendmentRef: j['amendmentRef'] as String?,
        representativeId: j['representativeId'] as String?,
        createdBy: j['createdBy'] as String? ?? '',
        createdAt: _t(j['createdAt']),
        effectiveAt: j['effectiveAt'] == null ? null : _t(j['effectiveAt']),
      );
}

// ───────────── R14 القرارات العائلية ─────────────

enum FamilyDecisionType { constitution, distribution, succession, deed, other }

extension FamilyDecisionTypeX on FamilyDecisionType {
  String get label => switch (this) {
        FamilyDecisionType.constitution => 'تعديل الدستور العائلي',
        FamilyDecisionType.distribution => 'اعتماد توزيع أرباح',
        FamilyDecisionType.succession => 'اعتماد خلافة',
        FamilyDecisionType.deed => 'اعتماد حصر وراثة',
        FamilyDecisionType.other => 'قرار عائلي',
      };
}

enum FamilyDecisionStatus { open, approved, rejected, expired }

extension FamilyDecisionStatusX on FamilyDecisionStatus {
  String get label => switch (this) {
        FamilyDecisionStatus.open => 'مفتوح للتصويت',
        FamilyDecisionStatus.approved => 'معتمد',
        FamilyDecisionStatus.rejected => 'مرفوض',
        FamilyDecisionStatus.expired => 'انتهت المهلة دون اعتماد',
      };
}

class FamilyVote {
  final bool approve;
  final DateTime at;
  final String method;
  const FamilyVote({required this.approve, required this.at, required this.method});
  Map<String, dynamic> toJson() => {'approve': approve, 'at': _iso(at), 'method': method};
  factory FamilyVote.fromJson(Map<String, dynamic> j) =>
      FamilyVote(approve: j['approve'] as bool, at: _t(j['at']), method: j['method'] as String? ?? 'manual');
}

class FamilyDecision {
  final String id;
  final String companyId;
  final String title;
  final String details;
  final FamilyDecisionType type;
  final String? refId;
  final double threshold;
  final double quorum;
  final Map<String, double> weights; // لقطة الأوزان عند فتح القرار
  final DateTime deadline;
  Map<String, FamilyVote> votes;
  FamilyDecisionStatus status;
  final String createdBy;
  final DateTime createdAt;
  DateTime? decidedAt;

  FamilyDecision({
    required this.id,
    required this.companyId,
    required this.title,
    this.details = '',
    required this.type,
    this.refId,
    required this.threshold,
    this.quorum = 50,
    required this.weights,
    required this.deadline,
    Map<String, FamilyVote>? votes,
    this.status = FamilyDecisionStatus.open,
    required this.createdBy,
    required this.createdAt,
    this.decidedAt,
  }) : votes = votes ?? {};

  double get totalWeight => weights.values.fold(0, (a, b) => a + b);
  double share(bool approve) {
    final t = totalWeight;
    if (t == 0) return 0;
    return weights.entries.where((e) => votes[e.key]?.approve == approve).fold(0.0, (a, e) => a + e.value) / t * 100;
  }

  double get participation => share(true) + share(false);

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyId': companyId,
        'title': title,
        'details': details,
        'type': type.name,
        'refId': refId,
        'threshold': threshold,
        'quorum': quorum,
        'weights': weights,
        'deadline': _iso(deadline),
        'votes': votes.map((k, v) => MapEntry(k, v.toJson())),
        'status': status.name,
        'createdBy': createdBy,
        'createdAt': _iso(createdAt),
        'decidedAt': decidedAt == null ? null : _iso(decidedAt!),
      };

  factory FamilyDecision.fromJson(Map<String, dynamic> j) => FamilyDecision(
        id: j['id'] as String,
        companyId: j['companyId'] as String,
        title: j['title'] as String,
        details: j['details'] as String? ?? '',
        type: FamilyDecisionType.values.byName(j['type'] as String),
        refId: j['refId'] as String?,
        threshold: (j['threshold'] as num).toDouble(),
        quorum: (j['quorum'] as num?)?.toDouble() ?? 50,
        weights: _dm(j['weights']),
        deadline: _t(j['deadline']),
        votes: Map<String, dynamic>.from(j['votes'] as Map? ?? {})
            .map((k, v) => MapEntry(k, FamilyVote.fromJson(Map<String, dynamic>.from(v as Map)))),
        status: FamilyDecisionStatus.values.byName(j['status'] as String? ?? 'open'),
        createdBy: j['createdBy'] as String? ?? '',
        createdAt: _t(j['createdAt']),
        decidedAt: j['decidedAt'] == null ? null : _t(j['decidedAt']),
      );
}
