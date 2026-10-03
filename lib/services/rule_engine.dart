import '../models/governance_config.dart';
import '../models/operations.dart';
import '../models/questionnaire.dart';

/// قاعدة سارية مستخرجة من العقد المعتمد: القاعدة كما كانت منشورة عند التأسيس + القيمة المتفق عليها
class ActiveRule {
  final LogicRule rule;
  final double? agreedValue;
  final String valueLabel;

  const ActiveRule({required this.rule, required this.agreedValue, required this.valueLabel});
}

/// محرك الفحص (Gate Logic): كل عملية تمر بقواعد العقد قبل اعتبارها متوافقة.
/// دالة نقية بلا حالة، حتى تكون نتيجتها قابلة للتكرار في شاشة الاختبار والتدقيق.
class RuleEngine {
  RuleEngine._();

  /// القواعد السارية من جلسة تأسيس معتمدة
  static List<ActiveRule> activeRules(ContractSession s, String Function(BankQuestion q, double? v) fmt,
      BankQuestion Function(String id) question) {
    if (s.status != SessionStatus.completed) return const [];
    final out = <ActiveRule>[];
    for (final r in s.records) {
      if (r.status != ClauseStatus.agreed || r.rule == null) continue;
      final q = question(r.questionId);
      out.add(ActiveRule(rule: LogicRule.fromJson(r.rule!), agreedValue: r.value, valueLabel: fmt(q, r.value)));
    }
    return out;
  }

  /// قيمة الحقل المرصودة لعملية معينة؛ null = الحقل لا يخص هذه العملية
  static double? _observe(String field, FinancialTx tx, double monthOutflow) {
    final out = tx.category.isOutflow;
    switch (field) {
      case 'transaction.amount':
        return out && tx.category != TxCategory.contract ? tx.amount : null;
      case 'monthly.expenses':
        return out ? monthOutflow + tx.amount : null;
      case 'contract.value':
        return tx.category == TxCategory.contract ? tx.amount : null;
      case 'transaction.type=personal_advance':
        return tx.category == TxCategory.personalAdvance ? 1 : null;
      case 'payroll.manager_change':
        return tx.category == TxCategory.salaryChange ? 1 : null;
      case 'losses.ratio':
        return null; // يُقاس من القوائم المالية لا من عملية منفردة
      default:
        return out ? tx.amount : null; // قواعد مخصصة: تُطبق على قيمة العملية
    }
  }

  static String _n(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);

  /// تقييم عملية مقابل كل القواعد السارية
  static List<RuleCheck> evaluate(FinancialTx tx, List<ActiveRule> rules, {required double monthOutflow}) {
    final checks = <RuleCheck>[];
    for (final ar in rules) {
      final rule = ar.rule;
      final results = <bool>[];
      final observed = <String>[];
      final expected = <String>[];
      for (final c in rule.conditions) {
        final v = _observe(c.field, tx, monthOutflow);
        if (v == null) continue;
        if (c.isEvent) {
          results.add(true);
          observed.add('${c.fieldLabel}: نعم');
          expected.add('غير مسموح دون موافقة');
          continue;
        }
        final limit = c.fixedValue ?? ar.agreedValue;
        if (limit == null) continue;
        results.add(c.op.evaluate(v, limit));
        observed.add('${c.fieldLabel}: ${_n(v)}');
        expected.add('${c.op.symbol} ${c.fixedValue == null ? ar.valueLabel : _n(limit)}');
      }
      if (results.isEmpty) continue; // القاعدة لا تخص هذه العملية
      final hit = rule.join == RuleJoin.and ? results.every((x) => x) : results.any((x) => x);
      final action = rule.actions.join('، ثم ');
      checks.add(RuleCheck(
        ruleId: rule.id,
        ruleVersion: rule.version,
        ruleName: rule.name,
        condition: rule.describe(value: (_) => ar.valueLabel),
        observed: observed.join(' · '),
        expected: expected.join(' · '),
        triggered: hit,
        action: hit ? action : 'لا إجراء: العملية ضمن حدود العقد',
        autoViolation: hit && (action.contains('رفض') || action.contains('خرق')),
      ));
    }
    return checks;
  }

  /// الحالة الناتجة: خرق تلقائي، أو تجميد للمراجعة، أو مسموح
  static TxStatus outcome(List<RuleCheck> checks) {
    if (checks.any((c) => c.autoViolation)) return TxStatus.violation;
    if (checks.any((c) => c.triggered)) return TxStatus.frozen;
    return TxStatus.allowed;
  }
}
