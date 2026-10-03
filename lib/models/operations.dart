import 'package:flutter/material.dart';

import 'questionnaire.dart';

/// فئة العملية المالية: تحدد أي القواعد تنطبق عليها
enum TxCategory { expense, purchase, hospitality, contract, personalAdvance, salaryChange, revenue }

extension TxCategoryX on TxCategory {
  String get label => switch (this) {
        TxCategory.expense => 'مصروف تشغيلي',
        TxCategory.purchase => 'مشتريات',
        TxCategory.hospitality => 'ضيافة',
        TxCategory.contract => 'عقد أو التزام مالي',
        TxCategory.personalAdvance => 'سلفة شخصية',
        TxCategory.salaryChange => 'تعديل راتب أو مزايا',
        TxCategory.revenue => 'إيراد',
      };

  IconData get icon => switch (this) {
        TxCategory.expense => Icons.receipt_rounded,
        TxCategory.purchase => Icons.shopping_bag_rounded,
        TxCategory.hospitality => Icons.local_cafe_rounded,
        TxCategory.contract => Icons.handshake_rounded,
        TxCategory.personalAdvance => Icons.person_remove_rounded,
        TxCategory.salaryChange => Icons.payments_rounded,
        TxCategory.revenue => Icons.trending_up_rounded,
      };

  /// المصروفات تُحتسب ضمن السقف الشهري، والإيرادات لا
  bool get isOutflow => this != TxCategory.revenue;
}

/// مصدر العملية
enum TxSource { manual, import, api }

extension TxSourceX on TxSource {
  String get label => switch (this) {
        TxSource.manual => 'إدخال يدوي',
        TxSource.import => 'استيراد ملف',
        TxSource.api => 'نظام محاسبي',
      };
}

/// حالة العملية بعد بوابة الفحص
enum TxStatus { pendingEvaluation, allowed, frozen, exceptionPending, releasedException, violation }

extension TxStatusX on TxStatus {
  String get label => switch (this) {
        TxStatus.pendingEvaluation => 'بانتظار الفحص',
        TxStatus.allowed => 'مسموح',
        TxStatus.frozen => 'مجمّد للمراجعة',
        TxStatus.exceptionPending => 'استثناء بانتظار الشركاء',
        TxStatus.releasedException => 'أُفرج عنه كاستثناء',
        TxStatus.violation => 'مخالفة مسجلة',
      };

  Color get color => switch (this) {
        TxStatus.pendingEvaluation => const Color(0xFF7C8CA3),
        TxStatus.allowed => const Color(0xFF2ECC71),
        TxStatus.frozen => const Color(0xFF5DADE2),
        TxStatus.exceptionPending => const Color(0xFF3498DB),
        TxStatus.releasedException => const Color(0xFF9B8AFB),
        TxStatus.violation => const Color(0xFFE74C3C),
      };

  IconData get icon => switch (this) {
        TxStatus.pendingEvaluation => Icons.hourglass_top_rounded,
        TxStatus.allowed => Icons.check_circle_rounded,
        TxStatus.frozen => Icons.ac_unit_rounded,
        TxStatus.exceptionPending => Icons.how_to_vote_rounded,
        TxStatus.releasedException => Icons.lock_open_rounded,
        TxStatus.violation => Icons.gpp_bad_rounded,
      };
}

/// نتيجة فحص قاعدة واحدة على عملية: يُحفظ إصدار القاعدة المستخدم وقت التقييم
class RuleCheck {
  final String ruleId;
  final int ruleVersion;
  final String ruleName;
  final String condition;
  final String observed;
  final String expected;
  final bool triggered;
  final String action;
  final bool autoViolation; // الإجراء يقضي بتسجيل خرق مباشرة (مثل السلفة الشخصية)

  const RuleCheck({
    required this.ruleId,
    required this.ruleVersion,
    required this.ruleName,
    required this.condition,
    required this.observed,
    required this.expected,
    required this.triggered,
    required this.action,
    this.autoViolation = false,
  });

  Map<String, dynamic> toJson() => {
        'ruleId': ruleId,
        'ruleVersion': ruleVersion,
        'ruleName': ruleName,
        'condition': condition,
        'observed': observed,
        'expected': expected,
        'triggered': triggered,
        'action': action,
        'autoViolation': autoViolation,
      };

