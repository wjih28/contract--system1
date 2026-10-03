import 'package:flutter/material.dart';

/// العملات المدعومة في السوق المستهدف (اليمن)
enum AppCurrency { usd, sar }

extension AppCurrencyX on AppCurrency {
  String get label => switch (this) {
        AppCurrency.usd => 'دولار أمريكي',
        AppCurrency.sar => 'ريال سعودي',
      };

  String get code => switch (this) {
        AppCurrency.usd => 'USD',
        AppCurrency.sar => 'SAR',
      };

  String get symbol => switch (this) {
        AppCurrency.usd => '\$',
        AppCurrency.sar => 'ر.س',
      };
}

/// تصنيف البند حسب طبيعته
enum ClauseCategory { legal, financial, administrative }

extension ClauseCategoryX on ClauseCategory {
  String get label => switch (this) {
        ClauseCategory.legal => 'قانوني',
        ClauseCategory.financial => 'مالي',
        ClauseCategory.administrative => 'إداري',
      };

  IconData get icon => switch (this) {
        ClauseCategory.legal => Icons.balance_rounded,
        ClauseCategory.financial => Icons.account_balance_wallet_rounded,
        ClauseCategory.administrative => Icons.apartment_rounded,
      };

  Color get color => switch (this) {
        ClauseCategory.legal => const Color(0xFF9B8AFB),
        ClauseCategory.financial => const Color(0xFF2ECC71),
        ClauseCategory.administrative => const Color(0xFF3498DB),
      };
}

/// نطاق البند: عام يحسم بالنصاب، أو خاص بشريك بعينه يحسم بتراضيه الفردي
enum ClauseScope { general, private }

extension ClauseScopeX on ClauseScope {
  String get label => switch (this) {
        ClauseScope.general => 'بند عام',
        ClauseScope.private => 'بند خاص بالشريك',
      };
}

/// نوع الأثر المترتب على اعتماد البند
enum EffectType { textual, financial }

extension EffectTypeX on EffectType {
  String get label => switch (this) {
        EffectType.textual => 'أثر نصي في العقد',
        EffectType.financial => 'أثر مالي ورقابي',
      };
}

/// المعاملات المنطقية المستخدمة في القواعد الشرطية
enum ComparisonOp { gt, lt, eq, gte, lte }

extension ComparisonOpX on ComparisonOp {
  String get symbol => switch (this) {
        ComparisonOp.gt => '>',
        ComparisonOp.lt => '<',
        ComparisonOp.eq => '=',
        ComparisonOp.gte => '>=',
        ComparisonOp.lte => '<=',
      };

  String get label => switch (this) {
        ComparisonOp.gt => 'أكبر من',
        ComparisonOp.lt => 'أصغر من',
        ComparisonOp.eq => 'يساوي',
        ComparisonOp.gte => 'أكبر من أو يساوي',
        ComparisonOp.lte => 'أصغر من أو يساوي',
      };

  bool evaluate(double left, double right) => switch (this) {
        ComparisonOp.gt => left > right,
        ComparisonOp.lt => left < right,
        ComparisonOp.eq => left == right,
        ComparisonOp.gte => left >= right,
        ComparisonOp.lte => left <= right,
      };
}

/// نصاب التصويت: التسمية اللفظية وقيمتها المئوية المخزنة
class QuorumRule {
  final String label;
  final double percent;

  const QuorumRule(this.label, this.percent);

  static const majority = QuorumRule('أغلبية مطلقة', 50.01);
  static const twoThirds = QuorumRule('ثلثين', 66.67);
  static const threeQuarters = QuorumRule('ثلاثة أرباع', 75);
  static const unanimous = QuorumRule('إجماع', 100);

  static const presets = [majority, twoThirds, threeQuarters, unanimous];

