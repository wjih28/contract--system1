import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/gov_status.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/operations.dart';
import '../../models/questionnaire.dart';
import '../../providers/company_state.dart';
import '../../providers/operations_state.dart';
import '../../services/identity_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import 'tx_detail_screen.dart';
import 'tx_widgets.dart';

/// P16: الموافقات والاستثناءات. يقرر الشركاء المخوّلون طلبات الاستثناء لمرة واحدة
/// دون تغيير قاعدة العقد أو إصداره.
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
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
    final all = ops.exceptionsFor(c.id);
    final pending = all.where((e) => e.status == ExceptionStatus.pending).toList();
    final decided = all.where((e) => e.status != ExceptionStatus.pending).toList();

    Widget list(List<ExceptionRequest> items, Widget empty) => items.isEmpty
        ? empty
        : ListView(padding: const EdgeInsets.all(20), children: items.map((e) => _ExceptionCard(ex: e)).toList());

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الموافقات والاستثناءات'),
          bottom: TabBar(tabs: [Tab(text: 'بانتظار القرار (${pending.length})'), Tab(text: 'محسومة (${decided.length})')]),
        ),
        body: ContentWidth(
          child: TabBarView(children: [
            list(
              pending,
              const StateView.empty(
                icon: Icons.task_alt_rounded,
                title: 'لا طلبات بانتظار قرارك',
                message: 'عندما تتجاوز عملية حداً في العقد ويُطلب لها استثناء، يظهر الطلب هنا.',
              ),
            ),
            list(decided, const StateView.empty(title: 'لا قرارات سابقة', message: '')),
          ]),
        ),
      ),
    );
  }
}

class _ExceptionCard extends StatelessWidget {
  final ExceptionRequest ex;
  const _ExceptionCard({required this.ex});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final ops = context.watch<OperationsState>();
    final c = cs.current!;
    final tx = ops.tx(ex.txId);
    final (approve, reject) = ops.shares(c, ex);
    final voters = ops.eligibleVoters(c, ex);
    final me = cs.me;
    final canVote = ex.status == ExceptionStatus.pending &&
        me != null &&
        voters.any((v) => v.id == me.id) &&
        !ex.votes.containsKey(me.id);
    final requester = c.members.where((m) => m.id == ex.requestedBy).firstOrNull?.name ?? '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GovCard(
          title: 'استثناء لمرة واحدة: ${ex.ruleName}',
          icon: Icons.outbox_rounded,
          trailing: Text(ex.status.label, style: TextStyle(color: ex.status.color, fontWeight: FontWeight.w800, fontSize: 12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // مقارنة الحد التعاقدي بالمطلوب
            Row(children: [
              Expanded(child: _box('الحد في العقد', ex.originalLimit, AppColors.textSecondary)),
              const SizedBox(width: 10),
              Expanded(child: _box('المطلوب', tx == null ? formatCurrency(ex.requestedAmount) : formatCurrency(tx.amount, tx.currency), AppColors.warning)),
            ]),
            const SizedBox(height: 10),
            Text('السبب: ${ex.reason}', style: const TextStyle(color: AppColors.textPrimary, height: 1.6)),
            Text('مقدّم الطلب: $requester · المهلة ${txTime.format(ex.deadline.toLocal())}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
            if (tx != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TxDetailScreen(txId: tx.id))),
                  icon: const Icon(Icons.receipt_long_rounded, size: 18),
                  label: Text('العملية: ${tx.payee} · ${tx.category.label}'),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        ApprovalPanel(
          threshold: ex.threshold,
          agree: approve,
          disagree: reject,
          neutral: 0,
          deadline: ex.deadline,
          decision: switch (ex.status) {
            ExceptionStatus.pending => null,
            ExceptionStatus.approved => GovStatus.approved,
            ExceptionStatus.rejected => GovStatus.rejected,
            ExceptionStatus.expired => GovStatus.archived,
          },
          voters: voters
              .map((p) => VoterLine(
                    name: p.name,
                    weight: p.equity,
                    vote: ex.votes[p.id] == null ? null : (ex.votes[p.id]!.approve ? 'موافق' : 'رافض'),
                    voteColor: ex.votes[p.id] == null
                        ? null
                        : (ex.votes[p.id]!.approve ? AppColors.success : AppColors.danger),
                  ))
              .toList(),
        ),
        if (canVote) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _vote(context, true),
                icon: const Icon(Icons.check_rounded),
                label: const Text('اعتماد لمرة واحدة'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger)),
                onPressed: () => _vote(context, false),
                icon: const Icon(Icons.close_rounded),
                label: const Text('رفض'),
              ),
            ),
          ]),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () async {
                final t = TextEditingController();
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.navySurface,
                    title: const Text('إفصاح عن تعارض مصالح'),
                    content: TextField(controller: t, decoration: const InputDecoration(labelText: 'طبيعة المصلحة')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                      ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إفصاح والامتناع')),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  context.read<OperationsState>().declareConflict(context.read<CompanyState>().current!, ex, me, note: t.text);
                }
                t.dispose();
              },
              icon: const Icon(Icons.front_hand_rounded, size: 18),
              label: const Text('لي مصلحة في هذه العملية'),
            ),
          ),
        ] else if (ex.conflicts.contains(me?.id))
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('أفصحت عن تعارض مصالح، فلا تصوّت على هذا الطلب.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          )
        else if (ex.status == ExceptionStatus.pending && me != null && me.id == ex.requestedBy)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('أنت مقدّم الطلب، فلا تصوّت عليه.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ),
      ]),
    );
  }

  Widget _box(String k, String v, Color c) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
          Text(v, style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 15)),
        ]),
      );

  /// تأكيد صريح بطبيعة الاستثناء لمرة واحدة، والرفض يتطلب سبباً
  Future<void> _vote(BuildContext context, bool approve) async {
    final ops = context.read<OperationsState>();
    final cs = context.read<CompanyState>();
    final me = cs.me!;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'اعتماد الاستثناء لمرة واحدة؟' : 'رفض الاستثناء؟'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            approve
                ? 'يُفرج عن هذه العملية وحدها. لا يتغير الحد في العقد، وأي عملية مماثلة لاحقاً ستُجمّد مجدداً.'
                : 'إذا رُفض الطلب بالأغلبية تُسجَّل مخالفة رسمية على العملية.',
            style: const TextStyle(height: 1.7),
          ),
          if (!approve) ...[
            const SizedBox(height: 10),
            TextField(controller: reason, decoration: const InputDecoration(labelText: 'سبب الرفض')),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(approve ? 'اعتماد' : 'رفض')),
        ],
      ),
    );
    if (ok != true || !context.mounted) {
      reason.dispose();
      return;
    }
    final m = await IdentityService.confirm(context,
        partnerName: me.name, action: '${approve ? 'اعتماد' : 'رفض'} استثناء "${ex.ruleName}"');
    if (m != null) {
      ops.voteException(cs.current!, ex, me, approve: approve, method: m.label, reason: reason.text.trim());
    }
    reason.dispose();
  }
}