  factory RuleCheck.fromJson(Map<String, dynamic> j) => RuleCheck(
        ruleId: j['ruleId'] as String,
        ruleVersion: (j['ruleVersion'] as num?)?.toInt() ?? 1,
        ruleName: j['ruleName'] as String? ?? '',
        condition: j['condition'] as String? ?? '',
        observed: j['observed'] as String? ?? '',
        expected: j['expected'] as String? ?? '',
        triggered: j['triggered'] as bool? ?? false,
        action: j['action'] as String? ?? '',
        autoViolation: j['autoViolation'] as bool? ?? false,
      );
}

/// عملية مالية: المصدر الوحيد لقبولها هو بوابة الفحص؛ التجميد حجز تشغيلي وليس حذفاً
class FinancialTx {
  final String id;
  final String companyId;
  final DateTime date;
  final double amount;
  final AppCurrency currency;
  final TxCategory category;
  final String payee;
  final String purpose;
  final String reference;
  final TxSource source;
  final String createdBy;
  final DateTime createdAt;
  TxStatus status;
  List<RuleCheck> checks;
  DateTime? evaluatedAt;
  String? contractRef; // معرّف جلسة العقد الذي فُحصت عليه
  List<String> notes;

  FinancialTx({
    required this.id,
    required this.companyId,
    required this.date,
    required this.amount,
    required this.currency,
    required this.category,
    required this.payee,
    required this.purpose,
    this.reference = '',
    this.source = TxSource.manual,
    required this.createdBy,
    required this.createdAt,
    this.status = TxStatus.pendingEvaluation,
    List<RuleCheck>? checks,
    this.evaluatedAt,
    this.contractRef,
    List<String>? notes,
  })  : checks = checks ?? [],
        notes = notes ?? [];

  List<RuleCheck> get triggered => checks.where((c) => c.triggered).toList();

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyId': companyId,
        'date': date.toUtc().toIso8601String(),
        'amount': amount,
        'currency': currency.name,
        'category': category.name,
        'payee': payee,
        'purpose': purpose,
        'reference': reference,
        'source': source.name,
        'createdBy': createdBy,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'status': status.name,
        'checks': checks.map((c) => c.toJson()).toList(),
        'evaluatedAt': evaluatedAt?.toUtc().toIso8601String(),
        'contractRef': contractRef,
        'notes': notes,
      };

  factory FinancialTx.fromJson(Map<String, dynamic> j) => FinancialTx(
        id: j['id'] as String,
        companyId: j['companyId'] as String,
        date: DateTime.parse(j['date'] as String),
        amount: (j['amount'] as num).toDouble(),
        currency: AppCurrency.values.byName(j['currency'] as String),
        category: TxCategory.values.byName(j['category'] as String),
        payee: j['payee'] as String? ?? '',
        purpose: j['purpose'] as String? ?? '',
        reference: j['reference'] as String? ?? '',
        source: TxSource.values.byName(j['source'] as String? ?? 'manual'),
        createdBy: j['createdBy'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        status: TxStatus.values.byName(j['status'] as String),
        checks: (j['checks'] as List? ?? []).map((c) => RuleCheck.fromJson(Map<String, dynamic>.from(c as Map))).toList(),
        evaluatedAt: j['evaluatedAt'] == null ? null : DateTime.tryParse(j['evaluatedAt'] as String),
        contractRef: j['contractRef'] as String?,
        notes: (j['notes'] as List? ?? []).map((n) => n as String).toList(),
      );
}

/// حالة طلب الاستثناء
enum ExceptionStatus { pending, approved, rejected, expired }

extension ExceptionStatusX on ExceptionStatus {
  String get label => switch (this) {
        ExceptionStatus.pending => 'بانتظار الشركاء',
        ExceptionStatus.approved => 'معتمد لمرة واحدة',
        ExceptionStatus.rejected => 'مرفوض',
        ExceptionStatus.expired => 'منتهي المهلة',
      };

