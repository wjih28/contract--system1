import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/operations.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../providers/operations_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import 'expense_entry_screen.dart';
import 'transactions_screen.dart';
import 'tx_detail_screen.dart';
import 'tx_widgets.dart';
import 'violations_screen.dart';

/// O01: لوحة التشغيل اليومية: ما الذي يحتاج إجراء وما الذي محجوز. اللوحة لا تتجاوز بوابة الفحص.
class OpsDashboardScreen extends StatelessWidget {
  const OpsDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final st = context.watch<ContractState>();
    final ops = context.watch<OperationsState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final now = DateTime.now();
    final tx = ops.txFor(c.id);
    final today = tx.where((t) => t.createdAt.year == now.year && t.createdAt.month == now.month && t.createdAt.day == now.day).length;
    final frozen = tx.where((t) => t.status == TxStatus.frozen || t.status == TxStatus.exceptionPending).toList();
    final openViolations = ops.violationsFor(c.id).where((v) => v.status != ViolationStatus.resolved).length;
    final month = ops.monthOutflow(c.id, now, c.currency);
    final cap = ops
        .activeRules(st, c.id)
        .where((r) => r.rule.conditions.any((x) => x.field == 'monthly.expenses'))
        .map((r) => r.agreedValue)
        .whereType<double>()
        .firstOrNull;
    final hasContract = ops.activeRules(st, c.id).isNotEmpty;

    return Scaffold(
      body: ContentWidth(
        max: 1100,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
          children: [
            const Text('لوحة التشغيل', style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w900)),
            Text('${c.legalName} · العمليات اليومية ضمن قواعد العقد',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            const SizedBox(height: 14),
            if (!hasContract)
              const StateBanner(
                color: AppColors.warning,
                icon: Icons.warning_amber_rounded,
                text: 'لا يوجد عقد معتمد بعد، فلا توجد قواعد رقابية سارية. العمليات تُقبل دون فحص حتى اعتماد العقد.',
              ),
            KpiGrid(items: [
              (w) => KpiCard(width: w, label: 'عمليات اليوم', value: '$today', icon: Icons.today_rounded, color: AppColors.info),
              (w) => KpiCard(
                    width: w,
                    label: 'مجمّدة (${frozen.length})',
                    value: formatCurrency(frozen.fold(0, (a, t) => a + t.amount), c.currency),
                    icon: Icons.ac_unit_rounded,
                    color: TxStatus.frozen.color,
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const TransactionsScreen(frozenOnly: true))),
                  ),
              (w) => KpiCard(
                    width: w,
                    label: 'مخالفات مفتوحة',
                    value: '$openViolations',
                    icon: Icons.gpp_bad_rounded,
                    color: AppColors.danger,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ViolationsScreen())),
                  ),
              (w) => KpiCard(
                    width: w,
                    label: cap == null ? 'مصروف الشهر' : 'مصروف الشهر من السقف',
                    value: cap == null
                        ? formatCurrency(month, c.currency)
                        : '${(month / cap * 100).toStringAsFixed(0)}%',
                    icon: Icons.speed_rounded,
                    color: cap != null && month > cap * 0.8 ? AppColors.warning : AppColors.gold,
                  ),
            ]),
            if (cap != null) ...[
              const SizedBox(height: 12),
              Text('${formatCurrency(month, c.currency)} من ${formatCurrency(cap, c.currency)} هذا الشهر',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (month / cap).clamp(0, 1),
                  minHeight: 8,
                  backgroundColor: AppColors.navyLight,
                  color: month > cap * 0.8 ? AppColors.warning : AppColors.success,
                ),
              ),
            ],
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpenseEntryScreen())),
              icon: const Icon(Icons.add_rounded),
              label: const Text('تسجيل عملية جديدة'),
            ),
            const SizedBox(height: 18),
            const Text('محجوزة بانتظار قرار', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (frozen.isEmpty)
              const StateBanner(color: AppColors.success, icon: Icons.task_alt_rounded, text: 'لا توجد عمليات محجوزة.')
            else
              ...frozen.take(5).map((t) => TxTile(
                    tx: t,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TxDetailScreen(txId: t.id))),
                  )),
          ],
        ),
      ),
    );
  }
}
