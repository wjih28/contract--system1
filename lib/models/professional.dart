import 'package:flutter/material.dart';

/// الأطراف المهنية (المرحلة 5): المحامي والمحاسب. وصول محدود بنطاق التكليف ومدته،
/// لا يمنح حق تصويت ولا ملكية، وتعليقاتهم أدلة لا تغيّر العقد.

DateTime _t(Object? v) => DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();
String _iso(DateTime d) => d.toUtc().toIso8601String();

enum ProRole { lawyer, accountant }

extension ProRoleX on ProRole {
  String get label => this == ProRole.lawyer ? 'محامٍ' : 'محاسب';
}

/// نطاق التكليف: ما يحق للطرف المهني الاطلاع عليه
enum EngagementScope { contract, financialRules, correspondence, disputes }

extension EngagementScopeX on EngagementScope {
  String get label => switch (this) {
        EngagementScope.contract => 'مسودات العقد وإصداراته',
        EngagementScope.financialRules => 'البنود المالية وقواعدها وحدودها',
        EngagementScope.correspondence => 'المراسلات المرتبطة',
        EngagementScope.disputes => 'ملفات النزاعات',
      };
}

enum EngagementStatus { pending, active, declined, expired, terminated }

extension EngagementStatusX on EngagementStatus {
  String get label => switch (this) {
        EngagementStatus.pending => 'بانتظار قبول الدعوة',
        EngagementStatus.active => 'سارٍ',
        EngagementStatus.declined => 'اعتذر عن التكليف',
        EngagementStatus.expired => 'منتهي المدة',
        EngagementStatus.terminated => 'مُنهى',
      };

  Color get color => switch (this) {
        EngagementStatus.pending => const Color(0xFF3498DB),
        EngagementStatus.active => const Color(0xFF2ECC71),
        EngagementStatus.declined => const Color(0xFF7C8CA3),
        EngagementStatus.expired => const Color(0xFFF39C12),
        EngagementStatus.terminated => const Color(0xFFE74C3C),
      };
}

/// تكليف طرف مهني. المعرّف = رقم جواله، فلكل طرف تكليف واحد في الشركة (قواعد الأمان تعتمد عليه).
class Engagement {
  final String id; // رقم الجوال
  final String companyId;
  final String memberId;
  final String name;
  final ProRole role;
  String organization;
  String contact;
  Set<EngagementScope> scope;
  DateTime start;
  DateTime end;
  EngagementStatus status;
  final String createdBy;
  final DateTime createdAt;
  DateTime? respondedAt;
  String? declineReason;

  /// طلب الإنهاء بعد بدء المراجعة: موافقات الشركاء (العضو ← الوقت)
  String? terminationReason;
  Map<String, String> terminationApprovals;

  Engagement({
    required this.id,
    required this.companyId,
    required this.memberId,
    required this.name,
    required this.role,
    this.organization = '',
    this.contact = '',
    required this.scope,
    required this.start,
    required this.end,
    this.status = EngagementStatus.pending,
    required this.createdBy,
    required this.createdAt,
    this.respondedAt,
    this.declineReason,
    this.terminationReason,
    Map<String, String>? terminationApprovals,
  }) : terminationApprovals = terminationApprovals ?? {};

  /// الحالة الفعلية: التكليف السارية مدته المنقضية يصبح منتهياً
  EngagementStatus statusAt(DateTime now) =>
      status == EngagementStatus.active && now.isAfter(end) ? EngagementStatus.expired : status;

  bool activeAt(DateTime now) => statusAt(now) == EngagementStatus.active;

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyId': companyId,
        'memberId': memberId,
        'name': name,
        'role': role.name,
        'organization': organization,
        'contact': contact,
        'scope': scope.map((s) => s.name).toList(),
        'start': _iso(start),
        'end': _iso(end),
        'endMillis': end.millisecondsSinceEpoch, // تقارن به قواعد الأمان انتهاء التكليف
        'status': status.name,
        'createdBy': createdBy,
        'createdAt': _iso(createdAt),
        'respondedAt': respondedAt == null ? null : _iso(respondedAt!),
        'declineReason': declineReason,
        'terminationReason': terminationReason,
        'terminationApprovals': terminationApprovals,
      };

  factory Engagement.fromJson(Map<String, dynamic> j) => Engagement(
        id: j['id'] as String,
        companyId: j['companyId'] as String,
        memberId: j['memberId'] as String,
        name: j['name'] as String? ?? '',
        role: ProRole.values.byName(j['role'] as String),
        organization: j['organization'] as String? ?? '',
        contact: j['contact'] as String? ?? '',
        scope: (j['scope'] as List? ?? []).map((s) => EngagementScope.values.byName(s as String)).toSet(),
        start: _t(j['start']),
        end: _t(j['end']),
        status: EngagementStatus.values.byName(j['status'] as String? ?? 'pending'),
        createdBy: j['createdBy'] as String? ?? '',
        createdAt: _t(j['createdAt']),
        respondedAt: j['respondedAt'] == null ? null : _t(j['respondedAt']),
        declineReason: j['declineReason'] as String?,
        terminationReason: j['terminationReason'] as String?,
        terminationApprovals: Map<String, dynamic>.from(j['terminationApprovals'] as Map? ?? {}).map((k, v) => MapEntry(k, '$v')),
      );
}

