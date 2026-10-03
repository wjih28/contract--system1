import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/questionnaire.dart';
import '../../providers/contract_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

/// لوحة إدارة بنك البنود: عرض البنود وإضافة بنود جديدة بأثرها وشروطها
class QuestionBankScreen extends StatelessWidget {
  const QuestionBankScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ContractState>();
    return Scaffold(
      appBar: AppBar(title: const Text('بنك البنود')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.navyDark,
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const _AddQuestionScreen())),
        icon: const Icon(Icons.add_rounded),
        label: const Text('بند جديد', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        children: [
          const Text(
            'البنود المضافة هنا تظهر في جلسات التأسيس الجديدة. البند المالي يمكن ربطه بشرط رقابي تراقبه المنصة بعد توقيع العقد.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.6),
          ),
          const SizedBox(height: 16),
          ...ClauseCategory.values.expand((c) {
            final items = state.bank.where((q) => q.category == c).toList();
            return [
              SectionHeader(title: 'البنود ال${c.label}ة (${items.length})'),
              const SizedBox(height: 6),
              ...items.map((q) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GoldBorderCard(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(c.icon, color: c.color, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(q.title,
                                    style: const TextStyle(
                                        color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 3),
                                Text(
                                  '${q.scope.label} · ${q.quorum.display} · ${q.effect.label}'
                                  '${q.rule != null ? ' · شرط ${q.rule!.op.symbol}' : ''}',
                                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          if (q.custom)
                            IconButton(
                              onPressed: () => state.removeQuestion(q.id),
                              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                            ),
                        ],
                      ),
                    ),
                  )),
              const SizedBox(height: 12),
            ];
          }),
        ],
      ),
    );
  }
}

class _AddQuestionScreen extends StatefulWidget {
  const _AddQuestionScreen();

  @override
  State<_AddQuestionScreen> createState() => _AddQuestionScreenState();
}

class _AddQuestionScreenState extends State<_AddQuestionScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _text = TextEditingController();
  final _awareness = TextEditingController();
  final _paramLabel = TextEditingController();
  final _default = TextEditingController();
  final _ruleField = TextEditingController();
  final _ruleAction = TextEditingController(text: 'تجميد العملية وتنبيه الشركاء');
  final _quorumText = TextEditingController(text: 'ثلثين');

  ClauseCategory _category = ClauseCategory.legal;
  ClauseScope _scope = ClauseScope.general;
  EffectType _effect = EffectType.textual;
  ParamKind _param = ParamKind.none;
  ComparisonOp _op = ComparisonOp.gt;

  @override
  void dispose() {
    for (final c in [_title, _text, _awareness, _paramLabel, _default, _ruleField, _ruleAction, _quorumText]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'حقل مطلوب' : null;

  void _save() {
    if (!_form.currentState!.validate()) return;
    if (_param != ParamKind.none && !_text.text.contains('{value}')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('أضف {value} في نص البند ليظهر فيه الرقم المتفق عليه')));
      return;
    }
    final state = context.read<ContractState>();
    state.addQuestion(BankQuestion(
      id: state.nextCustomId(),
      category: _category,
      scope: _scope,
      title: _title.text.trim(),
      clauseTemplate: _text.text.trim(),
      awareness: _awareness.text.trim(),
      quorum: QuorumRule.parse(_quorumText.text),
      effect: _effect,
      paramKind: _param,
      paramLabel: _param == ParamKind.none ? null : _paramLabel.text.trim(),
      defaultValue: double.tryParse(_default.text.trim()),
      rule: _effect == EffectType.financial && _ruleField.text.trim().isNotEmpty
          ? RuleTemplate(
              field: 'custom.${_ruleField.text.trim()}',
              fieldLabel: _ruleField.text.trim(),
              op: _op,
              action: _ruleAction.text.trim(),
            )
          : null,
      custom: true,
    ));
    Navigator.pop(context);
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(t,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w700)),
      );

  Widget _chips<T>(List<T> values, T selected, String Function(T) label, ValueChanged<T> onSel) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: values
            .map((v) => ChoiceChip(
                  label: Text(label(v)),
                  selected: v == selected,
                  selectedColor: AppColors.gold,
                  labelStyle: TextStyle(
                      color: v == selected ? AppColors.navyDark : AppColors.textSecondary,
                      fontWeight: FontWeight.w700),
                  backgroundColor: AppColors.navyLight,
                  side: const BorderSide(color: AppColors.divider),
                  onSelected: (_) => setState(() => onSel(v)),
                ))
            .toList(),
      );

  @override
  Widget build(BuildContext context) {
    final parsed = QuorumRule.parse(_quorumText.text);
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة بند')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            TextFormField(controller: _title, validator: _req, decoration: const InputDecoration(labelText: 'عنوان البند')),
            const SizedBox(height: 12),
            TextFormField(
              controller: _text,
              validator: _req,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'نص البند في العقد',
                helperText: 'المتغيرات: {value} القيمة، {partner} اسم الشريك، {capital} رأس المال',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _awareness,
              validator: _req,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'السؤال التوعوي للشركاء'),
            ),
            _label('التصنيف'),
            _chips(ClauseCategory.values, _category, (c) => c.label, (v) => _category = v),
            _label('النطاق'),
            _chips(ClauseScope.values, _scope, (c) => c.label, (v) => _scope = v),
            _label('النصاب'),
            TextFormField(
              controller: _quorumText,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'مثال: ثلثين، إجماع، أغلبية، 75',
                helperText: 'يُخزَّن كنسبة: ${parsed.display}',
              ),
            ),
            _label('نوع الأثر'),
            _chips(EffectType.values, _effect, (c) => c.label, (v) => _effect = v),
            _label('قيمة يحددها الشركاء'),
            _chips(ParamKind.values, _param, (p) => switch (p) {
                  ParamKind.none => 'بدون',
                  ParamKind.money => 'مبلغ',
                  ParamKind.percent => 'نسبة',
                  ParamKind.days => 'أيام',
                  ParamKind.number => 'رقم',
                }, (v) => _param = v),
            if (_param != ParamKind.none) ...[
              const SizedBox(height: 12),
              TextFormField(controller: _paramLabel, validator: _req, decoration: const InputDecoration(labelText: 'وصف القيمة')),
              const SizedBox(height: 12),
              TextFormField(
                controller: _default,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'القيمة المقترحة'),
              ),
            ],
            if (_effect == EffectType.financial) ...[
              _label('الشرط الرقابي (اختياري)'),
              TextFormField(
                controller: _ruleField,
                decoration: const InputDecoration(labelText: 'ما الذي يُفحص؟ مثال: قيمة الفاتورة'),
              ),
              const SizedBox(height: 10),
              _chips(ComparisonOp.values, _op, (o) => '${o.symbol}  ${o.label}', (v) => _op = v),
              const SizedBox(height: 10),
              TextFormField(controller: _ruleAction, decoration: const InputDecoration(labelText: 'الإجراء عند تحقق الشرط')),
            ],
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_rounded),
              label: const Text('حفظ البند'),
            ),
          ],
        ),
      ),
    );
  }
}
