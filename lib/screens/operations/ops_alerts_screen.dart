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
import '../disputes/dispute_detail_screen.dart';
import 'approvals_screen.dart';
import 'decision_execution_screen.dart';
import 'payroll_screen.dart';
import 'plans_screen.dart';
import 'tx_detail_screen.dart';
import 'tx_widgets.dart';
import 'violations_screen.dart';

/// O17: التنبيهات التشغيلية. العمليات المجمّدة، والمهل القريبة، والمخالفات، والانحرافات،
/// مع الإقرار والإسناد والتأجيل والحل. التنبيه لا يحل محل سجل التدقيق والإشعارات الرسمية.
class OpsAlertsScreen extends StatefulWidget {
  const OpsAlertsScreen({super.key});

  @override
  State<OpsAlertsScreen> createState() => _OpsAlertsScreenState();
}

class _OpsAlertsScreenState extends State<OpsAlertsScreen> {
  AlertStatus? _filter = AlertStatus.open;

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final daily = context.watch<DailyOpsState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final all = daily.alerts(c, context.watch<ContractState>(), context.watch<DisputeState>(), context.watch<OperationsState>());
    final list = all.where((a) => _filter == null || daily.statusOf(a.id) == _filter).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('التنبيهات التشغيلية')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in AlertStatus.values)
                ChoiceChip(
                  label: Text('${s.label} (${all.where((a) => daily.statusOf(a.id) == s).length})'),
                  selected: _filter == s,
                  onSelected: (_) => setState(() => _filter = s),
                ),
              ChoiceChip(label: Text('الكل (${all.length})'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
            ]),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const StateView.empty(icon: Icons.notifications_off_rounded, title: 'لا توجد تنبيهات هنا', message: ''),
            for (final a in list) _AlertCard(c: c, a: a),
          ],
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final Company c;
  final OpsAlert a;
  const _AlertCard({required this.c, required this.a});

  @override
  Widget build(BuildContext context) {
    final daily = context.read<DailyOpsState>();
    final s = daily.statusOf(a.id);
    final st = daily.alertState(a.id);
    final near = a.deadline != null && a.deadline!.difference(DateTime.now()).inHours < 48;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(a.type, style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 12.5))),
            Text(s.label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ]),
          const SizedBox(height: 2),
          Text(a.title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
          Text(a.detail, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.5)),
          Text(
            '${txTime.format(a.created.toLocal())} · الدور المعني: ${st?.assignedRole ?? a.role}'
            '${a.deadline == null ? '' : ' · المهلة ${txTime.format(a.deadline!.toLocal())}'}',
            style: TextStyle(color: near ? AppColors.danger : AppColors.textMuted, fontSize: 11.5),
          ),
          Wrap(spacing: 0, children: [
            TextButton(onPressed: () => _open(context), child: const Text('فتح')),
            if (s == AlertStatus.open) TextButton(onPressed: () => daily.setAlert(c, a, AlertStatus.acknowledged), child: const Text('اطّلعت')),
            if (s != AlertStatus.resolved)
              TextButton(
                  onPressed: () => daily.setAlert(c, a, AlertStatus.acknowledged, snooze: const Duration(hours: 24)),
                  child: const Text('تأجيل يوماً')),
            if (s != AlertStatus.resolved) TextButton(onPressed: () => _assign(context), child: const Text('إسناد')),
            if (s != AlertStatus.resolved) TextButton(onPressed: () => daily.setAlert(c, a, AlertStatus.resolved), child: const Text('حُلّ')),
          ]),
        ]),
      ),
    );
  }

  void _open(BuildContext context) {
    final Widget? w = switch (a.relatedType) {
      'transaction' => TxDetailScreen(txId: a.relatedId),
      'exception' => const ApprovalsScreen(),
      'violation' => const ViolationsScreen(),
      'dispute' => DisputeDetailScreen(disputeId: a.relatedId),
      'payroll' => PayrollBatchScreen(batchId: a.relatedId),
      'plan' => PlanDetailScreen(planId: a.relatedId),
      'execution' => const DecisionExecutionScreen(),
      _ => null,
    };
    if (w != null) Navigator.push(context, MaterialPageRoute(builder: (_) => w));
  }

  Future<void> _assign(BuildContext context) async {
    final roles = ['المدير التنفيذي', 'المدير المالي', 'مدير القسم', 'الشريك المدير'];
    final r = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.navySurface,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final x in roles) ListTile(title: Text(x), onTap: () => Navigator.pop(ctx, x)),
        ]),
      ),
    );
    if (r != null && context.mounted) context.read<DailyOpsState>().setAlert(c, a, AlertStatus.escalated, role: r);
  }
}