  /// تحويل التسمية اللفظية (مثل "ثلثين") إلى نسبة مئوية عشرية
  static QuorumRule parse(String text) {
    final t = text.trim();
    for (final p in presets) {
      if (t.contains(p.label)) return p;
    }
    if (t.contains('نصف') || t.contains('أغلبية')) return majority;
    final n = double.tryParse(t.replaceAll('%', ''));
    if (n != null) return QuorumRule('$n%', n.clamp(0, 100).toDouble());
    return twoThirds;
  }

  String get display => '$label (${percent.toStringAsFixed(percent % 1 == 0 ? 0 : 2)}%)';

  Map<String, dynamic> toJson() => {'label': label, 'percent': percent};
  factory QuorumRule.fromJson(Map<String, dynamic> j) =>
      QuorumRule(j['label'] as String, (j['percent'] as num).toDouble());
}

/// قاعدة رقابية تتولد من بند ذي أثر مالي
/// مثال: قيمة العملية > 2,000 ⬅ تجميد وتنبيه الشركاء
class RuleTemplate {
  final String field; // الحقل المالي الذي تفحصه القاعدة
  final String fieldLabel;
  final ComparisonOp op;
  final String action; // الإجراء عند تحقق الشرط

  const RuleTemplate({
    required this.field,
    required this.fieldLabel,
    required this.op,
    required this.action,
  });

  Map<String, dynamic> toJson() =>
      {'field': field, 'fieldLabel': fieldLabel, 'op': op.name, 'action': action};
  factory RuleTemplate.fromJson(Map<String, dynamic> j) => RuleTemplate(
        field: j['field'] as String,
        fieldLabel: j['fieldLabel'] as String,
        op: ComparisonOp.values.byName(j['op'] as String),
        action: j['action'] as String,
      );
}

/// نوع القيمة التي يدخلها الشركاء في البند (إن وجدت)
enum ParamKind { none, money, percent, days, number }

/// بند في بنك الأسئلة
class BankQuestion {
  final String id;
  final ClauseCategory category;
  final ClauseScope scope;
  final String title;

  /// نص البند في العقد، ويقبل المتغيرات: {value} {currency} {partner}
  final String clauseTemplate;

  /// سؤال توعوي يوضح للشركاء أهمية البند ويساعدهم على حسمه
  final String awareness;
  final QuorumRule quorum;
  final EffectType effect;
  final ParamKind paramKind;
  final String? paramLabel;
  final double? defaultValue;
  final RuleTemplate? rule;
  final bool custom;

  const BankQuestion({
    required this.id,
    required this.category,
    required this.title,
    required this.clauseTemplate,
    required this.awareness,
    this.scope = ClauseScope.general,
    this.quorum = QuorumRule.twoThirds,
    this.effect = EffectType.textual,
    this.paramKind = ParamKind.none,
    this.paramLabel,
    this.defaultValue,
    this.rule,
    this.custom = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category.name,
        'scope': scope.name,
        'title': title,
        'clauseTemplate': clauseTemplate,
        'awareness': awareness,
        'quorum': quorum.toJson(),
        'effect': effect.name,
        'paramKind': paramKind.name,
        'paramLabel': paramLabel,
        'defaultValue': defaultValue,
        'rule': rule?.toJson(),
        'custom': custom,
      };

  factory BankQuestion.fromJson(Map<String, dynamic> j) => BankQuestion(
        id: j['id'] as String,
        category: ClauseCategory.values.byName(j['category'] as String),
        scope: ClauseScope.values.byName(j['scope'] as String),
        title: j['title'] as String,
        clauseTemplate: j['clauseTemplate'] as String,
        awareness: j['awareness'] as String,
        quorum: QuorumRule.fromJson(j['quorum'] as Map<String, dynamic>),
        effect: EffectType.values.byName(j['effect'] as String),
        paramKind: ParamKind.values.byName(j['paramKind'] as String),
        paramLabel: j['paramLabel'] as String?,
        defaultValue: (j['defaultValue'] as num?)?.toDouble(),
        rule: j['rule'] == null
            ? null
            : RuleTemplate.fromJson(j['rule'] as Map<String, dynamic>),
        custom: j['custom'] as bool? ?? false,
      );
}

/// خيار الشريك في التصويت
enum Ballot { agree, disagree, neutral }

extension BallotX on Ballot {
  String get label => switch (this) {
        Ballot.agree => 'موافق',
        Ballot.disagree => 'غير موافق',
        Ballot.neutral => 'محايد',
      };

