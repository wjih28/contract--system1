import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/gov_status.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/operations.dart';
import '../../models/questionnaire.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../providers/operations_state.dart';
import '../../services/rule_engine.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

/// A10: شاشة اختبار القواعد. محاكاة عملية مقابل قواعد العقد السارية وعرض مسار التقييم.
/// وضع الاختبار لا يسجّل أي عملية حقيقية ولا يرسل إشعارات.
class RuleTestScreen extends StatefulWidget {
  const RuleTestScreen({super.key});

  @override
  State<RuleTestScreen> createState() => _RuleTestScreenState();
}

class _RuleTestScreenState extends State<RuleTestScreen> {
  final _amount = TextEditingController(text: '3500');
  final _month = TextEditingController(text: '0');
  TxCategory _cat = TxCategory.purchase;
  List<RuleCheck>? _result;

  @override
  void dispose() {
    _amount.dispose();
    _month.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final st = context.watch<ContractState>();
    final ops = context.watch<OperationsState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final rules = ops.activeRules(st, c.id);

    return Scaffold(
      appBar: AppBar(title: const Text('اختبار القواعد')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            const StateBanner(
              color: AppColors.info,
              icon: Icons.science_rounded,
              text: 'وضع اختبار معزول: لا يسجّل عمليات ولا يرسل إشعارات.',
            ),
            Text('القواعد السارية من العقد المعتمد: ${rules.length}',
                style: const TextStyle(color: AppColors.textSecondary)),
            if (rules.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('اعتمدوا العقد أولاً لتظهر القواعد السارية.', style: TextStyle(color: AppColors.warning)),
              ),
            const SizedBox(height: 14),
            DropdownButtonFormField<TxCategory>(
              initialValue: _cat,
              isExpanded: true,
              dropdownColor: AppColors.navySurface,
              decoration: const InputDecoration(labelText: 'فئة العملية'),
              items: TxCategory.values.map((x) => DropdownMenuItem(value: x, child: Text(x.label))).toList(),
              onChanged: (v) => setState(() => _cat = v!),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: InputDecoration(labelText: 'المبلغ', suffixText: c.currency.code),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _month,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: InputDecoration(labelText: 'مصروفات الشهر المقبولة قبل هذه العملية', suffixText: c.currency.code),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () {
                final tx = FinancialTx(
                  id: 'TEST',
                  companyId: c.id,
                  date: DateTime.now(),
                  amount: double.tryParse(_amount.text) ?? 0,
                  currency: c.currency,
                  category: _cat,
                  payee: 'اختبار',
                  purpose: 'اختبار',
                  createdBy: 'test',
                  createdAt: DateTime.now(),
                );
                setState(() => _result = RuleEngine.evaluate(tx, rules, monthOutflow: double.tryParse(_month.text) ?? 0));
              },
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('تشغيل الاختبار'),
            ),
            if (_result != null) ...[
              const SizedBox(height: 18),
              StateBanner(
                color: RuleEngine.outcome(_result!).color,
                icon: RuleEngine.outcome(_result!).icon,
                text: 'النتيجة: ${RuleEngine.outcome(_result!).label} · '
                    '${_result!.where((r) => r.triggered).length} من ${_result!.length} قواعد انطبقت وتحققت شروطها'
                    '${_result!.isEmpty ? ' (لا توجد قاعدة تخص هذه الفئة)' : ''}',
              ),
              ..._result!.map((h) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: RuleEvaluationCard(
                      ruleId: h.ruleId,
                      condition: h.condition,
                      observed: h.observed,
                      expected: h.expected,
                      result: h.triggered ? (h.autoViolation ? GovStatus.violation : GovStatus.frozen) : GovStatus.approved,
                      action: h.action,
                      ruleVersion: 'الإصدار ${h.ruleVersion}',
                    ),
                  )),
              Text('صيغة المبلغ: ${formatCurrency(double.tryParse(_amount.text) ?? 0, c.currency)}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
            ],
          ],
        ),
      ),
    );
  }
}
