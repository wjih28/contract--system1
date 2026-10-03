import 'package:flutter/material.dart';

/// النزاعات (P18 / P19) وفق "مخطط تدفق العمل الرقمي لإدارة وتصفية نزاعات الشركاء":
/// رصد المحفز، ثم التسوية الودية (تفاوض ثم وساطة)، ثم كسر الجمود، ثم التحكيم، ثم التصفية.

/// مُطلق النزاع
enum DisputeTrigger { deadlock, violation, exitRequest, losses, other }

extension DisputeTriggerX on DisputeTrigger {
  String get label => switch (this) {
        DisputeTrigger.deadlock => 'جمود التصويت',
        DisputeTrigger.violation => 'تضارب مصالح أو خلط ذمم',
        DisputeTrigger.exitRequest => 'طلب تخارج',
        DisputeTrigger.losses => 'خسائر تتجاوز نصف رأس المال',
        DisputeTrigger.other => 'خلاف آخر بين الشركاء',
      };

  IconData get icon => switch (this) {
        DisputeTrigger.deadlock => Icons.block_rounded,
        DisputeTrigger.violation => Icons.gpp_bad_rounded,
        DisputeTrigger.exitRequest => Icons.logout_rounded,
        DisputeTrigger.losses => Icons.trending_down_rounded,
        DisputeTrigger.other => Icons.forum_rounded,
      };
}

/// مراحل المسار بالترتيب
enum DisputeStage { negotiation, mediation, deadlockBreak, arbitration, liquidation }

extension DisputeStageX on DisputeStage {
  String get label => switch (this) {
        DisputeStage.negotiation => 'التفاوض المباشر',
        DisputeStage.mediation => 'الوساطة والتوفيق',
        DisputeStage.deadlockBreak => 'كسر الجمود',
        DisputeStage.arbitration => 'التحكيم',
        DisputeStage.liquidation => 'التصفية',
      };

  String get hint => switch (this) {
        DisputeStage.negotiation => 'غرفة تفاوض بين الأطراف مع الاطلاع على السجلات. عند التوافق يُعتمد محضر صلح.',
        DisputeStage.mediation => 'يُحال الملف إلى جهة وساطة معتمدة. عند التوافق يصدر محضر صلح ملزم.',
        DisputeStage.deadlockBreak =>
          'عرض شراء مغلق وملزم لحصة الطرف الآخر، وله أن يبيع بالسعر أو يشتري حصة صاحب العرض بنفس السعر.',
        DisputeStage.arbitration => 'يُصدَّر ملف القضية إلى مركز التحكيم، وتُمنع القرارات الاستثنائية حتى صدور الحكم.',
        DisputeStage.liquidation => 'تُسدَّد الديون الممتازة ثم العادية، ويوزَّع الصافي على الشركاء بنسب حصصهم.',
      };
}

/// حالة التذكرة كما في الملف: نشطة (تسوية ودية)، بانتظار طرف، مصعّدة، محسومة، مغلقة
enum DisputeStatus { adrActive, awaitingParty, escalated, resolved, closed }

extension DisputeStatusX on DisputeStatus {
  String get label => switch (this) {
        DisputeStatus.adrActive => 'تسوية ودية جارية',
        DisputeStatus.awaitingParty => 'بانتظار رد طرف',
        DisputeStatus.escalated => 'مصعّد',
        DisputeStatus.resolved => 'محسوم',
        DisputeStatus.closed => 'مغلق',
      };

  Color get color => switch (this) {
        DisputeStatus.adrActive => const Color(0xFF3498DB),
        DisputeStatus.awaitingParty => const Color(0xFFF39C12),
        DisputeStatus.escalated => const Color(0xFFE74C3C),
        DisputeStatus.resolved => const Color(0xFF2ECC71),
        DisputeStatus.closed => const Color(0xFF7C8CA3),
      };

  bool get open => this != DisputeStatus.resolved && this != DisputeStatus.closed;
}

/// المهل الافتراضية من مخطط النزاعات
class DisputeSettings {
  static const negotiationDays = 14;
  static const mediationDays = 30;
  static const deadlockBreakDays = 14;
  static const buyOutHours = 72;
}

/// نوع قيد في الخط الزمني للنزاع. أحداث النظام تختلف عن مدخلات الأطراف.
enum EntryKind { system, response, evidence, settlement, offer, choice, award }