enum CommentKind { comment, changeRequest, clarification }

extension CommentKindX on CommentKind {
  String get label => switch (this) {
        CommentKind.comment => 'ملاحظة',
        CommentKind.changeRequest => 'طلب تعديل',
        CommentKind.clarification => 'طلب إيضاح',
      };
}

enum Severity3 { low, medium, high }

extension Severity3X on Severity3 {
  String get label => switch (this) { Severity3.low => 'منخفضة', Severity3.medium => 'متوسطة', Severity3.high => 'مرتفعة' };
  Color get color => switch (this) {
        Severity3.low => const Color(0xFF3498DB),
        Severity3.medium => const Color(0xFFF39C12),
        Severity3.high => const Color(0xFFE74C3C),
      };
}

/// فئات التعليق حسب نوع المراجعة
const kLegalCategories = ['صياغة', 'امتثال قانوني', 'مخاطرة', 'غموض', 'تعارض بين البنود'];
const kAccountingCategories = ['تصنيف محاسبي', 'حد مالي', 'عملة', 'إثبات وتوثيق', 'إيضاح'];

enum CommentStatus { open, awaitingResponse, resolved, reopened }

extension CommentStatusX on CommentStatus {
  String get label => switch (this) {
        CommentStatus.open => 'مفتوح',
        CommentStatus.awaitingResponse => 'بانتظار الرد',
        CommentStatus.resolved => 'محلول',
        CommentStatus.reopened => 'أُعيد فتحه',
      };

  bool get isOpen => this != CommentStatus.resolved;
}

class CommentReply {
  final String authorId;
  final String authorName;
  final bool professional;
  final String text;
  final DateTime at;

  const CommentReply({required this.authorId, required this.authorName, required this.professional, required this.text, required this.at});

  Map<String, dynamic> toJson() =>
      {'authorId': authorId, 'authorName': authorName, 'professional': professional, 'text': text, 'at': _iso(at)};

  factory CommentReply.fromJson(Map<String, dynamic> j) => CommentReply(
        authorId: j['authorId'] as String? ?? '',
        authorName: j['authorName'] as String? ?? '',
        professional: j['professional'] as bool? ?? false,
        text: j['text'] as String? ?? '',
        at: _t(j['at']),
      );
}

/// تعليق مهني على بند أو قاعدة أو مستند. دليل محفوظ لا يغيّر النص المعتمد.
class ProComment {
  final String id;
  final String companyId;
  final String engagementId;
  final String authorId;
  final String authorName;
  final ProRole authorRole;
  final String targetType; // clause / rule / document
  final String targetId;
  final String targetLabel;
  final String? sessionId; // الإصدار الذي عُلِّق عليه
  final int? version;
  final CommentKind kind;
  final String category;
  final Severity3 severity;
  final String text;
  final DateTime createdAt;
  DateTime? dueDate;
  CommentStatus status;
  List<CommentReply> replies;
  DateTime? resolvedAt;

  /// مقترح الإصدار الذي فتحه الشركاء استجابة لطلب التعديل
  String? amendmentRef;

