import 'package:flutter/material.dart';

import 'questionnaire.dart';

/// دورة حياة عناصر الإعداد (الأسئلة، البنود، القواعد): لا يُعدَّل المنشور، بل يُنشأ إصدار جديد
enum ConfigStatus { draft, published, retired }

extension ConfigStatusX on ConfigStatus {
  String get label => switch (this) {
        ConfigStatus.draft => 'مسودة',
        ConfigStatus.published => 'منشور',
        ConfigStatus.retired => 'موقوف للمستقبل',
      };

  Color get color => switch (this) {
        ConfigStatus.draft => const Color(0xFFB7C0CF),
        ConfigStatus.published => const Color(0xFF2ECC71),
        ConfigStatus.retired => const Color(0xFF7C8CA3),
      };
}

/// A08: بند قانوني في المكتبة. نص مقروء بمتغيرات، مرتبط بسؤال، وله إصدارات.
class LegalClause {
  final String id;
  final String questionId;
  final String title;
  final String text; // يقبل {value} {capital} {partner} {currency}
  final ClauseCategory category;
  final int version;
  final ConfigStatus status;
  final DateTime updatedAt;

  const LegalClause({
    required this.id,
    required this.questionId,
    required this.title,
    required this.text,
    required this.category,
    this.version = 1,
    this.status = ConfigStatus.published,
    required this.updatedAt,
  });

  LegalClause copyWith({String? title, String? text, int? version, ConfigStatus? status}) => LegalClause(
        id: id,
        questionId: questionId,
        title: title ?? this.title,
        text: text ?? this.text,
        category: category,
        version: version ?? this.version,
        status: status ?? this.status,
        updatedAt: DateTime.now(),
      );

  /// المتغيرات المستخدمة في النص (تظهر كرقائق في المحرر)
  List<String> get variables =>
      RegExp(r'\{(\w+)\}').allMatches(text).map((m) => m.group(1)!).toSet().toList();

