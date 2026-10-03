import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/operations.dart';
import '../../models/ops_extra.dart';
import '../../models/questionnaire.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../providers/daily_ops_state.dart';
import '../../providers/operations_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../versions/amendment_screens.dart';
import 'payroll_screen.dart';
import 'plans_screen.dart';
import 'tx_detail_screen.dart';
import 'tx_widgets.dart';

/// O10: مركز الموافقات التشغيلية. طابور مهام بالأولوية والمهلة والقاعدة.
/// القرارات التي هي من حق الشركاء وحدهم تظهر للإحالة إلى بوابة الشركاء ولا تُتخذ هنا.
class ApprovalCenterScreen extends StatelessWidget {
  const ApprovalCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final ops = context.watch<OperationsState>();
    final st = context.watch<ContractState>();
    final daily = context.watch<DailyOpsState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final approver = canApproveOps(cs.myRoles);
    final items = <_Item>[
      for (final b in daily.payrollFor(c.id).where((b) => b.status == PayrollStatus.pendingApproval))
        _Item('PR-${b.id}', 'دفعة رواتب ${b.period}', b.createdBy, formatCurrency(b.total, b.currency), 'لا قاعدة متأثرة',
            null, b.status.label, true, () => PayrollBatchScreen(batchId: b.id)),
      for (final p in daily.plansFor(c.id).where((p) => p.status == PlanStatus.pending))
        _Item('PL-${p.id}', 'خطة ${p.category.label} ${p.year}: ${p.title}', p.owner,
            p.budget == null ? 'بلا ميزانية' : 'ميزانية ${formatCurrency(p.budget!, c.currency)}', 'اعتماد الخطة لا يتجاوز حدود الصرف',
            null, p.status.label, true, () => PlanDetailScreen(planId: p.id)),
      // قرارات الشركاء: إحالة فقط
      for (final x in ops.exceptionsFor(c.id).where((x) => x.status == ExceptionStatus.pending))
        _Item('EX-${x.id}', 'استثناء: ${x.ruleName}', x.requestedBy, formatCurrency(x.requestedAmount, c.currency),
            'الحد في العقد ${x.originalLimit}', x.deadline, 'نصاب الشركاء مطلوب', false, () => TxDetailScreen(txId: x.txId)),
      for (final b in daily.payrollFor(c.id).where((b) => b.status == PayrollStatus.awaitingPartners))
        _Item('PRX-${b.id}', 'تعديل راتب الشريك المدير (${b.period})', b.createdBy, formatCurrency(b.total, b.currency),
            'قاعدة العقد لتغيير راتب الشريك المدير', null, 'نصاب الشركاء مطلوب', false, () => PayrollBatchScreen(batchId: b.id)),
      if (st.activeAmendment(c.id) != null)
        _Item('AM', 'مقترح الإصدار ${st.activeAmendment(c.id)!.version} من العقد', st.activeAmendment(c.id)!.proposedBy ?? '',
            st.activeAmendment(c.id)!.changeType.label, st.activeAmendment(c.id)!.changeSummary ?? '', null, 'تصويت الشركاء مطلوب',
            false, () => AmendmentDetailScreen(sessionId: st.activeAmendment(c.id)!.id)),
    ];
    final mine = items.where((i) => i.operational).toList();
    final partners = items.where((i) => !i.operational).toList();
    String who(String id) => c.members.where((m) => m.id == id).firstOrNull?.name ?? (id.isEmpty ? '—' : id);

    Widget tile(_Item i) => Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => i.open())),
            leading: Icon(i.operational ? Icons.task_alt_rounded : Icons.how_to_vote_rounded,
                color: i.operational ? AppColors.gold : AppColors.info),
            title: Text(i.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            subtitle: Text(
              '${i.id} · مقدّم الطلب: ${who(i.requester)} · ${i.amount}\nالقاعدة: ${i.rule}'
              '${i.deadline == null ? '' : ' · المهلة ${txTime.format(i.deadline!.toLocal())}'}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.5),
            ),
            isThreeLine: true,
            trailing: Text(i.status, style: TextStyle(color: i.operational ? AppColors.gold : AppColors.info, fontSize: 11.5)),
          ),
        );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مركز الموافقات'),
          bottom: TabBar(tabs: [Tab(text: 'تشغيلية (${mine.length})'), Tab(text: 'قرارات الشركاء (${partners.length})')]),
        ),
        body: ContentWidth(
          child: TabBarView(children: [
            ListView(padding: const EdgeInsets.all(20), children: [
              if (!approver)
                StateBanner.readOnly('الاعتماد للشريك المدير أو المدير التنفيذي. يمكنك متابعة الطلبات وطلب الإيضاح من تفاصيلها.'),
              if (mine.isEmpty) const StateView.empty(icon: Icons.inbox_rounded, title: 'لا توجد موافقات معلّقة', message: ''),
              ...mine.map(tile),
            ]),
            ListView(padding: const EdgeInsets.all(20), children: [
              const StateBanner(
                color: AppColors.info,
                icon: Icons.how_to_vote_rounded,
                text: 'هذه القرارات من حق الشركاء وحدهم بالنصاب المرجّح بالحصص، وتُحسم في بوابة الشركاء ولا تُحاكى هنا.',
              ),
              if (partners.isEmpty) const StateView.empty(icon: Icons.inbox_rounded, title: 'لا توجد قرارات معلّقة', message: ''),
              ...partners.map(tile),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Item {
  final String id, title, requester, amount, rule;
  final DateTime? deadline;
  final String status;
  final bool operational;
  final Widget Function() open;
  const _Item(this.id, this.title, this.requester, this.amount, this.rule, this.deadline, this.status, this.operational, this.open);
}
