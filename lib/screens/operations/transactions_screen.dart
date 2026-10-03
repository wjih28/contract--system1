import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/operations.dart';
import '../../providers/company_state.dart';
import '../../providers/operations_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import 'expense_entry_screen.dart';
import 'tx_detail_screen.dart';
import 'tx_widgets.dart';

/// O02 / P17: العمليات المالية ونتيجة فحصها. بوابة الشركاء تعرضها للقراءة،
/// وبوابة التشغيل تسمح بإضافة عمليات. لا يمكن تجاوز بوابة الفحص من أي شاشة.
class TransactionsScreen extends StatefulWidget {
  final bool frozenOnly;
  const TransactionsScreen({super.key, this.frozenOnly = false});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  TxStatus? _status;
  String _q = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = context.read<CompanyState>().current;
      if (c != null) context.read<OperationsState>().expireOverdue(c);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final ops = context.watch<OperationsState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final all = ops.txFor(c.id);
    final base = widget.frozenOnly
        ? all.where((t) => t.status == TxStatus.frozen || t.status == TxStatus.exceptionPending).toList()
        : all;
    final list = base
        .where((t) => _status == null || t.status == _status)
        .where((t) => _q.isEmpty || t.payee.contains(_q) || t.purpose.contains(_q))
        .toList();
    final operate = canOperate(cs.myRoles);
    double sum(TxStatus s) => all.where((t) => t.status == s).fold(0, (a, t) => a + t.amount);

    return Scaffold(
      appBar: AppBar(title: Text(widget.frozenOnly ? 'العمليات المجمّدة' : 'العمليات المالية')),
      floatingActionButton: operate && !widget.frozenOnly
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.navyDark,
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpenseEntryScreen())),
              icon: const Icon(Icons.add_rounded),
              label: const Text('عملية جديدة', style: TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          children: [
            if (widget.frozenOnly)
              const StateBanner(
                color: AppColors.info,
                icon: Icons.ac_unit_rounded,
                text: 'التجميد حجز تشغيلي بانتظار مراجعة، وليس حذفاً للقيد. يُفرج عن العملية فقط باستثناء يعتمده الشركاء.',
              )
            else
              KpiGrid(items: [
                (w) => KpiCard(width: w, label: 'مسموحة', value: formatCurrency(sum(TxStatus.allowed), c.currency),
                    icon: Icons.check_circle_rounded, color: AppColors.success),
                (w) => KpiCard(width: w, label: 'مجمّدة', value: formatCurrency(sum(TxStatus.frozen) + sum(TxStatus.exceptionPending), c.currency),
                    icon: Icons.ac_unit_rounded, color: TxStatus.frozen.color),
                (w) => KpiCard(width: w, label: 'استثناءات', value: formatCurrency(sum(TxStatus.releasedException), c.currency),
                    icon: Icons.lock_open_rounded, color: TxStatus.releasedException.color),
                (w) => KpiCard(width: w, label: 'مخالفات', value: formatCurrency(sum(TxStatus.violation), c.currency),
                    icon: Icons.gpp_bad_rounded, color: AppColors.danger),
              ]),
            const SizedBox(height: 14),
            TextField(
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: const InputDecoration(hintText: 'بحث بالمستفيد أو الغرض', prefixIcon: Icon(Icons.search_rounded)),
            ),
            const SizedBox(height: 10),
            if (!widget.frozenOnly)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  ChoiceChip(label: const Text('الكل'), selected: _status == null, onSelected: (_) => setState(() => _status = null)),
                  for (final s in TxStatus.values.where((s) => s != TxStatus.pendingEvaluation))
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8),
                      child: ChoiceChip(label: Text(s.label), selected: _status == s, onSelected: (_) => setState(() => _status = s)),
                    ),
                ]),
              ),
            const SizedBox(height: 12),
            if (list.isEmpty)
              StateView.empty(
                title: widget.frozenOnly ? 'لا توجد عمليات مجمّدة' : 'لا توجد عمليات',
                message: widget.frozenOnly
                    ? 'كل العمليات ضمن حدود العقد أو حُسمت.'
                    : operate
                        ? 'سجّل أول عملية لتمر ببوابة الفحص مقابل قواعد العقد.'
                        : 'تظهر هنا العمليات التي يسجّلها فريق التشغيل.',
              ),
            ...list.map((t) => TxTile(
                  tx: t,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TxDetailScreen(txId: t.id))),
                )),
          ],
        ),
      ),
    );
  }
}
