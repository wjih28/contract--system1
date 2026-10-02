import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/operations.dart';
import '../../models/questionnaire.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../providers/operations_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import 'transactions_screen.dart';
import 'tx_detail_screen.dart';
import 'tx_widgets.dart';

enum _Period { day, week, month }

extension on _Period {
  String get label => switch (this) { _Period.day => 'اليوم', _Period.week => 'هذا الأسبوع', _Period.month => 'هذا الشهر' };
}

/// O07: المصروفات والضيافة. الفعلي مقابل حدود العقد لكل فترة، بأرقام دقيقة وشريط تقدّم
/// ونص يوضح الحالة (لا يُعتمد على اللون وحده)، مع سجل الاستثناءات.
class ExpenseLimitsMonitorScreen extends StatefulWidget {
  const ExpenseLimitsMonitorScreen({super.key});

  @override
  State<ExpenseLimitsMonitorScreen> createState() => _ExpenseLimitsMonitorScreenState();
}

class _ExpenseLimitsMonitorScreenState extends State<ExpenseLimitsMonitorScreen> {
  _Period _p = _Period.month;

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final st = context.watch<ContractState>();
    final ops = context.watch<OperationsState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final now = DateTime.now();
    final start = switch (_p) {
      _Period.day => DateTime(now.year, now.month, now.day),
      _Period.week => DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday % 7)),
      _Period.month => DateTime(now.year, now.month),
    };
    final txs = ops.txFor(c.id).where((t) => !t.date.isBefore(start) && t.currency == c.currency && t.category.isOutflow).toList();
    bool counted(FinancialTx t) => t.status == TxStatus.allowed || t.status == TxStatus.releasedException;
    final rules = ops.activeRules(st, c.id);
    final perTx = rules.where((r) => r.rule.conditions.any((x) => x.field == 'transaction.amount')).firstOrNull;
    final monthly = rules.where((r) => r.rule.conditions.any((x) => x.field == 'monthly.expenses')).firstOrNull;
    final monthTotal = ops.monthOutflow(c.id, now, c.currency);
    final total = txs.where(counted).fold<double>(0, (a, t) => a + t.amount);
    final maxSingle = txs.fold<double>(0, (a, t) => t.amount > a ? t.amount : a);
    final pendingEx = ops.exceptionsFor(c.id).where((x) => x.status == ExceptionStatus.pending).length;

    return Scaffold(
      appBar: AppBar(title: const Text('المصروفات والضيافة')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            SegmentedButton<_Period>(
              segments: [for (final p in _Period.values) ButtonSegment(value: p, label: Text(p.label))],
              selected: {_p},
              onSelectionChanged: (s) => setState(() => _p = s.first),
            ),
            const SizedBox(height: 12),
            if (rules.isEmpty)
              const StateBanner(
                  color: AppColors.warning,
                  icon: Icons.warning_amber_rounded,
                  text: 'لا توجد حدود سارية لأن العقد لم يُعتمد بعد.'),
            _LimitCard(
              title: 'السقف الشهري للمصروفات',
              actual: monthTotal,
              limit: monthly?.agreedValue,
              currency: c.currency,
              note: monthly == null ? 'لا يوجد سقف شهري في العقد' : 'من البند المعتمد · ${monthly.rule.id} الإصدار ${monthly.rule.version}',
            ),
            const SizedBox(height: 10),
            _LimitCard(
              title: 'أكبر عملية منفردة في ${_p.label}',
              actual: maxSingle,
              limit: perTx?.agreedValue,
              currency: c.currency,
              note: perTx == null ? 'لا يوجد سقف للعملية في العقد' : 'سقف العملية الواحدة · ما يتجاوزه يُجمَّد ويحتاج استثناء',
            ),
            const SizedBox(height: 10),
            if (_p != _Period.month)
              Text('لا ينص العقد على حد ${_p == _Period.day ? 'يومي' : 'أسبوعي'}، ويظهر الفعلي فقط: ${formatCurrency(total, c.currency)}.',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            const SizedBox(height: 14),
            GovCard(
              title: 'حسب الفئة (${_p.label})',
              icon: Icons.category_rounded,
              child: Column(children: [
                for (final cat in TxCategory.values.where((x) => x.isOutflow))
                  Builder(builder: (context) {
                    final list = txs.where((t) => t.category == cat).toList();
                    if (list.isEmpty) return const SizedBox.shrink();
                    final sum = list.where(counted).fold<double>(0, (a, t) => a + t.amount);
                    final frozen = list.where((t) => t.status == TxStatus.frozen || t.status == TxStatus.exceptionPending).length;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(cat.icon, color: AppColors.gold, size: 20),
                      title: Text(cat.label),
                      subtitle: Text(
                        '${list.length} عمليات${frozen == 0 ? '' : ' · $frozen مجمّدة أو بانتظار استثناء'}'
                        '${cat == TxCategory.hospitality ? '\nالتجاوز يُعامل حسب قاعدة العقد، وقد يُحمَّل على الحساب الجاري كسلفة إن نص العقد' : ''}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.5),
                      ),
                      trailing: Text(formatCurrency(sum, c.currency), style: const TextStyle(fontWeight: FontWeight.w800)),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TransactionsScreen())),
                    );
                  }),
                if (txs.isEmpty) const Text('لا توجد مصروفات في هذه الفترة.', style: TextStyle(color: AppColors.textMuted)),
              ]),
            ),
            const SizedBox(height: 12),
            GovCard(
              title: 'سجل الاستثناءات${pendingEx == 0 ? '' : ' · $pendingEx معلّقة'}',
              icon: Icons.fact_check_rounded,
              child: Column(children: [
                for (final x in ops.exceptionsFor(c.id).take(10))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(x.ruleName),
                    subtitle: Text('${formatCurrency(x.requestedAmount, c.currency)} · الحد ${x.originalLimit} · ${txDate.format(x.createdAt)}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                    trailing: Text(x.status.label, style: TextStyle(color: x.status.color, fontSize: 12)),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TxDetailScreen(txId: x.txId))),
                  ),
                if (ops.exceptionsFor(c.id).isEmpty) const Text('لا توجد طلبات استثناء.', style: TextStyle(color: AppColors.textMuted)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _LimitCard extends StatelessWidget {
  final String title;
  final double actual;
  final double? limit;
  final AppCurrency currency;
  final String note;
  const _LimitCard({required this.title, required this.actual, required this.limit, required this.currency, required this.note});

  @override
  Widget build(BuildContext context) {
    final cur = currency;
    final ratio = limit == null || limit == 0 ? 0.0 : actual / limit!;
    final (label, color) = limit == null
        ? ('لا يوجد حد', AppColors.textMuted)
        : ratio > 1
            ? ('تجاوز الحد', AppColors.danger)
            : ratio >= 0.8
                ? ('قريب من الحد', AppColors.warning)
                : ('ضمن الحد', AppColors.success);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.navySurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800))),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12.5)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: limit == null ? 0 : ratio.clamp(0, 1),
            minHeight: 8,
            backgroundColor: AppColors.navyLight,
            color: color,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          limit == null
              ? 'الفعلي ${formatCurrency(actual, cur)}'
              : 'الفعلي ${formatCurrency(actual, cur)} من ${formatCurrency(limit!, cur)} · المتبقي ${formatCurrency((limit! - actual).clamp(0, double.infinity), cur)} · ${(ratio * 100).toStringAsFixed(0)}%',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
        ),
        Text(note, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
      ]),
    );
  }
}