extension EntryKindX on EntryKind {
  String get label => switch (this) {
        EntryKind.system => 'حدث نظام',
        EntryKind.response => 'رد',
        EntryKind.evidence => 'دليل',
        EntryKind.settlement => 'محضر صلح',
        EntryKind.offer => 'عرض شراء',
        EntryKind.choice => 'اختيار',
        EntryKind.award => 'حكم',
      };

  IconData get icon => switch (this) {
        EntryKind.system => Icons.settings_suggest_rounded,
        EntryKind.response => Icons.chat_bubble_outline_rounded,
        EntryKind.evidence => Icons.attach_file_rounded,
        EntryKind.settlement => Icons.handshake_rounded,
        EntryKind.offer => Icons.local_offer_rounded,
        EntryKind.choice => Icons.call_split_rounded,
        EntryKind.award => Icons.gavel_rounded,
      };
}

class DisputeEntry {
  final EntryKind kind;
  final String authorId; // 'system' لأحداث النظام
  final String authorName;
  final String text;
  final DateTime at;
  final DisputeStage stage;
  final String? evidenceRef;

  const DisputeEntry({
    required this.kind,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.at,
    required this.stage,
    this.evidenceRef,
  });

  bool get isSystem => kind == EntryKind.system;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'authorId': authorId,
        'authorName': authorName,
        'text': text,
        'at': at.toUtc().toIso8601String(),
        'stage': stage.name,
        'evidenceRef': evidenceRef,
      };

  factory DisputeEntry.fromJson(Map<String, dynamic> j) => DisputeEntry(
        kind: EntryKind.values.byName(j['kind'] as String),
        authorId: j['authorId'] as String? ?? '',
        authorName: j['authorName'] as String? ?? '',
        text: j['text'] as String? ?? '',
        at: DateTime.tryParse(j['at']?.toString() ?? '') ?? DateTime.now(),
        stage: DisputeStage.values.byName(j['stage'] as String? ?? 'negotiation'),
        evidenceRef: j['evidenceRef'] as String?,
      );
}

/// محضر صلح مقترح: يُعتمد بموافقة كل الأطراف. إن غيّر شروط العقد يمر عبر إصدار جديد.
class Settlement {
  final String text;
  final String proposedBy;
  final DateTime at;
  final bool requiresAmendment;
  final Map<String, DateTime> approvals;

  const Settlement({
    required this.text,
    required this.proposedBy,
    required this.at,
    this.requiresAmendment = false,
    this.approvals = const {},
  });

  Settlement approvedBy(String memberId, DateTime at) =>
      Settlement(text: text, proposedBy: proposedBy, at: this.at, requiresAmendment: requiresAmendment, approvals: {
        ...approvals,
        memberId: at,
      });

  Map<String, dynamic> toJson() => {
        'text': text,
        'proposedBy': proposedBy,
        'at': at.toUtc().toIso8601String(),
        'requiresAmendment': requiresAmendment,
        'approvals': approvals.map((k, v) => MapEntry(k, v.toUtc().toIso8601String())),
      };

  factory Settlement.fromJson(Map<String, dynamic> j) => Settlement(
        text: j['text'] as String,
        proposedBy: j['proposedBy'] as String,
        at: DateTime.tryParse(j['at']?.toString() ?? '') ?? DateTime.now(),
        requiresAmendment: j['requiresAmendment'] as bool? ?? false,
        approvals: Map<String, dynamic>.from(j['approvals'] as Map? ?? {})
            .map((k, v) => MapEntry(k, DateTime.tryParse(v.toString()) ?? DateTime.now())),
      );
}

/// عرض الشراء المغلق (Texas Shootout): سعر حصة الطرف الآخر كاملة، ومهلة للاختيار.
/// يُسجَّل كدليل فقط، ولا يجري أي دفع داخل التطبيق.
class BuyOutOffer {
  final String offerorId;
  final String targetId;
  final double price;
  final DateTime at;
  final DateTime deadline;
  final String? choice; // 'sell' يبيع الطرف حصته / 'buy' يشتري حصة صاحب العرض
  final DateTime? decidedAt;

  const BuyOutOffer({
    required this.offerorId,
    required this.targetId,
    required this.price,
    required this.at,
    required this.deadline,
    this.choice,
    this.decidedAt,
  });

  bool get decided => choice != null;

  BuyOutOffer decide(String c, DateTime at) => BuyOutOffer(
      offerorId: offerorId, targetId: targetId, price: price, at: this.at, deadline: deadline, choice: c, decidedAt: at);

  /// المشتري والبائع بعد الاختيار
  String? get buyerId => choice == null ? null : (choice == 'sell' ? offerorId : targetId);
  String? get sellerId => choice == null ? null : (choice == 'sell' ? targetId : offerorId);

