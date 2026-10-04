import 'dart:convert';
import 'package:flutter/material.dart';

/// العملات المدعومة في السوق المستهدف (اليمن): الدولار أولاً، ثم الريال السعودي، ثم الريال اليمني
enum AppCurrency { usd, sar, yer }

extension AppCurrencyX on AppCurrency {
  String get label => switch (this) {
        AppCurrency.usd => 'دولار أمريكي',
        AppCurrency.sar => 'ريال سعودي',
        AppCurrency.yer => 'ريال يمني',
      };

  String get code => switch (this) {
        AppCurrency.usd => 'USD',
        AppCurrency.sar => 'SAR',
        AppCurrency.yer => 'YER',
      };

  String get symbol => switch (this) {
        AppCurrency.usd => '\$',
        AppCurrency.sar => 'ر.س',
        AppCurrency.yer => 'ر.ي',
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
enum ClauseStatus { pending, agreed, rejected, deferred, neutralized, quorumFailed, deadlock, notApplicable }

extension ClauseStatusX on ClauseStatus {
  String get label => switch (this) {
        ClauseStatus.pending => 'بانتظار الحسم',
        ClauseStatus.agreed => 'متراضى عليه',
        ClauseStatus.rejected => 'لم يبلغ النصاب',
        ClauseStatus.deferred => 'مؤجل',
        ClauseStatus.neutralized => 'محيّد',
        ClauseStatus.quorumFailed => 'تعذّر النصاب',
        ClauseStatus.deadlock => 'جمود',
        ClauseStatus.notApplicable => 'غير منطبق',
      };

  Color get color => switch (this) {
        ClauseStatus.pending => const Color(0xFF7C8CA3),
        ClauseStatus.agreed => const Color(0xFF2ECC71),
        ClauseStatus.rejected => const Color(0xFFE74C3C),
        ClauseStatus.deferred => const Color(0xFFF39C12),
        ClauseStatus.neutralized => const Color(0xFF9B8AFB),
        ClauseStatus.quorumFailed => const Color(0xFFE67E22),
        ClauseStatus.deadlock => const Color(0xFFC0392B),
        ClauseStatus.notApplicable => const Color(0xFF5B6B82),
      };

  IconData get icon => switch (this) {
        ClauseStatus.pending => Icons.radio_button_unchecked_rounded,
        ClauseStatus.agreed => Icons.verified_rounded,
        ClauseStatus.rejected => Icons.error_rounded,
        ClauseStatus.deferred => Icons.schedule_rounded,
        ClauseStatus.neutralized => Icons.block_rounded,
        ClauseStatus.quorumFailed => Icons.group_off_rounded,
        ClauseStatus.deadlock => Icons.lock_clock_rounded,
        ClauseStatus.notApplicable => Icons.do_not_disturb_on_outlined,
      };

  /// بنود تحتاج قراراً جديداً من الشركاء (لم تُحسم ولم تؤجل أو تحيّد)
  bool get needsDecision =>
      this == ClauseStatus.pending ||
      this == ClauseStatus.rejected ||
      this == ClauseStatus.quorumFailed ||
      this == ClauseStatus.deadlock;
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

  /// بداية التصويت في الجولة الحالية (أول صوت)، ومنها تُحسب المهلة
  DateTime? openedAt;

  /// عدد الجولات المتتالية التي فشلت (رفض أو تعذّر نصاب)؛ تكرارها يعني جموداً
  int failures;

  /// ملاحظات النقاش على البند
  List<ClauseNote> notes;

  /// سبب التأجيل
  String? deferReason;

  /// لقطة من نص البند وإصداره عند إنشاء الجلسة: تعديل المكتبة لاحقاً لا يغيّر الجلسات القائمة
  String? clauseText;
  int? clauseVersion;

  /// لقطة من القاعدة المنطقية المرتبطة (JSON) وإصدارها
  Map<String, dynamic>? rule;

  /// شرط ظهور البند (JSON لشرط QuestionCondition)
  Map<String, dynamic>? showIf;

  /// الشركاء الذين وافقوا على تحييد البند في الجولة الحالية (وضع الخادم)
  Set<String> neutralConsents = {};

  /// في جلسة التعديل: البند موضوع التعديل، وقيمته في الإصدار السابق
  bool amended;
  double? previousValue;

  ClauseRecord({
    required this.key,
    required this.questionId,
    this.concernedPartnerId,
    this.value,
    this.status = ClauseStatus.pending,
    this.round = 1,
    Map<String, PartnerVote>? votes,
    this.resolvedAt,
    this.openedAt,
    this.failures = 0,
    List<ClauseNote>? notes,
    this.deferReason,
    this.clauseText,
    this.clauseVersion,
    this.rule,
    this.showIf,
    this.amended = false,
    this.previousValue,
  })  : votes = votes ?? {},
        notes = notes ?? [];

  /// نسخة مستقلة من البند (لإنشاء إصدار جديد دون المساس بالإصدار السابق)
  ClauseRecord clone() => ClauseRecord.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>);

  Map<String, dynamic> toJson() => {
        'key': key,
        'questionId': questionId,
        'concernedPartnerId': concernedPartnerId,
        'value': value,
        'status': status.name,
        'round': round,
        'votes': votes.map((k, v) => MapEntry(k, v.toJson())),
        'resolvedAt': resolvedAt?.toIso8601String(),
        'openedAt': openedAt?.toIso8601String(),
        'failures': failures,
        'notes': notes.map((n) => n.toJson()).toList(),
        'deferReason': deferReason,
        'clauseText': clauseText,
        'clauseVersion': clauseVersion,
        'rule': rule,
        'showIf': showIf,
        if (amended) 'amended': true,
        if (previousValue != null) 'previousValue': previousValue,
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
        openedAt: j['openedAt'] == null ? null : DateTime.parse(j['openedAt'] as String),
        failures: (j['failures'] as num?)?.toInt() ?? 0,
        notes: (j['notes'] as List? ?? [])
            .map((n) => ClauseNote.fromJson(Map<String, dynamic>.from(n as Map)))
            .toList(),
        deferReason: j['deferReason'] as String?,
        clauseText: j['clauseText'] as String?,
        clauseVersion: (j['clauseVersion'] as num?)?.toInt(),
        rule: j['rule'] == null ? null : Map<String, dynamic>.from(j['rule'] as Map),
        showIf: j['showIf'] == null ? null : Map<String, dynamic>.from(j['showIf'] as Map),
        amended: j['amended'] as bool? ?? false,
        previousValue: (j['previousValue'] as num?)?.toDouble(),
      );
}

/// ملاحظة نقاش على بند (لا تغيّر نص البند، وهي جزء من سجل القرار)
class ClauseNote {
  final String author;
  final String text;
  final DateTime at;