  Color get color => switch (this) {
        Ballot.agree => const Color(0xFF2ECC71),
        Ballot.disagree => const Color(0xFFE74C3C),
        Ballot.neutral => const Color(0xFF7C8CA3),
      };

  IconData get icon => switch (this) {
        Ballot.agree => Icons.check_circle_rounded,
        Ballot.disagree => Icons.cancel_rounded,
        Ballot.neutral => Icons.remove_circle_rounded,
      };
}

/// طريقة تأكيد هوية الشريك عند التصويت
enum ConfirmMethod { biometric, deviceCredential, manual }

extension ConfirmMethodX on ConfirmMethod {
  String get label => switch (this) {
        ConfirmMethod.biometric => 'بصمة حيوية',
        ConfirmMethod.deviceCredential => 'رمز الجهاز',
        ConfirmMethod.manual => 'تأكيد يدوي',
      };
}

/// صوت شريك واحد على بند
class PartnerVote {
  final String partnerId;
  final Ballot ballot;
  final DateTime at;
  final ConfirmMethod method;

  const PartnerVote({
    required this.partnerId,
    required this.ballot,
    required this.at,
    required this.method,
  });

  Map<String, dynamic> toJson() => {
        'partnerId': partnerId,
        'ballot': ballot.name,
        'at': at.toIso8601String(),
        'method': method.name,
      };

  factory PartnerVote.fromJson(Map<String, dynamic> j) => PartnerVote(
        partnerId: j['partnerId'] as String,
        ballot: Ballot.values.byName(j['ballot'] as String),
        at: DateTime.parse(j['at'] as String),
        method: ConfirmMethod.values.byName(j['method'] as String),
      );
}

/// حالة البند داخل الجلسة
enum ClauseStatus { pending, agreed, rejected, deferred, neutralized }

extension ClauseStatusX on ClauseStatus {
  String get label => switch (this) {
        ClauseStatus.pending => 'بانتظار الحسم',
        ClauseStatus.agreed => 'متراضى عليه',
        ClauseStatus.rejected => 'لم يبلغ النصاب',
        ClauseStatus.deferred => 'مؤجل',
        ClauseStatus.neutralized => 'محيّد',
      };

  Color get color => switch (this) {
        ClauseStatus.pending => const Color(0xFF7C8CA3),
        ClauseStatus.agreed => const Color(0xFF2ECC71),
        ClauseStatus.rejected => const Color(0xFFE74C3C),
        ClauseStatus.deferred => const Color(0xFFF39C12),
        ClauseStatus.neutralized => const Color(0xFF9B8AFB),
      };

  IconData get icon => switch (this) {
        ClauseStatus.pending => Icons.radio_button_unchecked_rounded,
        ClauseStatus.agreed => Icons.verified_rounded,
        ClauseStatus.rejected => Icons.error_rounded,
        ClauseStatus.deferred => Icons.schedule_rounded,
        ClauseStatus.neutralized => Icons.block_rounded,
      };
}

/// سجل بند داخل جلسة: الأصوات والقيمة المتفق عليها والحالة
class ClauseRecord {
  final String key; // فريد داخل الجلسة (معرّف السؤال + الشريك للبنود الخاصة)
  final String questionId;
  final String? concernedPartnerId;
  double? value;
  ClauseStatus status;
  int round;
  Map<String, PartnerVote> votes;
  DateTime? resolvedAt;

  /// الشركاء الذين وافقوا على تحييد البند في الجولة الحالية (وضع الخادم)
  Set<String> neutralConsents = {};