  Map<String, dynamic> toJson() => {
        'offerorId': offerorId,
        'targetId': targetId,
        'price': price,
        'at': at.toUtc().toIso8601String(),
        'deadline': deadline.toUtc().toIso8601String(),
        'choice': choice,
        'decidedAt': decidedAt?.toUtc().toIso8601String(),
      };

  factory BuyOutOffer.fromJson(Map<String, dynamic> j) => BuyOutOffer(
        offerorId: j['offerorId'] as String,
        targetId: j['targetId'] as String,
        price: (j['price'] as num).toDouble(),
        at: DateTime.tryParse(j['at']?.toString() ?? '') ?? DateTime.now(),
        deadline: DateTime.tryParse(j['deadline']?.toString() ?? '') ?? DateTime.now(),
        choice: j['choice'] as String?,
        decidedAt: j['decidedAt'] == null ? null : DateTime.tryParse(j['decidedAt'].toString()),
      );
}

/// منطوق حكم التحكيم
enum AwardOutcome { equityChange, dissolve, dismiss }

extension AwardOutcomeX on AwardOutcome {
  String get label => switch (this) {
        AwardOutcome.equityChange => 'تعديل الملكية',
        AwardOutcome.dissolve => 'فض الشراكة والتصفية',
        AwardOutcome.dismiss => 'رفض الدعوى واستمرار العقد',
      };
}

/// دين على الشركة في التصفية. الديون الممتازة تُسدَّد أولاً.
class LiquidationDebt {
  final String creditor;
  final double amount;
  final bool preferred;

  const LiquidationDebt({required this.creditor, required this.amount, this.preferred = false});

  Map<String, dynamic> toJson() => {'creditor': creditor, 'amount': amount, 'preferred': preferred};

  factory LiquidationDebt.fromJson(Map<String, dynamic> j) => LiquidationDebt(
        creditor: j['creditor'] as String,
        amount: (j['amount'] as num).toDouble(),
        preferred: j['preferred'] as bool? ?? false,
      );
}

/// جدول التصفية المحسوب: ما يُسدَّد لكل دائن، والصافي، ونصيب كل شريك
class LiquidationPlan {
  final double assets;
  final List<(LiquidationDebt, double)> payments; // الدين والمبلغ المسدد منه
  final double net;
  final Map<String, double> distribution;

  const LiquidationPlan({required this.assets, required this.payments, required this.net, required this.distribution});

  double get unpaid => payments.fold(0, (a, p) => a + (p.$1.amount - p.$2));
}

class Dispute {
  final String id;
  final String companyId;
  final DisputeTrigger trigger;
  final String issue;
  final String? relatedType; // clause / violation / transaction
  final String? relatedId;
  final int contractVersion;
  final String openedBy; // معرّف العضو أو 'system'
  final DateTime openedAt;
  final List<String> parties;

  DisputeStage stage;
  DateTime stageStartedAt;
  DateTime deadline;
  DisputeStatus status;
  List<DisputeEntry> entries;

  /// موافقات الأطراف على إنهاء المرحلة الحالية مبكراً دون اتفاق
  Set<String> escalationConsents;
  Settlement? settlement;
  String? mediator;
  String? arbitrationCenter;
  String? caseFileHash;
  BuyOutOffer? buyOut;
  String? awardText;
  AwardOutcome? awardOutcome;
  String? awardRef;

  /// الحصص بعد الحسم (من الشراء أو الحكم)؛ تُطبَّق عبر إصدار جديد لجدول الحصص
  Map<String, double>? equityAfter;
  String? liquidator;
  double? liquidationAssets;
  List<LiquidationDebt> debts;
  String? outcome;
  DateTime? resolvedAt;

  /// إصدار العقد الذي نفّذ الحسم (تعديل بنود أو جدول حصص)
  String? amendmentRef;

  Dispute({
    required this.id,
    required this.companyId,
    required this.trigger,
    required this.issue,
    this.relatedType,
    this.relatedId,
    required this.contractVersion,
    required this.openedBy,
    required this.openedAt,
    required this.parties,
    this.stage = DisputeStage.negotiation,
    required this.stageStartedAt,
    required this.deadline,
    this.status = DisputeStatus.adrActive,
    List<DisputeEntry>? entries,
    Set<String>? escalationConsents,
    this.settlement,
    this.mediator,
    this.arbitrationCenter,
    this.caseFileHash,
    this.buyOut,
    this.awardText,
    this.awardOutcome,
    this.awardRef,
    this.equityAfter,
    this.liquidator,
    this.liquidationAssets,
    List<LiquidationDebt>? debts,
    this.outcome,
    this.resolvedAt,
    this.amendmentRef,
  })  : entries = entries ?? [],
        escalationConsents = escalationConsents ?? {},
        debts = debts ?? [];