  ProComment({
    required this.id,
    required this.companyId,
    required this.engagementId,
    required this.authorId,
    required this.authorName,
    required this.authorRole,
    required this.targetType,
    required this.targetId,
    required this.targetLabel,
    this.sessionId,
    this.version,
    this.kind = CommentKind.comment,
    required this.category,
    this.severity = Severity3.medium,
    required this.text,
    required this.createdAt,
    this.dueDate,
    this.status = CommentStatus.open,
    List<CommentReply>? replies,
    this.resolvedAt,
    this.amendmentRef,
  }) : replies = replies ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyId': companyId,
        'engagementId': engagementId,
        'authorId': authorId,
        'authorName': authorName,
        'authorRole': authorRole.name,
        'targetType': targetType,
        'targetId': targetId,
        'targetLabel': targetLabel,
        'sessionId': sessionId,
        'version': version,
        'kind': kind.name,
        'category': category,
        'severity': severity.name,
        'text': text,
        'createdAt': _iso(createdAt),
        'dueDate': dueDate == null ? null : _iso(dueDate!),
        'status': status.name,
        'replies': replies.map((r) => r.toJson()).toList(),
        'resolvedAt': resolvedAt == null ? null : _iso(resolvedAt!),
        'amendmentRef': amendmentRef,
      };

  factory ProComment.fromJson(Map<String, dynamic> j) => ProComment(
        id: j['id'] as String,
        companyId: j['companyId'] as String,
        engagementId: j['engagementId'] as String,
        authorId: j['authorId'] as String? ?? '',
        authorName: j['authorName'] as String? ?? '',
        authorRole: ProRole.values.byName(j['authorRole'] as String? ?? 'lawyer'),
        targetType: j['targetType'] as String? ?? 'clause',
        targetId: j['targetId'] as String? ?? '',
        targetLabel: j['targetLabel'] as String? ?? '',
        sessionId: j['sessionId'] as String?,
        version: (j['version'] as num?)?.toInt(),
        kind: CommentKind.values.byName(j['kind'] as String? ?? 'comment'),
        category: j['category'] as String? ?? '',
        severity: Severity3.values.byName(j['severity'] as String? ?? 'medium'),
        text: j['text'] as String? ?? '',
        createdAt: _t(j['createdAt']),
        dueDate: j['dueDate'] == null ? null : _t(j['dueDate']),
        status: CommentStatus.values.byName(j['status'] as String? ?? 'open'),
        replies: (j['replies'] as List? ?? []).map((e) => CommentReply.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        resolvedAt: j['resolvedAt'] == null ? null : _t(j['resolvedAt']),
        amendmentRef: j['amendmentRef'] as String?,
      );
}

enum ReviewStatus { underReview, completed }

extension ReviewStatusX on ReviewStatus {
  String get label => this == ReviewStatus.underReview ? 'قيد المراجعة' : 'اكتملت المراجعة';
}

/// قائمة تحقق المراجعة المحاسبية (R05)
const kAccountingChecklist = [
  'حدود الصرف متسقة مع رأس المال وحجم النشاط',
  'العملة المعتمدة وطريقة التعامل مع العملات الأخرى واضحة',
  'تصنيف المصروفات والضيافة والسلف قابل للتطبيق محاسبياً',
  'معالجة الحساب الجاري للشريك المدير محددة',
  'قواعد الرواتب وتعديلها قابلة للتدقيق',
  'نسب توزيع الأرباح والاحتياطي متسقة',
];

/// مراجعة مهنية لإصدار محدد من العقد
class ProReview {
  final String id; // engagementId|sessionId
  final String companyId;
  final String engagementId;
  final ProRole type;
  final String sessionId;
  final int version;
  ReviewStatus status;
  Set<String> reviewedKeys;
  Map<String, bool> checklist;
  Map<String, String> accountMapping; // الفئة ← رمز الحساب
  final DateTime startedAt;
  DateTime? completedAt;
  String? summary;

  ProReview({
    required this.id,
    required this.companyId,
    required this.engagementId,
    required this.type,
    required this.sessionId,
    required this.version,
    this.status = ReviewStatus.underReview,
    Set<String>? reviewedKeys,
    Map<String, bool>? checklist,
    Map<String, String>? accountMapping,
    required this.startedAt,
    this.completedAt,
    this.summary,
  })  : reviewedKeys = reviewedKeys ?? {},
        checklist = checklist ?? {},
        accountMapping = accountMapping ?? {};

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyId': companyId,
        'engagementId': engagementId,
        'type': type.name,
        'sessionId': sessionId,
        'version': version,
        'status': status.name,
        'reviewedKeys': reviewedKeys.toList(),
        'checklist': checklist,
        'accountMapping': accountMapping,
        'startedAt': _iso(startedAt),
        'completedAt': completedAt == null ? null : _iso(completedAt!),
        'summary': summary,
      };

  factory ProReview.fromJson(Map<String, dynamic> j) => ProReview(
        id: j['id'] as String,
        companyId: j['companyId'] as String,
        engagementId: j['engagementId'] as String,
        type: ProRole.values.byName(j['type'] as String),
        sessionId: j['sessionId'] as String,
        version: (j['version'] as num?)?.toInt() ?? 1,
        status: ReviewStatus.values.byName(j['status'] as String? ?? 'underReview'),
        reviewedKeys: (j['reviewedKeys'] as List? ?? []).map((e) => '$e').toSet(),
        checklist: Map<String, dynamic>.from(j['checklist'] as Map? ?? {}).map((k, v) => MapEntry(k, v == true)),
        accountMapping: Map<String, dynamic>.from(j['accountMapping'] as Map? ?? {}).map((k, v) => MapEntry(k, '$v')),
        startedAt: _t(j['startedAt']),
        completedAt: j['completedAt'] == null ? null : _t(j['completedAt']),
        summary: j['summary'] as String?,
      );
}