  const ClauseNote({required this.author, required this.text, required this.at});

  Map<String, dynamic> toJson() => {'author': author, 'text': text, 'at': at.toUtc().toIso8601String()};

  factory ClauseNote.fromJson(Map<String, dynamic> j) => ClauseNote(
        author: j['author'] as String? ?? '',
        text: j['text'] as String? ?? '',
        at: DateTime.tryParse(j['at']?.toString() ?? '') ?? DateTime.now(),
      );
}

/// إعدادات التصويت (A11): تُنسخ إلى الجلسة عند إنشائها حتى لا يغيّرها تعديل لاحق
class VotingSettings {
  /// الحد الأدنى للحصص المشاركة حتى يُعتد بالقرار بعد انتهاء المهلة
  final double quorum;

  /// مهلة التصويت على البند بالأيام تبدأ من أول صوت
  final int deadlineDays;

  /// عدد الجولات الفاشلة المتتالية الذي يُعد جموداً
  final int deadlockAfter;

  const VotingSettings({this.quorum = 50, this.deadlineDays = 7, this.deadlockAfter = 2});

  static const defaults = VotingSettings();

  Map<String, dynamic> toJson() => {'quorum': quorum, 'deadlineDays': deadlineDays, 'deadlockAfter': deadlockAfter};