  ClauseRecord({
    required this.key,
    required this.questionId,
    this.concernedPartnerId,
    this.value,
    this.status = ClauseStatus.pending,
    this.round = 1,
    Map<String, PartnerVote>? votes,
    this.resolvedAt,
  }) : votes = votes ?? {};

  Map<String, dynamic> toJson() => {
        'key': key,
        'questionId': questionId,
        'concernedPartnerId': concernedPartnerId,
        'value': value,
        'status': status.name,
        'round': round,
        'votes': votes.map((k, v) => MapEntry(k, v.toJson())),
        'resolvedAt': resolvedAt?.toIso8601String(),
      };

  factory ClauseRecord.fromJson(Map<String, dynamic> j) => ClauseRecord(
        key: j['key'] as String,
        questionId: j['questionId'] as String,
        concernedPartnerId: j['concernedPartnerId'] as String?,
        value: (j['value'] as num?)?.toDouble(),
        status: ClauseStatus.values.byName(j['status'] as String),
        round: j['round'] as int? ?? 1,
        votes: (j['votes'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, PartnerVote.fromJson(v as Map<String, dynamic>)),
        ),
        resolvedAt: j['resolvedAt'] == null
            ? null
            : DateTime.parse(j['resolvedAt'] as String),
      );
}

/// شريك مؤسس ضمن جلسة العقد
class SessionPartner {
  final String id;
  final String name;
  final String nationalId;
  final String phone;
  final double equity;