  Map<String, dynamic> toJson() => {
        'id': id,
        'questionId': questionId,
        'title': title,
        'text': text,
        'category': category.name,
        'version': version,
        'status': status.name,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory LegalClause.fromJson(Map<String, dynamic> j) => LegalClause(
        id: j['id'] as String,
        questionId: j['questionId'] as String,
        title: j['title'] as String,
        text: j['text'] as String,
        category: ClauseCategory.values.byName(j['category'] as String),
        version: (j['version'] as num?)?.toInt() ?? 1,
        status: ConfigStatus.values.byName(j['status'] as String? ?? 'published'),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

/// شرط في قاعدة منطقية: الحقل، المعامل، والقيمة (قيمة البند المتفق عليها أو رقم ثابت)
class RuleCondition {
  final String field;
  final String fieldLabel;
  final ComparisonOp op;
  final double? fixedValue; // null = القيمة التي اتفق عليها الشركاء في البند

  /// شرط حدث بلا قيمة، مثل "عملية سلفة شخصية"
  final bool isEvent;

  const RuleCondition({
    required this.field,
    required this.fieldLabel,
    required this.op,
    this.fixedValue,
    this.isEvent = false,
  });

  Map<String, dynamic> toJson() =>
      {'field': field, 'fieldLabel': fieldLabel, 'op': op.name, 'fixedValue': fixedValue, 'isEvent': isEvent};

  factory RuleCondition.fromJson(Map<String, dynamic> j) => RuleCondition(
        field: j['field'] as String,
        fieldLabel: j['fieldLabel'] as String,
        op: ComparisonOp.values.byName(j['op'] as String),
        fixedValue: (j['fixedValue'] as num?)?.toDouble(),
        isEvent: j['isEvent'] as bool? ?? false,
      );
}

enum RuleJoin { and, or }

extension RuleJoinX on RuleJoin {
  String get label => this == RuleJoin.and ? 'و' : 'أو';
}

/// A09: قاعدة منطقية قابلة للتنفيذ مشتقة من بند. مستقلة عن النص القانوني ومرتبطة به.
/// إذا (الشروط) فإن (الإجراءات)
class LogicRule {
  final String id;
  final String name;
  final String questionId;
  final String clauseId;
  final String trigger; // الحدث الذي يُطلق الفحص
  final List<RuleCondition> conditions;
  final RuleJoin join;
  final List<String> actions;
  final int priority;
  final int version;
  final ConfigStatus status;

  const LogicRule({
    required this.id,
    required this.name,
    required this.questionId,
    required this.clauseId,
    this.trigger = 'عملية مالية جديدة',
    required this.conditions,
    this.join = RuleJoin.and,
    required this.actions,
    this.priority = 1,
    this.version = 1,
    this.status = ConfigStatus.published,
  });

  LogicRule copyWith({
    String? name,
    String? trigger,
    List<RuleCondition>? conditions,
    RuleJoin? join,
    List<String>? actions,
    int? priority,
    int? version,
    ConfigStatus? status,
  }) =>
      LogicRule(
        id: id,
        name: name ?? this.name,
        questionId: questionId,
        clauseId: clauseId,
        trigger: trigger ?? this.trigger,
        conditions: conditions ?? this.conditions,
        join: join ?? this.join,
        actions: actions ?? this.actions,
        priority: priority ?? this.priority,
        version: version ?? this.version,
        status: status ?? this.status,
      );

  /// أخطاء التحقق قبل النشر
  List<String> validate() => [
        if (name.trim().isEmpty) 'اسم القاعدة مطلوب',
        if (conditions.isEmpty) 'أضف شرطاً واحداً على الأقل',
        if (actions.isEmpty) 'أضف إجراءً واحداً على الأقل',
        if (conditions.any((c) => c.fieldLabel.trim().isEmpty)) 'كل شرط يحتاج حقلاً',
      ];

  /// صياغة مقروءة: إذا ... و ... فإن ...
  String describe({String Function(double? v)? value}) {
    final conds = conditions
        .map((c) => c.isEvent
            ? 'حدثت ${c.fieldLabel}'
            : '${c.fieldLabel} ${c.op.symbol} ${c.fixedValue == null ? (value?.call(null) ?? 'القيمة المتفق عليها') : _num(c.fixedValue!)}')
        .join(' ${join.label} ');
    return 'إذا كان $conds: ${actions.join('، ثم ')}';
  }

  static String _num(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'questionId': questionId,
        'clauseId': clauseId,
        'trigger': trigger,
        'conditions': conditions.map((c) => c.toJson()).toList(),
        'join': join.name,
        'actions': actions,
        'priority': priority,
        'version': version,
        'status': status.name,
      };

  factory LogicRule.fromJson(Map<String, dynamic> j) => LogicRule(
        id: j['id'] as String,
        name: j['name'] as String,
        questionId: j['questionId'] as String,
        clauseId: j['clauseId'] as String,
        trigger: j['trigger'] as String? ?? 'عملية مالية جديدة',
        conditions: (j['conditions'] as List)
            .map((c) => RuleCondition.fromJson(Map<String, dynamic>.from(c as Map)))
            .toList(),
        join: RuleJoin.values.byName(j['join'] as String? ?? 'and'),
        actions: (j['actions'] as List).map((a) => a as String).toList(),
        priority: (j['priority'] as num?)?.toInt() ?? 1,
        version: (j['version'] as num?)?.toInt() ?? 1,
        status: ConfigStatus.values.byName(j['status'] as String? ?? 'published'),
      );
}

/// A07: شرط ظهور سؤال بناءً على نتيجة سؤال آخر
enum ConditionKind { agreed, notAgreed, valueCompare }

class QuestionCondition {
  final String sourceQuestionId;
  final ConditionKind kind;
  final ComparisonOp? op;
  final double? value;

  const QuestionCondition({required this.sourceQuestionId, required this.kind, this.op, this.value});

  String describe(String sourceTitle) => switch (kind) {
        ConditionKind.agreed => 'يظهر إذا اعتُمد بند "$sourceTitle"',
        ConditionKind.notAgreed => 'يظهر إذا لم يُعتمد بند "$sourceTitle"',
        ConditionKind.valueCompare =>
          'يظهر إذا كانت قيمة "$sourceTitle" ${op?.label ?? ''} ${value?.toStringAsFixed(value! % 1 == 0 ? 0 : 2) ?? ''}',
      };

  Map<String, dynamic> toJson() =>
      {'sourceQuestionId': sourceQuestionId, 'kind': kind.name, 'op': op?.name, 'value': value};

  factory QuestionCondition.fromJson(Map<String, dynamic> j) => QuestionCondition(
        sourceQuestionId: j['sourceQuestionId'] as String,
        kind: ConditionKind.values.byName(j['kind'] as String),
        op: j['op'] == null ? null : ComparisonOp.values.byName(j['op'] as String),
        value: (j['value'] as num?)?.toDouble(),
      );
}

/// A12: إعداد العملة
class CurrencySetting {
  final AppCurrency currency;
  final bool enabled;
  final int decimals;

  const CurrencySetting({required this.currency, this.enabled = true, this.decimals = 0});

  Map<String, dynamic> toJson() => {'currency': currency.name, 'enabled': enabled, 'decimals': decimals};

  factory CurrencySetting.fromJson(Map<String, dynamic> j) => CurrencySetting(
        currency: AppCurrency.values.byName(j['currency'] as String),
        enabled: j['enabled'] as bool? ?? true,
        decimals: (j['decimals'] as num?)?.toInt() ?? 0,
      );
}