  Color get color => switch (this) {
        ExceptionStatus.pending => const Color(0xFF3498DB),
        ExceptionStatus.approved => const Color(0xFF2ECC71),
        ExceptionStatus.rejected => const Color(0xFFE74C3C),
        ExceptionStatus.expired => const Color(0xFF7C8CA3),
      };
}

/// صوت شريك على استثناء (مفتاحه رقم جوال الشريك أو معرّفه محلياً)
class ExceptionVote {
  final String partnerId;
  final bool approve;
  final DateTime at;
  final String method;
  final String? reason;

  const ExceptionVote({required this.partnerId, required this.approve, required this.at, required this.method, this.reason});

  Map<String, dynamic> toJson() =>
      {'partnerId': partnerId, 'approve': approve, 'at': at.toUtc().toIso8601String(), 'method': method, 'reason': reason};

  factory ExceptionVote.fromJson(Map<String, dynamic> j) => ExceptionVote(
        partnerId: j['partnerId'] as String,
        approve: j['approve'] as bool,
        at: DateTime.tryParse(j['at']?.toString() ?? '') ?? DateTime.now(),
        method: j['method'] as String? ?? 'manual',
        reason: j['reason'] as String?,
      );
}

/// طلب استثناء لمرة واحدة: لا يعدّل القاعدة ولا العقد
class ExceptionRequest {
  final String id;
  final String companyId;
  final String txId;
  final String ruleId;
  final String ruleName;
  final String originalLimit;
  final double requestedAmount;
  final String reason;
  final String requestedBy;
  final DateTime createdAt;
  final DateTime deadline;
  final double threshold; // نسبة الحصص الموافقة المطلوبة
  Map<String, ExceptionVote> votes;
  ExceptionStatus status;
  DateTime? decidedAt;

  ExceptionRequest({
    required this.id,
    required this.companyId,
    required this.txId,
    required this.ruleId,
    required this.ruleName,
    required this.originalLimit,
    required this.requestedAmount,
    required this.reason,
    required this.requestedBy,
    required this.createdAt,
    required this.deadline,
    this.threshold = 50.01,
    Map<String, ExceptionVote>? votes,
    this.status = ExceptionStatus.pending,
    this.decidedAt,
  }) : votes = votes ?? {};

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyId': companyId,
        'txId': txId,
        'ruleId': ruleId,
        'ruleName': ruleName,
        'originalLimit': originalLimit,
        'requestedAmount': requestedAmount,
        'reason': reason,
        'requestedBy': requestedBy,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'deadline': deadline.toUtc().toIso8601String(),
        'threshold': threshold,
        'votes': votes.map((k, v) => MapEntry(k, v.toJson())),
        'status': status.name,
        'decidedAt': decidedAt?.toUtc().toIso8601String(),
      };

  factory ExceptionRequest.fromJson(Map<String, dynamic> j) => ExceptionRequest(
        id: j['id'] as String,
        companyId: j['companyId'] as String,
        txId: j['txId'] as String,
        ruleId: j['ruleId'] as String,
        ruleName: j['ruleName'] as String? ?? '',
        originalLimit: j['originalLimit'] as String? ?? '',
        requestedAmount: (j['requestedAmount'] as num).toDouble(),
        reason: j['reason'] as String? ?? '',
        requestedBy: j['requestedBy'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        deadline: DateTime.tryParse(j['deadline'] as String? ?? '') ?? DateTime.now(),
        threshold: (j['threshold'] as num?)?.toDouble() ?? 50.01,
        votes: (j['votes'] as Map? ?? {}).map(
          (k, v) => MapEntry(k as String, ExceptionVote.fromJson(Map<String, dynamic>.from(v as Map))),
        ),
        status: ExceptionStatus.values.byName(j['status'] as String),
        decidedAt: j['decidedAt'] == null ? null : DateTime.tryParse(j['decidedAt'] as String),
      );
}

/// حالة المخالفة
enum ViolationStatus { open, investigating, corrective, escalated, resolved, disputed }

extension ViolationStatusX on ViolationStatus {
  String get label => switch (this) {
        ViolationStatus.open => 'مفتوحة',
        ViolationStatus.investigating => 'قيد التحقيق',
        ViolationStatus.corrective => 'إجراء تصحيحي',
        ViolationStatus.escalated => 'مُصعّدة',
        ViolationStatus.resolved => 'محلولة',
        ViolationStatus.disputed => 'محالة إلى نزاع',
      };

