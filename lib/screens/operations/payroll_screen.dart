import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/admin.dart';
import '../../models/company.dart';
import '../../models/operations.dart';
import '../../models/ops_extra.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../providers/daily_ops_state.dart';
import '../../providers/operations_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import 'tx_detail_screen.dart';

/// من يعتمد دفعات الرواتب والخطط: الشريك المدير أو المدير التنفيذي
bool canApproveOps(Set<CompanyRole> roles) =>
    roles.contains(CompanyRole.managingPartner) || roles.contains(CompanyRole.executiveManager);

/// O09: الرواتب. دفعة لكل فترة: مسودة ثم رفع للاعتماد ثم اعتماد. تغيير راتب الشريك المدير
/// يمر بقاعدة العقد، فإن نص على قرار الشركاء تنتظر الدفعة قرارهم.
class PayrollScreen extends StatelessWidget {
  const PayrollScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final daily = context.watch<DailyOpsState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    if (!cs.canSee('payroll.salaries')) {
      return const Scaffold(body: StateView.denied(message: 'الرواتب الفردية بيانات سرية غير متاحة لدورك.'));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) context.read<DailyOpsState>().refreshPayroll(c, context.read<OperationsState>());
    });
    final batches = daily.payrollFor(c.id);
    final canAdd = cs.canSee('payroll.salaries', PermAction.add);
    final now = DateTime.now();
    final period = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(title: const Text('الرواتب')),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              onPressed: () {
                final err = daily.createBatch(c, period, by: cs.me?.id ?? '');
                if (err != null) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                } else {
                  final b = daily.payrollFor(c.id).firstWhere((x) => x.period == period);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => PayrollBatchScreen(batchId: b.id)));
                }
              },
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.navyDark,
              icon: const Icon(Icons.add_rounded),
              label: Text('دفعة $period'),
            )
          : null,
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
          children: [
            const StateBanner(
              color: AppColors.info,
              icon: Icons.info_outline_rounded,
              text: 'تغيير راتب الشريك المدير يمر ببوابة الفحص كعملية "تعديل راتب"، ولا تُعتمد الدفعة قبل قرار الشركاء إن نص العقد على ذلك.',
            ),
            if (batches.isEmpty)
              const StateView.empty(
                  icon: Icons.payments_rounded, title: 'لا توجد دفعات رواتب', message: 'أنشئ دفعة الشهر الحالي ثم أدخل الرواتب.'),
            for (final b in batches)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PayrollBatchScreen(batchId: b.id))),
                  title: Text('رواتب ${b.period}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${b.lines.length} موظفين · ${formatCurrency(b.total, b.currency)}${b.reason == null ? '' : '\n${b.reason}'}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.5)),
                  trailing: Text(b.status.label, style: TextStyle(color: b.status.color, fontWeight: FontWeight.w700)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class PayrollBatchScreen extends StatelessWidget {
  final String batchId;
  const PayrollBatchScreen({super.key, required this.batchId});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final daily = context.watch<DailyOpsState>();
    final ops = context.read<OperationsState>();
    final c = cs.current;
    final b = daily.batch(batchId);
    if (c == null || b == null) return const Scaffold(body: StateView.empty(title: 'الدفعة غير متاحة', message: ''));
    final editable = (b.status == PayrollStatus.draft || b.status == PayrollStatus.rejected) &&
        cs.canSee('payroll.salaries', PermAction.add);
    final prev = daily.approvedManagerSalary(c.id, before: b.period);
    final mp = b.lines.where((l) => l.managingPartner).firstOrNull;
    final mpChanged = mp != null && prev != null && mp.total != prev;
    final tx = b.ruleTxId == null ? null : ops.tx(b.ruleTxId!);

    return Scaffold(
      appBar: AppBar(title: Text('رواتب ${b.period}')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            StateBanner(
              color: b.status.color,
              icon: Icons.payments_rounded,
              text: '${b.status.label} · الإجمالي ${formatCurrency(b.total, b.currency)}${b.reason == null ? '' : ' · ${b.reason}'}',
            ),
            if (mpChanged)
              StateBanner(
                color: AppColors.warning,
                icon: Icons.rule_rounded,
                text: 'راتب الشريك المدير تغيّر من ${formatCurrency(prev, b.currency)} إلى ${formatCurrency(mp.total, b.currency)}: '
                    'يمر بقاعدة العقد عند الرفع للاعتماد.',
              ),
            if (tx != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TxDetailScreen(txId: tx.id))),
                  icon: const Icon(Icons.rule_rounded, size: 18),
                  label: Text('عملية تعديل الراتب: ${tx.status.label}'),
                ),
              ),
            GovCard(
              title: 'الموظفون',
              icon: Icons.groups_rounded,
              child: Column(children: [
                for (var i = 0; i < b.lines.length; i++)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onTap: editable ? () => _editLine(context, c, b, i) : null,
                    title: Text('${b.lines[i].employee}${b.lines[i].managingPartner ? ' · محمي بالعقد' : ''}'),
                    subtitle: Text(
                        '${b.lines[i].role}${b.lines[i].adjustment == 0 ? '' : ' · تعديل ${formatCurrency(b.lines[i].adjustment, b.currency)}'}${b.lines[i].note.isEmpty ? '' : ' · ${b.lines[i].note}'}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                    trailing: Text(formatCurrency(b.lines[i].total, b.currency), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                if (editable)
                  TextButton.icon(onPressed: () => _editLine(context, c, b, null), icon: const Icon(Icons.add_rounded), label: const Text('إضافة موظف')),
              ]),
            ),
            const SizedBox(height: 12),
            if (editable)
              ElevatedButton.icon(
                onPressed: b.lines.any((l) => l.salary <= 0)
                    ? null
                    : () => daily.submitBatch(c, b, ops, context.read<ContractState>(),
                        by: cs.me?.id ?? '', byName: cs.me?.name ?? ''),
                icon: const Icon(Icons.send_rounded),
                label: Text(b.lines.any((l) => l.salary <= 0) ? 'أدخل كل الرواتب أولاً' : 'رفع الدفعة للاعتماد'),
              ),
            if (b.status == PayrollStatus.pendingApproval && canApproveOps(cs.myRoles)) ...[
              ElevatedButton.icon(
                onPressed: () => daily.decideBatch(c, b, approve: true, byName: cs.me?.name ?? ''),
                icon: const Icon(Icons.check_rounded),
                label: const Text('اعتماد الدفعة'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => daily.decideBatch(c, b, approve: false, byName: cs.me?.name ?? '', reason: 'أُعيدت للمراجعة'),
                icon: const Icon(Icons.undo_rounded),
                label: const Text('رفض وإعادة للمراجعة'),
              ),
            ],
            const SizedBox(height: 8),
            const Text('التصدير إلى النظام المحاسبي: يحتاج ربط Xero أو QuickBooks. يمكن طباعة الدفعة من التقارير.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }

  Future<void> _editLine(BuildContext context, Company c, PayrollBatch b, int? i) async {
    final daily = context.read<DailyOpsState>();
    final cur = i == null ? null : b.lines[i];
    final name = TextEditingController(text: cur?.employee ?? '');
    final role = TextEditingController(text: cur?.role ?? '');
    final salary = TextEditingController(text: cur == null || cur.salary == 0 ? '' : cur.salary.toStringAsFixed(0));
    final adj = TextEditingController(text: cur == null || cur.adjustment == 0 ? '' : cur.adjustment.toStringAsFixed(0));
    final note = TextEditingController(text: cur?.note ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navySurface,
        title: Text(cur?.employee ?? 'موظف جديد'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, enabled: cur?.managingPartner != true, decoration: const InputDecoration(labelText: 'الاسم')),
            TextField(controller: role, decoration: const InputDecoration(labelText: 'الوظيفة')),
            TextField(controller: salary, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الراتب الأساسي')),
            TextField(controller: adj, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'تعديل (بدل أو خصم)')),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة')),
          ]),
        ),
        actions: [
          if (i != null && cur?.managingPartner != true)
            TextButton(
              onPressed: () {
                daily.updateLines(c, b, [...b.lines]..removeAt(i));
                Navigator.pop(ctx, false);
              },
              child: const Text('حذف السطر', style: TextStyle(color: AppColors.danger)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      final line = PayrollLine(
        employee: name.text.trim(),
        role: role.text.trim(),
        salary: double.tryParse(salary.text) ?? 0,
        adjustment: double.tryParse(adj.text) ?? 0,
        note: note.text.trim(),
        managingPartner: cur?.managingPartner ?? false,
      );
      final lines = [...b.lines];
      i == null ? lines.add(line) : lines[i] = line;
      daily.updateLines(c, b, lines);
    }
    for (final x in [name, role, salary, adj, note]) {
      x.dispose();
    }
  }
}