  factory VotingSettings.fromJson(Map<String, dynamic>? j) => j == null
      ? defaults
      : VotingSettings(
          quorum: (j['quorum'] as num?)?.toDouble() ?? 50,
          deadlineDays: (j['deadlineDays'] as num?)?.toInt() ?? 7,
          deadlockAfter: (j['deadlockAfter'] as num?)?.toInt() ?? 2,
        );
}

/// شريك مؤسس ضمن جلسة العقد
class SessionPartner {
  final String id;
  final String name;
  final String nationalId;
  final String phone;
  final double equity;
  final String? partnerClass;
  final String? guardianName;
  final String? guardianshipRef;
  final String email;

  const SessionPartner({
    required this.id,
    required this.name,
    required this.nationalId,
    required this.phone,
    required this.equity,
    this.partnerClass,
    this.guardianName,
    this.guardianshipRef,
    this.email = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (email.isNotEmpty) 'email': email,
        'nationalId': nationalId,
        'phone': phone,
        'equity': equity,
        if (partnerClass != null) 'partnerClass': partnerClass,
        if (guardianName != null) 'guardianName': guardianName,
        if (guardianshipRef != null) 'guardianshipRef': guardianshipRef,
      };

  factory SessionPartner.fromJson(Map<String, dynamic> j) => SessionPartner(
        id: j['id'] as String,
        name: j['name'] as String,
        nationalId: j['nationalId'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        equity: (j['equity'] as num).toDouble(),
        partnerClass: j['partnerClass'] as String?,
        guardianName: j['guardianName'] as String?,
        guardianshipRef: j['guardianshipRef'] as String?,
        email: j['email'] as String? ?? '',
      );
}

/// شاهد على العقد
class Witness {
  final String name;
  final String nationalId;
  final bool internal; // من داخل الشركة أو خارجها
  final String? signaturePng; // base64
  final String phone; // الشاهد المدعو يشهد من جواله برقمه هذا
  final String? draftHash; // إصدار العقد الذي شهد عليه
  final DateTime? attestedAt;
  final ConfirmMethod? method;

  const Witness({
    required this.name,
    required this.nationalId,
    required this.internal,
    this.signaturePng,
    this.phone = '',
    this.draftHash,
    this.attestedAt,
    this.method,
  });

  /// شهد فعلاً (وقّع) أم ما زال مدعواً فقط
  bool get attested => signaturePng != null;

  Witness attest({required String signature, required String hash, required ConfirmMethod by}) => Witness(
        name: name,
        nationalId: nationalId,
        internal: internal,
        phone: phone,
        signaturePng: signature,
        draftHash: hash,
        attestedAt: DateTime.now(),
        method: by,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'nationalId': nationalId,
        'internal': internal,
        'signaturePng': signaturePng,
        'phone': phone,
        'draftHash': draftHash,
        'attestedAt': attestedAt?.toUtc().toIso8601String(),
        'method': method?.name,
      };

  factory Witness.fromJson(Map<String, dynamic> j) => Witness(
        name: j['name'] as String,
        nationalId: j['nationalId'] as String,
        internal: j['internal'] as bool? ?? false,
        signaturePng: j['signaturePng'] as String?,
        phone: j['phone'] as String? ?? '',
        draftHash: j['draftHash'] as String?,
        attestedAt: j['attestedAt'] == null ? null : DateTime.tryParse(j['attestedAt'].toString()),
        method: j['method'] == null ? null : ConfirmMethod.values.byName(j['method'] as String),
      );
}

/// توقيع الشريك النهائي مع إقرار الأهلية
class PartnerSignOff {
  final String partnerId;
  final String signaturePng; // base64
  final DateTime at;
  final ConfirmMethod method;

  /// بصمة مسودة العقد لحظة التوقيع: التوقيع يخص هذا الإصدار تحديداً
  final String draftHash;

  const PartnerSignOff({
    required this.partnerId,
    required this.signaturePng,
    required this.at,
    required this.method,
    this.draftHash = '',
  });

  Map<String, dynamic> toJson() => {
        'partnerId': partnerId,
        'signaturePng': signaturePng,
        'at': at.toIso8601String(),
        'method': method.name,
        'draftHash': draftHash,
      };

  factory PartnerSignOff.fromJson(Map<String, dynamic> j) => PartnerSignOff(
        partnerId: j['partnerId'] as String,
        signaturePng: j['signaturePng'] as String,
        at: DateTime.parse(j['at'] as String),
        method: ConfirmMethod.values.byName(j['method'] as String),
        draftHash: j['draftHash'] as String? ?? '',
      );
}

/// حالة الجلسة
enum SessionStatus { active, suspended, awaitingSignature, completed, withdrawn }

/// نوع الإصدار: التأسيس، أو تعديل قيم بنود، أو تغيير جدول الحصص (من صلح أو حكم أو تخارج)
enum ChangeType { establishment, amendment, capTable }

extension ChangeTypeX on ChangeType {
  String get label => switch (this) {
        ChangeType.establishment => 'عقد التأسيس',
        ChangeType.amendment => 'تعديل بنود',
        ChangeType.capTable => 'تعديل جدول الحصص',
      };
}

extension SessionStatusX on SessionStatus {
  String get label => switch (this) {
        SessionStatus.active => 'جارية',
        SessionStatus.suspended => 'معلّقة',
        SessionStatus.awaitingSignature => 'بانتظار التوقيع',
        SessionStatus.completed => 'مكتملة',
        SessionStatus.withdrawn => 'لم يُعتمد',
      };

  Color get color => switch (this) {
        SessionStatus.active => const Color(0xFF3498DB),
        SessionStatus.suspended => const Color(0xFFF39C12),
        SessionStatus.awaitingSignature => const Color(0xFFC9A227),
        SessionStatus.completed => const Color(0xFF2ECC71),
        SessionStatus.withdrawn => const Color(0xFF7C8CA3),
      };
}

/// جلسة إعداد عقد تأسيس
class ContractSession {
  final String id;
  final String? companyId; // الشركة التي تتبعها جلسة التأسيس
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
  VotingSettings settings;
  List<Witness> witnesses;
  Map<String, PartnerSignOff> signOffs;
  DateTime? completedAt;

  /// بصمة SHA-256 لمحتوى العقد المعتمد؛ أي تعديل لاحق يغيّرها
  String? contentHash;

  // ───── الإصدارات (المرحلة 3) ─────
  /// رقم إصدار العقد: 1 للتأسيس، ثم يزيد مع كل تعديل معتمد
  int version;
  ChangeType changeType;

  /// الإصدار السابق الذي يعدّله هذا الإصدار
  String? amends;
  String? changeSummary;
  String? proposedBy;

  /// النزاع الذي نتج عنه التعديل (صلح أو حكم)
  String? disputeRef;

  /// الإصدار الذي حلّ محل هذا الإصدار؛ عندها يصبح مؤرشفاً للقراءة فقط
  String? supersededBy;
  DateTime? archivedAt;

  bool get archived => supersededBy != null;

  /// أغراض الشركة (بند جوهري)
  String purpose;

  /// تعديل يزيد الأعباء المالية على الشركاء: يتطلب الإجماع (القانون اليمني)
  bool burdenIncrease;
  bool get isAmendment => version > 1;

  ContractSession({
    required this.id,
    this.companyId,
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
    this.settings = VotingSettings.defaults,
    List<Witness>? witnesses,
    Map<String, PartnerSignOff>? signOffs,
    this.completedAt,
    this.contentHash,
    this.version = 1,
    this.changeType = ChangeType.establishment,
    this.amends,
    this.changeSummary,
    this.proposedBy,
    this.disputeRef,
    this.supersededBy,
    this.archivedAt,
    this.purpose = '',
    this.burdenIncrease = false,
  })  : witnesses = witnesses ?? [],
        signOffs = signOffs ?? {};

  int count(ClauseStatus s) => records.where((r) => r.status == s).length;

  /// نسبة الإنجاز: البنود المحسومة (متراضى عليها أو محيّدة) من الإجمالي
  double get progress => records.isEmpty
      ? 0
      : (count(ClauseStatus.agreed) + count(ClauseStatus.neutralized) + count(ClauseStatus.notApplicable)) /
          records.length;

  /// لا يُصدر العقد إلا بعد حسم كافة البنود
  bool get allResolved => records.every((r) =>
      r.status == ClauseStatus.agreed ||
      r.status == ClauseStatus.neutralized ||
      r.status == ClauseStatus.notApplicable);

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyId': companyId,
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
        'settings': settings.toJson(),
        'witnesses': witnesses.map((w) => w.toJson()).toList(),
        'signOffs': signOffs.map((k, v) => MapEntry(k, v.toJson())),
        'completedAt': completedAt?.toIso8601String(),
        'contentHash': contentHash,
        'version': version,
        'changeType': changeType.name,
        'amends': amends,
        'changeSummary': changeSummary,
        'proposedBy': proposedBy,
        'disputeRef': disputeRef,
        'supersededBy': supersededBy,
        'archivedAt': archivedAt?.toUtc().toIso8601String(),
        'purpose': purpose,
        'burdenIncrease': burdenIncrease,
      };

  factory ContractSession.fromJson(Map<String, dynamic> j) => ContractSession(
        id: j['id'] as String,
        companyId: j['companyId'] as String?,
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
        settings: VotingSettings.fromJson(j['settings'] == null ? null : Map<String, dynamic>.from(j['settings'] as Map)),
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
        version: (j['version'] as num?)?.toInt() ?? 1,
        changeType: ChangeType.values.byName(j['changeType'] as String? ?? 'establishment'),
        amends: j['amends'] as String?,
        changeSummary: j['changeSummary'] as String?,
        proposedBy: j['proposedBy'] as String?,
        disputeRef: j['disputeRef'] as String?,
        supersededBy: j['supersededBy'] as String?,
        archivedAt: j['archivedAt'] == null ? null : DateTime.tryParse(j['archivedAt'] as String),
        purpose: j['purpose'] as String? ?? '',
        burdenIncrease: j['burdenIncrease'] as bool? ?? false,
      );
}

/// نتيجة احتساب النصاب لبند
class QuorumResult {
  final double agreeShare; // نسبة الحصص الموافقة من إجمالي الحصص
  final double disagreeShare;
  final double neutralShare;
  final double required; // العتبة
  final double quorum; // الحد الأدنى للمشاركة
  final bool complete; // صوّت كل من يحق له التصويت
  final bool passed; // بلغت الموافقة العتبة
  final DateTime? deadline;
  final bool deadlinePassed;

  const QuorumResult({
    required this.agreeShare,
    required this.disagreeShare,
    required this.neutralShare,
    required this.required,
    this.quorum = 0,
    required this.complete,
    required this.passed,
    this.deadline,
    this.deadlinePassed = false,
  });

  double get participation => agreeShare + disagreeShare + neutralShare;
  bool get quorumMet => participation + 1e-6 >= quorum;

  /// هل يمكن حسم البند الآن: صوّت الجميع، أو انتهت المهلة
  bool get decidable => complete || deadlinePassed;
}

/// فرق بين إصدارين من العقد (P14): القيمة أو الحالة قبل وبعد، والنص عند تغيّره
class VersionDiff {
  final String title;
  final String before;
  final String after;
  final String? textBefore;
  final String? textAfter;

  const VersionDiff({required this.title, required this.before, required this.after, this.textBefore, this.textAfter});
}
