import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/company.dart';
import '../../models/ops_extra.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../providers/daily_ops_state.dart';
import '../../providers/dispute_state.dart';
import '../../providers/operations_state.dart';
import '../../theme/app_theme.dart';
import 'tx_widgets.dart';

/// O11: تنفيذ القرارات. كل قرار معتمد (إصدار عقد، حسم نزاع، استثناء) يتحول إلى مهمة لها مسؤول
/// ومهلة ودليل إنجاز. هذه الشاشة لا تغيّر نتيجة القرار؛ الإكمال يتطلب دليلاً.
class DecisionExecutionScreen extends StatefulWidget {
  const DecisionExecutionScreen({super.key});

  @override
  State<DecisionExecutionScreen> createState() => _DecisionExecutionScreenState();
}

class _DecisionExecutionScreenState extends State<DecisionExecutionScreen> {
  ExecStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final daily = context.watch<DailyOpsState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final all = daily.decisions(c, context.watch<ContractState>(), context.watch<DisputeState>(), context.watch<OperationsState>());
    final list = all.where((d) => _filter == null || daily.executionOf(d.id).status == _filter).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('تنفيذ القرارات')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(label: Text('الكل (${all.length})'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
              for (final s in ExecStatus.values)
                ChoiceChip(
                  label: Text('${s.label} (${all.where((d) => daily.executionOf(d.id).status == s).length})'),
                  selected: _filter == s,
                  onSelected: (_) => setState(() => _filter = s),
                ),
            ]),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const StateView.empty(
                icon: Icons.task_alt_rounded,
                title: 'لا توجد قرارات للتنفيذ',
                message: 'تظهر هنا القرارات المعتمدة: إصدارات العقد الجديدة، وحسم النزاعات، والاستثناءات المعتمدة.',
              ),
            for (final d in list) _DecisionCard(c: c, d: d, e: daily.executionOf(d.id)),
          ],
        ),
      ),
    );
  }
}

class _DecisionCard extends StatelessWidget {
  final Company c;
  final ApprovedDecision d;
  final Execution e;
  const _DecisionCard({required this.c, required this.d, required this.e});

  @override
  Widget build(BuildContext context) {
    final daily = context.read<DailyOpsState>();
    final late = e.deadline != null && e.deadline!.isBefore(DateTime.now()) && e.status != ExecStatus.completed;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(d.type, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800))),
            Text(e.status.label, style: TextStyle(color: e.status.color, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ]),
          const SizedBox(height: 4),
          Text('النتيجة المعتمدة: ${d.result}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.5)),
          Text('الإجراء المطلوب: ${d.requiredAction}', style: const TextStyle(color: AppColors.gold, fontSize: 12.5, height: 1.5)),
          const SizedBox(height: 4),
          Text(
            'السريان ${txDate.format(d.effective)}${e.owner.isEmpty ? '' : ' · المسؤول ${e.owner}'}'
            '${e.deadline == null ? '' : ' · المهلة ${txDate.format(e.deadline!)}${late ? ' (متأخر)' : ''}'}'
            '${e.evidence.isEmpty ? '' : ' · ${e.evidence.length} أدلة'}${e.issue == null || e.issue!.isEmpty ? '' : '\nالعائق: ${e.issue}'}',
            style: TextStyle(color: late ? AppColors.danger : AppColors.textMuted, fontSize: 11.5, height: 1.5),
          ),
          if (e.status != ExecStatus.completed)
            Wrap(spacing: 4, children: [
              if (e.status == ExecStatus.pending)
                TextButton.icon(
                  onPressed: () => _start(context),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('بدء التنفيذ'),
                ),
              TextButton.icon(
                onPressed: () async {
                  final t = await _ask(context, 'دليل الإنجاز', 'وصف الدليل أو رقم المستند');
                  if (t != null) daily.updateExecution(c, d, evidence: t);
                },
                icon: const Icon(Icons.attach_file_rounded, size: 18),
                label: const Text('إرفاق دليل'),
              ),
              TextButton.icon(
                onPressed: e.evidence.isEmpty ? null : () => daily.updateExecution(c, d, status: ExecStatus.completed),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(e.evidence.isEmpty ? 'الإكمال يتطلب دليلاً' : 'تم التنفيذ'),
              ),
              TextButton.icon(
                onPressed: () async {
                  final t = await _ask(context, 'الإبلاغ عن عائق', 'ما الذي يمنع التنفيذ؟');
                  if (t != null) daily.updateExecution(c, d, status: ExecStatus.blocked, issue: t);
                },
                icon: const Icon(Icons.report_problem_rounded, size: 18),
                label: const Text('عائق'),
              ),
            ]),
        ]),
      ),
    );
  }

  Future<void> _start(BuildContext context) async {
    final daily = context.read<DailyOpsState>();
    final owner = TextEditingController(text: context.read<CompanyState>().me?.name ?? '');
    final days = TextEditingController(text: '7');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navySurface,
        title: const Text('بدء التنفيذ'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: owner, decoration: const InputDecoration(labelText: 'المسؤول')),
          TextField(controller: days, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المهلة (أيام)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('بدء')),
        ],
      ),
    );
    if (ok == true) {
      daily.updateExecution(c, d,
          status: ExecStatus.inProgress,
          owner: owner.text.trim(),
          deadline: DateTime.now().add(Duration(days: int.tryParse(days.text) ?? 7)));
    }
    owner.dispose();
    days.dispose();
  }
}

Future<String?> _ask(BuildContext context, String title, String label) async {
  final t = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.navySurface,
      title: Text(title),
      content: TextField(controller: t, decoration: InputDecoration(labelText: label)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
      ],
    ),
  );
  final v = t.text.trim();
  t.dispose();
  return ok == true && v.isNotEmpty ? v : null;
}