  Color get color => switch (this) {
        ViolationStatus.open => const Color(0xFFE74C3C),
        ViolationStatus.investigating => const Color(0xFFF39C12),
        ViolationStatus.corrective => const Color(0xFF3498DB),
        ViolationStatus.escalated => const Color(0xFFE67E22),
        ViolationStatus.resolved => const Color(0xFF2ECC71),
        ViolationStatus.disputed => const Color(0xFFC0392B),
      };
}

/// مخالفة مسجلة: دليل رسمي على خرق قاعدة من قواعد العقد
class Violation {
  final String id;
  final String companyId;
  final String txId;
  final String ruleId;
  final String ruleName;
  final String description;
  final String origin; // تلقائية من القاعدة، أو بعد رفض استثناء
  final DateTime createdAt;
  ViolationStatus status;
  String owner;
  String correctiveAction;
  List<String> evidence;

  Violation({
    required this.id,
    required this.companyId,
    required this.txId,
    required this.ruleId,
    required this.ruleName,
    required this.description,
    required this.origin,
    required this.createdAt,
    this.status = ViolationStatus.open,
    this.owner = '',
    this.correctiveAction = '',
    List<String>? evidence,
  }) : evidence = evidence ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyId': companyId,
        'txId': txId,
        'ruleId': ruleId,
        'ruleName': ruleName,
        'description': description,
        'origin': origin,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'status': status.name,
        'owner': owner,
        'correctiveAction': correctiveAction,
        'evidence': evidence,
      };

  factory Violation.fromJson(Map<String, dynamic> j) => Violation(
        id: j['id'] as String,
        companyId: j['companyId'] as String,
        txId: j['txId'] as String,
        ruleId: j['ruleId'] as String,
        ruleName: j['ruleName'] as String? ?? '',
        description: j['description'] as String? ?? '',
        origin: j['origin'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        status: ViolationStatus.values.byName(j['status'] as String),
        owner: j['owner'] as String? ?? '',
        correctiveAction: j['correctiveAction'] as String? ?? '',
        evidence: (j['evidence'] as List? ?? []).map((e) => e as String).toList(),
      );
}

/// قنوات الإشعار
enum NotifChannel { app, sms, email, whatsapp }

extension NotifChannelX on NotifChannel {
  String get label => switch (this) {
        NotifChannel.app => 'داخل التطبيق',
        NotifChannel.sms => 'رسالة SMS',
        NotifChannel.email => 'البريد الإلكتروني',
        NotifChannel.whatsapp => 'واتساب',
      };

  IconData get icon => switch (this) {
        NotifChannel.app => Icons.notifications_rounded,
        NotifChannel.sms => Icons.sms_rounded,
        NotifChannel.email => Icons.mail_rounded,
        NotifChannel.whatsapp => Icons.chat_rounded,
      };
}

enum NotifCategory { legal, approval, violation, operational, system }

extension NotifCategoryX on NotifCategory {
  String get label => switch (this) {
        NotifCategory.legal => 'قانونية',
        NotifCategory.approval => 'موافقات',
        NotifCategory.violation => 'مخالفات',
        NotifCategory.operational => 'تشغيلية',
        NotifCategory.system => 'النظام',
      };

  /// الإشعارات القانونية والمخالفات إلزامية ولا يمكن إيقافها من التفضيلات
  bool get mandatory => this == NotifCategory.legal || this == NotifCategory.violation;
}

/// حالة التسليم لكل قناة: تُحفظ كدليل قانوني (معرّف الرسالة، وقت الإرسال، الحالة)
enum DeliveryStatus { delivered, pending, failed, notConfigured }

extension DeliveryStatusX on DeliveryStatus {
  String get label => switch (this) {
        DeliveryStatus.delivered => 'وصلت',
        DeliveryStatus.pending => 'قيد الإرسال',
        DeliveryStatus.failed => 'فشل الإرسال',
        DeliveryStatus.notConfigured => 'القناة غير مهيأة',
      };