  bool get isOpen => status.open;

  /// يتطلب الحسم إصداراً جديداً للعقد (تغيير ملكية أو شروط) لم يُنشأ بعد
  bool get needsAmendment =>
      status == DisputeStatus.resolved &&
      amendmentRef == null &&
      (equityAfter != null || (settlement?.requiresAmendment ?? false));

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyId': companyId,
        'trigger': trigger.name,
        'issue': issue,
        'relatedType': relatedType,
        'relatedId': relatedId,
        'contractVersion': contractVersion,
        'openedBy': openedBy,
        'openedAt': openedAt.toUtc().toIso8601String(),
        'parties': parties,
        'stage': stage.name,
        'stageStartedAt': stageStartedAt.toUtc().toIso8601String(),
        'deadline': deadline.toUtc().toIso8601String(),
        'status': status.name,
        'entries': entries.map((e) => e.toJson()).toList(),
        'escalationConsents': escalationConsents.toList(),
        'settlement': settlement?.toJson(),
        'mediator': mediator,
        'arbitrationCenter': arbitrationCenter,
        'caseFileHash': caseFileHash,
        'buyOut': buyOut?.toJson(),
        'awardText': awardText,
        'awardOutcome': awardOutcome?.name,
        'awardRef': awardRef,
        'equityAfter': equityAfter,
        'liquidator': liquidator,
        'liquidationAssets': liquidationAssets,
        'debts': debts.map((d) => d.toJson()).toList(),
        'outcome': outcome,
        'resolvedAt': resolvedAt?.toUtc().toIso8601String(),
        'amendmentRef': amendmentRef,
      };

  factory Dispute.fromJson(Map<String, dynamic> j) {
    DateTime t(Object? v) => DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();
    Map<String, dynamic>? m(Object? v) => v == null ? null : Map<String, dynamic>.from(v as Map);
    return Dispute(
      id: j['id'] as String,
      companyId: j['companyId'] as String,
      trigger: DisputeTrigger.values.byName(j['trigger'] as String),
      issue: j['issue'] as String? ?? '',
      relatedType: j['relatedType'] as String?,
      relatedId: j['relatedId'] as String?,
      contractVersion: (j['contractVersion'] as num?)?.toInt() ?? 1,
      openedBy: j['openedBy'] as String? ?? '',
      openedAt: t(j['openedAt']),
      parties: (j['parties'] as List? ?? []).map((e) => e as String).toList(),
      stage: DisputeStage.values.byName(j['stage'] as String? ?? 'negotiation'),
      stageStartedAt: t(j['stageStartedAt']),
      deadline: t(j['deadline']),
      status: DisputeStatus.values.byName(j['status'] as String? ?? 'adrActive'),
      entries: (j['entries'] as List? ?? []).map((e) => DisputeEntry.fromJson(m(e)!)).toList(),
      escalationConsents: (j['escalationConsents'] as List? ?? []).map((e) => e as String).toSet(),
      settlement: m(j['settlement']) == null ? null : Settlement.fromJson(m(j['settlement'])!),
      mediator: j['mediator'] as String?,
      arbitrationCenter: j['arbitrationCenter'] as String?,
      caseFileHash: j['caseFileHash'] as String?,
      buyOut: m(j['buyOut']) == null ? null : BuyOutOffer.fromJson(m(j['buyOut'])!),
      awardText: j['awardText'] as String?,
      awardOutcome: j['awardOutcome'] == null ? null : AwardOutcome.values.byName(j['awardOutcome'] as String),
      awardRef: j['awardRef'] as String?,
      equityAfter: m(j['equityAfter'])?.map((k, v) => MapEntry(k, (v as num).toDouble())),
      liquidator: j['liquidator'] as String?,
      liquidationAssets: (j['liquidationAssets'] as num?)?.toDouble(),
      debts: (j['debts'] as List? ?? []).map((e) => LiquidationDebt.fromJson(m(e)!)).toList(),
      outcome: j['outcome'] as String?,
      resolvedAt: j['resolvedAt'] == null ? null : t(j['resolvedAt']),
      amendmentRef: j['amendmentRef'] as String?,
    );
  }
}
