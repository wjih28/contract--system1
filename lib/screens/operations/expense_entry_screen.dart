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
import '../../theme/app_theme.dart';
import 'tx_detail_screen.dart';

/// O03: إدخال مصروف يدوي مع معاينة فحص القواعد قبل الإرسال.
/// الإرسال لا يعني الموافقة؛ النتيجة تظهر بعد التقييم.
class ExpenseEntryScreen extends StatefulWidget {
  const ExpenseEntryScreen({super.key});

  @override
  State<ExpenseEntryScreen> createState() => _ExpenseEntryScreenState();
}

class _ExpenseEntryScreenState extends State<ExpenseEntryScreen> {
  final _amount = TextEditingController();
  final _payee = TextEditingController();
  final _purpose = TextEditingController();
  final _ref = TextEditingController();
  TxCategory _cat = TxCategory.purchase;
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    for (final c in [_amount, _payee, _purpose, _ref]) {
      c.dispose();
    }
    super.dispose();
  }

  FinancialTx? _draft(String companyId, String createdBy, AppCurrency c) {
    final a = double.tryParse(_amount.text.trim());
    if (a == null || a <= 0) return null;
    return FinancialTx(
      id: 'T${DateTime.now().millisecondsSinceEpoch}',
      companyId: companyId,
      date: _date,
      amount: a,
      currency: c,
      category: _cat,
      payee: _payee.text.trim(),
      purpose: _purpose.text.trim(),
      reference: _ref.text.trim(),
      createdBy: createdBy,
      createdAt: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final st = context.watch<ContractState>();
    final ops = context.watch<OperationsState>();
    final c = cs.current;
    if (c == null) return const Scaffold(body: StateView.empty(title: 'لا توجد شركة', message: ''));
    final rules = ops.activeRules(st, c.id);
    final d = _draft(c.id, cs.me?.id ?? '', c.currency);
    final preview = d == null ? null : ops.preview(st, c, d);

    return Scaffold(
      appBar: AppBar(title: const Text('إدخال عملية مالية')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            if (rules.isEmpty)
              const StateBanner(
                color: AppColors.warning,
                icon: Icons.warning_amber_rounded,
                text: 'لا يوجد عقد معتمد لهذه الشركة بعد، فلا توجد قواعد سارية للفحص. اعتمدوا العقد أولاً من رحلة التأسيس.',
              ),
            DropdownButtonFormField<TxCategory>(
              initialValue: _cat,
              isExpanded: true,
              dropdownColor: AppColors.navySurface,
              decoration: const InputDecoration(labelText: 'الفئة'),
              items: TxCategory.values.map((x) => DropdownMenuItem(value: x, child: Text(x.label))).toList(),
              onChanged: (v) => setState(() => _cat = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: InputDecoration(labelText: 'المبلغ', suffixText: c.currency.code),
            ),
            const SizedBox(height: 12),
            TextField(controller: _payee, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'المستفيد')),
            const SizedBox(height: 12),
            TextField(controller: _purpose, decoration: const InputDecoration(labelText: 'الغرض')),
            const SizedBox(height: 12),
            TextField(controller: _ref, decoration: const InputDecoration(labelText: 'رقم الفاتورة أو المرجع (اختياري)')),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded, color: AppColors.gold),
              title: Text('التاريخ: ${_date.year}/${_date.month}/${_date.day}'),
              trailing: TextButton(
                onPressed: () async {
                  final p = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (p != null) setState(() => _date = p);
                },
                child: const Text('تغيير'),
              ),
            ),
            const SizedBox(height: 10),
            const Text('معاينة الفحص قبل الإرسال',
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (preview == null)
              const Text('أدخل المبلغ لمعاينة نتيجة الفحص.', style: TextStyle(color: AppColors.textMuted))
            else if (preview.isEmpty)
              const StateBanner(color: AppColors.success, icon: Icons.check_circle_rounded, text: 'لا تنطبق أي قاعدة: ستُقبل العملية.')
            else
              ...preview.map((h) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: RuleEvaluationCard(
                      ruleId: h.ruleId,
                      condition: h.condition,
                      observed: h.observed,
                      expected: h.expected,
                      result: h.triggered ? (h.autoViolation ? GovStatus.violation : GovStatus.frozen) : GovStatus.approved,
                      action: h.action,
                    ),
                  )),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: d == null || _payee.text.trim().isEmpty
                  ? null
                  : () {
                      final saved = ops.submit(st, c, d, actorName: cs.me?.name ?? '');
                      Navigator.pushReplacement(
                          context, MaterialPageRoute(builder: (_) => TxDetailScreen(txId: saved.id)));
                    },
              icon: const Icon(Icons.send_rounded),
              label: const Text('إرسال للفحص'),
            ),
          ],
        ),
      ),
    );
  }
}