  const SessionPartner({
    required this.id,
    required this.name,
    required this.nationalId,
    required this.phone,
    required this.equity,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'nationalId': nationalId,
        'phone': phone,
        'equity': equity,
      };

  factory SessionPartner.fromJson(Map<String, dynamic> j) => SessionPartner(
        id: j['id'] as String,
        name: j['name'] as String,
        nationalId: j['nationalId'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        equity: (j['equity'] as num).toDouble(),
      );
}

/// شاهد على العقد
class Witness {
  final String name;
  final String nationalId;
  final bool internal; // من داخل الشركة أو خارجها
  final String? signaturePng; // base64

  const Witness({
    required this.name,
    required this.nationalId,
    required this.internal,
    this.signaturePng,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'nationalId': nationalId,
        'internal': internal,
        'signaturePng': signaturePng,
      };

  factory Witness.fromJson(Map<String, dynamic> j) => Witness(
        name: j['name'] as String,
        nationalId: j['nationalId'] as String,
        internal: j['internal'] as bool? ?? false,
        signaturePng: j['signaturePng'] as String?,
      );
}

/// توقيع الشريك النهائي مع إقرار الأهلية
class PartnerSignOff {
  final String partnerId;
  final String signaturePng; // base64
  final DateTime at;
  final ConfirmMethod method;

  const PartnerSignOff({
    required this.partnerId,
    required this.signaturePng,
    required this.at,
    required this.method,
  });

  Map<String, dynamic> toJson() => {
        'partnerId': partnerId,
        'signaturePng': signaturePng,
        'at': at.toIso8601String(),
        'method': method.name,
      };

  factory PartnerSignOff.fromJson(Map<String, dynamic> j) => PartnerSignOff(
        partnerId: j['partnerId'] as String,
        signaturePng: j['signaturePng'] as String,
        at: DateTime.parse(j['at'] as String),
        method: ConfirmMethod.values.byName(j['method'] as String),
      );
}

/// حالة الجلسة
enum SessionStatus { active, suspended, awaitingSignature, completed }

extension SessionStatusX on SessionStatus {
  String get label => switch (this) {
        SessionStatus.active => 'جارية',
        SessionStatus.suspended => 'معلّقة',
        SessionStatus.awaitingSignature => 'بانتظار التوقيع',
        SessionStatus.completed => 'مكتملة',
      };

  Color get color => switch (this) {
        SessionStatus.active => const Color(0xFF3498DB),
        SessionStatus.suspended => const Color(0xFFF39C12),
        SessionStatus.awaitingSignature => const Color(0xFFC9A227),
        SessionStatus.completed => const Color(0xFF2ECC71),
      };
}

/// جلسة إعداد عقد تأسيس
class ContractSession {
  final String id;
  String companyName;
  String companyType;
  AppCurrency currency;
  double capital;
  List<SessionPartner> partners;
  List<ClauseRecord> records;
  SessionStatus status;
  final DateTime createdAt;
  DateTime updatedAt;
  int sittings; // عدد الجلسات (كل استئناف بعد تعليق = جلسة جديدة)
  List<Witness> witnesses;
  Map<String, PartnerSignOff> signOffs;
  DateTime? completedAt;

  /// بصمة SHA-256 لمحتوى العقد المعتمد؛ أي تعديل لاحق يغيّرها
  String? contentHash;

  ContractSession({
    required this.id,
    required this.companyName,
    required this.companyType,
    required this.currency,
    required this.capital,
    required this.partners,
    required this.records,
    this.status = SessionStatus.active,
    required this.createdAt,
    required this.updatedAt,
    this.sittings = 1,
    List<Witness>? witnesses,
    Map<String, PartnerSignOff>? signOffs,
    this.completedAt,
    this.contentHash,
  })  : witnesses = witnesses ?? [],
        signOffs = signOffs ?? {};

  int count(ClauseStatus s) => records.where((r) => r.status == s).length;

  /// نسبة الإنجاز: البنود المحسومة (متراضى عليها أو محيّدة) من الإجمالي
  double get progress => records.isEmpty
      ? 0
      : (count(ClauseStatus.agreed) + count(ClauseStatus.neutralized)) /
          records.length;

  /// لا يُصدر العقد إلا بعد حسم كافة البنود
  bool get allResolved => records.every((r) =>
      r.status == ClauseStatus.agreed || r.status == ClauseStatus.neutralized);

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyName': companyName,
        'companyType': companyType,
        'currency': currency.name,
        'capital': capital,
        'partners': partners.map((p) => p.toJson()).toList(),
        'records': records.map((r) => r.toJson()).toList(),
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'sittings': sittings,
        'witnesses': witnesses.map((w) => w.toJson()).toList(),
        'signOffs': signOffs.map((k, v) => MapEntry(k, v.toJson())),
        'completedAt': completedAt?.toIso8601String(),
        'contentHash': contentHash,
      };

  factory ContractSession.fromJson(Map<String, dynamic> j) => ContractSession(
        id: j['id'] as String,
        companyName: j['companyName'] as String,
        companyType: j['companyType'] as String,
        currency: AppCurrency.values.byName(j['currency'] as String),
        capital: (j['capital'] as num).toDouble(),
        partners: (j['partners'] as List)
            .map((p) => SessionPartner.fromJson(p as Map<String, dynamic>))
            .toList(),
        records: (j['records'] as List)
            .map((r) => ClauseRecord.fromJson(r as Map<String, dynamic>))
            .toList(),
        status: SessionStatus.values.byName(j['status'] as String),
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
        sittings: j['sittings'] as int? ?? 1,
        witnesses: (j['witnesses'] as List? ?? [])
            .map((w) => Witness.fromJson(w as Map<String, dynamic>))
            .toList(),
        signOffs: (j['signOffs'] as Map<String, dynamic>? ?? {}).map(
          (k, v) =>
              MapEntry(k, PartnerSignOff.fromJson(v as Map<String, dynamic>)),
        ),
        completedAt: j['completedAt'] == null
            ? null
            : DateTime.parse(j['completedAt'] as String),
        contentHash: j['contentHash'] as String?,
      );
}

/// نتيجة احتساب النصاب لبند
class QuorumResult {
  final double agreeShare; // نسبة الحصص الموافقة
  final double disagreeShare;
  final double neutralShare;
  final double required;
  final bool complete; // صوّت كل من يحق له التصويت
  final bool passed;

  const QuorumResult({
    required this.agreeShare,
    required this.disagreeShare,
    required this.neutralShare,
    required this.required,
    required this.complete,
    required this.passed,
  });
}