  Color get color => switch (this) {
        DeliveryStatus.delivered => const Color(0xFF2ECC71),
        DeliveryStatus.pending => const Color(0xFF3498DB),
        DeliveryStatus.failed => const Color(0xFFE74C3C),
        DeliveryStatus.notConfigured => const Color(0xFF7C8CA3),
      };
}

class DeliveryRecord {
  final NotifChannel channel;
  final DeliveryStatus status;
  final String? messageRef;
  final DateTime at;

  const DeliveryRecord({required this.channel, required this.status, this.messageRef, required this.at});

  Map<String, dynamic> toJson() =>
      {'channel': channel.name, 'status': status.name, 'messageRef': messageRef, 'at': at.toUtc().toIso8601String()};

  factory DeliveryRecord.fromJson(Map<String, dynamic> j) => DeliveryRecord(
        channel: NotifChannel.values.byName(j['channel'] as String),
        status: DeliveryStatus.values.byName(j['status'] as String),
        messageRef: j['messageRef'] as String?,
        at: DateTime.tryParse(j['at']?.toString() ?? '') ?? DateTime.now(),
      );
}

/// إشعار موجّه لعضو في الشركة
class AppNotification {
  final String id;
  final String companyId;
  final String recipientId; // معرّف العضو
  final NotifCategory category;
  final String subject;
  final String body;
  final String? relatedType; // tx / exception / violation
  final String? relatedId;
  final DateTime sentAt;
  final List<DeliveryRecord> deliveries;
  bool read;

  AppNotification({
    required this.id,
    required this.companyId,
    required this.recipientId,
    required this.category,
    required this.subject,
    required this.body,
    this.relatedType,
    this.relatedId,
    required this.sentAt,
    required this.deliveries,
    this.read = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyId': companyId,
        'recipientId': recipientId,
        'category': category.name,
        'subject': subject,
        'body': body,
        'relatedType': relatedType,
        'relatedId': relatedId,
        'sentAt': sentAt.toUtc().toIso8601String(),
        'deliveries': deliveries.map((d) => d.toJson()).toList(),
        'read': read,
      };

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        companyId: j['companyId'] as String,
        recipientId: j['recipientId'] as String,
        category: NotifCategory.values.byName(j['category'] as String),
        subject: j['subject'] as String,
        body: j['body'] as String,
        relatedType: j['relatedType'] as String?,
        relatedId: j['relatedId'] as String?,
        sentAt: DateTime.tryParse(j['sentAt']?.toString() ?? '') ?? DateTime.now(),
        deliveries: (j['deliveries'] as List? ?? [])
            .map((d) => DeliveryRecord.fromJson(Map<String, dynamic>.from(d as Map)))
            .toList(),
        read: j['read'] as bool? ?? false,
      );
}

/// قالب رسالة (A15) بمتغيرات
class MessageTemplate {
  final String id;
  final String event;
  final String subject;
  final String body;
  final bool mandatory;
  final int version;

  const MessageTemplate({
    required this.id,
    required this.event,
    required this.subject,
    required this.body,
    this.mandatory = false,
    this.version = 1,
  });

  static const variables = {
    'company': 'اسم الشركة',
    'amount': 'المبلغ',
    'rule': 'اسم القاعدة',
    'limit': 'الحد في العقد',
    'payee': 'المستفيد',
  };

  String render(Map<String, String> v) {
    var s = body;
    v.forEach((k, val) => s = s.replaceAll('{$k}', val));
    return s;
  }

  String renderSubject(Map<String, String> v) {
    var s = subject;
    v.forEach((k, val) => s = s.replaceAll('{$k}', val));
    return s;
  }

  MessageTemplate copyWith({String? subject, String? body}) => MessageTemplate(
        id: id,
        event: event,
        subject: subject ?? this.subject,
        body: body ?? this.body,
        mandatory: mandatory,
        version: version + 1,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'event': event, 'subject': subject, 'body': body, 'mandatory': mandatory, 'version': version};

  factory MessageTemplate.fromJson(Map<String, dynamic> j) => MessageTemplate(
        id: j['id'] as String,
        event: j['event'] as String,
        subject: j['subject'] as String,
        body: j['body'] as String,
        mandatory: j['mandatory'] as bool? ?? false,
        version: (j['version'] as num?)?.toInt() ?? 1,
      );
}
