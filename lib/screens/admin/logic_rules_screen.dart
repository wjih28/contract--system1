import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/governance_config.dart';
import '../../models/questionnaire.dart';
import '../../providers/contract_state.dart';
import '../../theme/app_theme.dart';

/// A09: محرر القواعد المنطقية (إذا / و / أو / فإن). القاعدة مستقلة عن النص القانوني ومرتبطة به،
/// ولها إصدارات؛ التنفيذ التاريخي يحتفظ بإصدار القاعدة الذي كان سارياً.
class LogicRulesScreen extends StatelessWidget {
  const LogicRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<ContractState>();
    final qids = st.ruleVersions.map((r) => r.questionId).toSet().toList();
    return Scaffold(
      appBar: AppBar(title: const Text('القواعد المنطقية')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            const StateBanner(
              color: AppColors.info,
              icon: Icons.account_tree_rounded,
              text: 'كل قاعدة تحوّل بنداً مالياً إلى فحص تلقائي للعمليات. اختبار القواعد على عمليات تجريبية يأتي في المرحلة 2 (شاشة A10).',
            ),
            if (qids.isEmpty) const StateView.empty(title: 'لا توجد قواعد', message: 'تُنشأ القواعد من البنود المالية في البنك.'),
            ...qids.map((qid) {
              final latest = st.latestRule(qid)!;
              final pub = st.publishedRule(qid);
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RuleEditorScreen(questionId: qid))),
                  leading: const Icon(Icons.rule_rounded, color: AppColors.gold),
                  title: Text(latest.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    '${latest.id} · ${(pub ?? latest).describe()}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                  ),
                  trailing: Text('ج${pub?.version ?? '—'}${latest.status == ConfigStatus.draft ? ' + مسودة' : ''}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class RuleEditorScreen extends StatefulWidget {
  final String questionId;
  const RuleEditorScreen({super.key, required this.questionId});

  @override
  State<RuleEditorScreen> createState() => _RuleEditorScreenState();
}

class _CondDraft {
  final TextEditingController label;
  final TextEditingController value;
  ComparisonOp op;
  bool useAgreed; // القيمة المتفق عليها في البند
  bool isEvent;
  final String field;

  _CondDraft(RuleCondition c)
      : label = TextEditingController(text: c.fieldLabel),
        value = TextEditingController(text: c.fixedValue?.toString() ?? ''),
        op = c.op,
        useAgreed = c.fixedValue == null,
        isEvent = c.isEvent,
        field = c.field;

  RuleCondition build() => RuleCondition(
        field: field.isEmpty ? 'custom.${label.text.trim()}' : field,
        fieldLabel: label.text.trim(),
        op: op,
        fixedValue: isEvent || useAgreed ? null : double.tryParse(value.text.trim()),
        isEvent: isEvent,
      );
}

class _RuleEditorScreenState extends State<RuleEditorScreen> {
  late final ContractState st = context.read<ContractState>();
  late LogicRule _base = st.latestRule(widget.questionId)!;
  late final _name = TextEditingController(text: _base.name);
  late final _trigger = TextEditingController(text: _base.trigger);
  late final List<_CondDraft> _conds = _base.conditions.map(_CondDraft.new).toList();
  late final List<String> _actions = [..._base.actions];
  late RuleJoin _join = _base.join;
  final _newAction = TextEditingController();
  List<String> _errors = [];

  @override
  void dispose() {
    _name.dispose();
    _trigger.dispose();
    _newAction.dispose();
    for (final c in _conds) {
      c.label.dispose();
      c.value.dispose();
    }
    super.dispose();
  }

  LogicRule _draft() => _base.copyWith(
        name: _name.text.trim(),
        trigger: _trigger.text.trim(),
        conditions: _conds.map((c) => c.build()).toList(),
        join: _join,
        actions: _actions,
      );

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<ContractState>();
    final q = cs.question(widget.questionId);
    final latest = cs.latestRule(widget.questionId)!;
    final draft = _draft();

    return Scaffold(
      appBar: AppBar(title: Text('القاعدة ${latest.id}')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            Text('مرتبطة بالبند: ${q.title} (${latest.clauseId}) · الإصدار المنشور ${cs.publishedRule(widget.questionId)?.version ?? '—'}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(controller: _name, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'اسم القاعدة')),
            const SizedBox(height: 10),
            TextField(
                controller: _trigger,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'الحدث الذي يُطلق الفحص', hintText: 'مثل: عملية مالية جديدة')),
            const SizedBox(height: 18),
            Row(children: [
              const _Chip('إذا', AppColors.info),
              const Spacer(),
              SegmentedButton<RuleJoin>(
                segments: const [
                  ButtonSegment(value: RuleJoin.and, label: Text('و (كل الشروط)')),
                  ButtonSegment(value: RuleJoin.or, label: Text('أو (أي شرط)')),
                ],
                selected: {_join},
                onSelectionChanged: (v) => setState(() => _join = v.first),
              ),
            ]),
            const SizedBox(height: 10),
            ..._conds.asMap().entries.map((e) => _condCard(e.key, e.value, q)),
            TextButton.icon(
              onPressed: () => setState(() => _conds.add(_CondDraft(
                  const RuleCondition(field: '', fieldLabel: '', op: ComparisonOp.gt)))),
              icon: const Icon(Icons.add_rounded),
              label: const Text('إضافة شرط'),
            ),
            const SizedBox(height: 10),
            const _Chip('فإن', AppColors.success),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final a in _actions)
                InputChip(label: Text(a), onDeleted: () => setState(() => _actions.remove(a))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _newAction,
                  decoration: const InputDecoration(hintText: 'إجراء، مثل: تجميد العملية وتنبيه الشركاء', isDense: true),
                ),
              ),
              IconButton(
                onPressed: () {
                  if (_newAction.text.trim().isEmpty) return;
                  setState(() => _actions.add(_newAction.text.trim()));
                  _newAction.clear();
                },
                icon: const Icon(Icons.add_circle_rounded, color: AppColors.gold),
              ),
            ]),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.navySurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('القاعدة بلغة مقروءة', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 12.5)),
                const SizedBox(height: 6),
                Text('عند ${draft.trigger.isEmpty ? '…' : draft.trigger}: ${draft.describe()}',
                    style: const TextStyle(color: AppColors.textPrimary, height: 1.8)),
              ]),
            ),
            if (_errors.isNotEmpty) ...[
              const SizedBox(height: 10),
              ..._errors.map((e) => Text('• $e', style: const TextStyle(color: AppColors.danger))),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _errors = draft.validate());
                    if (_errors.isNotEmpty) return;
                    cs.saveRuleDraft(draft);
                    _base = cs.latestRule(widget.questionId)!;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حُفظت مسودة القاعدة')));
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('تحقق واحفظ مسودة'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: latest.status == ConfigStatus.draft
                      ? () {
                          final errs = cs.publishRule(widget.questionId);
                          setState(() => _errors = errs);
                          if (errs.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                content: Text('نُشرت القاعدة، وتسري على جلسات التأسيس الجديدة')));
                          }
                        }
                      : null,
                  icon: const Icon(Icons.publish_rounded),
                  label: const Text('نشر'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _condCard(int i, _CondDraft c, BankQuestion q) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.navySurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: c.label,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'الحقل', hintText: 'مثل: قيمة العملية الواحدة', isDense: true),
              ),
            ),
            IconButton(
              onPressed: () => setState(() => _conds.removeAt(i)),
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
            ),
          ]),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: c.isEvent,
            onChanged: (v) => setState(() => c.isEvent = v),
            title: const Text('شرط حدث بلا قيمة (مثل: حدوث سلفة شخصية)', style: TextStyle(fontSize: 12.5)),
          ),
          if (!c.isEvent)
            Row(children: [
              DropdownButton<ComparisonOp>(
                value: c.op,
                dropdownColor: AppColors.navySurface,
                items: ComparisonOp.values
                    .map((o) => DropdownMenuItem(value: o, child: Text('${o.symbol}  ${o.label}')))
                    .toList(),
                onChanged: (v) => setState(() => c.op = v!),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: c.useAgreed
                    ? Text('القيمة المتفق عليها في البند${q.paramLabel == null ? '' : ' (${q.paramLabel})'}',
                        style: const TextStyle(color: AppColors.gold, fontSize: 12.5))
                    : TextField(
                        controller: c.value,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(labelText: 'قيمة ثابتة', isDense: true),
                      ),
              ),
              IconButton(
                tooltip: c.useAgreed ? 'استخدام قيمة ثابتة' : 'استخدام القيمة المتفق عليها',
                onPressed: () => setState(() => c.useAgreed = !c.useAgreed),
                icon: Icon(c.useAgreed ? Icons.pin_rounded : Icons.handshake_rounded),
              ),
            ]),
        ]),
      );
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w900)),
      );
}
