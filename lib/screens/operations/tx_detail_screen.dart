import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/gov_status.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/operations.dart';
import '../../providers/company_state.dart';
import '../../providers/operations_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import 'tx_widgets.dart';

/// O04: تفاصيل العملية وفحص القاعدة. يشرح بالضبط كيف قُيّمت العملية مقابل قواعد العقد،
/// ولا يخفي سبب التجميد أبداً. اعتماد الاستثناء لا يغيّر الحد الأصلي في العقد.
class TxDetailScreen extends StatefulWidget {
  final String txId;
  const TxDetailScreen({super.key, required this.txId});

  @override
  State<TxDetailScreen> createState() => _TxDetailScreenState();
}

class _TxDetailScreenState extends State<TxDetailScreen> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  GovStatus _gov(TxStatus s) => switch (s) {
        TxStatus.pendingEvaluation => GovStatus.pending,
        TxStatus.allowed => GovStatus.approved,
        TxStatus.frozen => GovStatus.frozen,
        TxStatus.exceptionPending => GovStatus.pending,
        TxStatus.releasedException => GovStatus.approved,
        TxStatus.violation => GovStatus.violation,
      };

  @override
  Widget build(BuildContext context) {
    final ops = context.watch<OperationsState>();
    final cs = context.watch<CompanyState>();
    final tx = ops.tx(widget.txId);
    final c = cs.current;
    if (tx == null || c == null) return const Scaffold(body: StateView.empty(title: 'العملية غير موجودة', message: ''));
    final ex = ops.exceptionForTx(tx.id);
    final operate = canOperate(cs.myRoles);
    final history = cs.audit.where((e) => e.objectId == tx.id || (ex != null && e.objectId == ex.id)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل العملية وفحص القاعدة')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            if (tx.status == TxStatus.frozen)
              StateBanner(
                color: TxStatus.frozen.color,
                icon: Icons.ac_unit_rounded,
                text: 'العملية محجوزة على مستوى النظام لأنها تتجاوز قاعدة في العقد. '
                    'التجميد ليس حذفاً للقيد المحاسبي، ويُفرج عنها فقط عبر استثناء يعتمده الشركاء.',
              ),
            if (tx.status == TxStatus.releasedException)
              StateBanner(
                color: TxStatus.releasedException.color,
                icon: Icons.lock_open_rounded,
                text: 'أُفرج عن هذه العملية وحدها كاستثناء لمرة واحدة. الحد في العقد لم يتغير.',
              ),
            if (tx.status == TxStatus.violation)
              StateBanner(
                color: TxStatus.violation.color,
                icon: Icons.gpp_bad_rounded,
                text: 'سُجّلت مخالفة رسمية لقواعد العقد على هذه العملية، وتظهر في سجل المخالفات.',
              ),
            GovCard(
              title: 'ملخص العملية',
              icon: Icons.receipt_long_rounded,
              trailing: StatusBadge(_gov(tx.status), overrideLabel: tx.status.label, dense: true),
              child: Column(children: [
                _kv('المبلغ', formatCurrency(tx.amount, tx.currency)),
                _kv('الفئة', tx.category.label),
                _kv('المستفيد', tx.payee),
                _kv('الغرض', tx.purpose),
                _kv('التاريخ', txDate.format(tx.date)),
                _kv('المصدر', tx.source.label),
                if (tx.reference.isNotEmpty) _kv('المرجع', tx.reference),
                if (tx.evaluatedAt != null) _kv('وقت الفحص', txTime.format(tx.evaluatedAt!.toLocal())),
              ]),
            ),
            const SizedBox(height: 12),
            if (tx.checks.isEmpty)
              const StateBanner(
                color: AppColors.info,
                icon: Icons.info_outline_rounded,
                text: 'لا توجد قاعدة في العقد تخص هذه العملية، فاعتُبرت مسموحة.',
              ),
            ...tx.checks.map((h) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: RuleEvaluationCard(
                    ruleId: h.ruleId,
                    condition: h.condition,
                    observed: h.observed,
                    expected: h.expected,
                    result: h.triggered ? (h.autoViolation ? GovStatus.violation : GovStatus.frozen) : GovStatus.approved,
                    action: h.action,
                    ruleVersion: 'الإصدار ${h.ruleVersion} (كما كان سارياً وقت الفحص)',
                  ),
                )),
            if (ex != null) ...[
              GovCard(
                title: 'طلب الاستثناء لمرة واحدة',
                icon: Icons.how_to_vote_rounded,
                trailing: Text(ex.status.label, style: TextStyle(color: ex.status.color, fontWeight: FontWeight.w800)),
                child: Column(children: [
                  _kv('السبب', ex.reason),
                  _kv('الحد الأصلي', ex.originalLimit),
                  _kv('المهلة', txTime.format(ex.deadline.toLocal())),
                  _kv('الموافقة', '${ops.shares(c, ex).$1.toStringAsFixed(1)}% من ${ex.threshold.toStringAsFixed(2)}% مطلوبة'),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            if (operate && tx.status == TxStatus.frozen && ops.exceptionBlocker(c.id) != null)
              StateBanner(color: AppColors.danger, icon: Icons.gavel_rounded, text: ops.exceptionBlocker(c.id)!)
            else if (operate && tx.status == TxStatus.frozen)
              ElevatedButton.icon(
                onPressed: () => requestExceptionSheet(context, tx),
                icon: const Icon(Icons.outbox_rounded),
                label: const Text('طلب استثناء لمرة واحدة'),
              ),
            const SizedBox(height: 12),
            GovCard(
              title: 'ملاحظات (${tx.notes.length})',
              icon: Icons.sticky_note_2_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ...tx.notes.map((n) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('• $n', style: const TextStyle(color: AppColors.textSecondary)),
                    )),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _note,
                      decoration: const InputDecoration(hintText: 'أضف ملاحظة أو دليلاً', isDense: true),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      ops.addTxNote(c, tx, _note.text);
                      _note.clear();
                    },
                    icon: const Icon(Icons.add_comment_rounded, color: AppColors.gold),
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 12),
            GovCard(title: 'سجل العملية', icon: Icons.history_rounded, child: AuditTimeline(events: history)),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 100, child: Text(k, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5))),
          Expanded(child: Text(v, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600))),
        ]),
      );
}

/// O06: طلب استثناء لمرة واحدة. ينص صراحة على أن الموافقة لا تعدّل العقد.
Future<void> requestExceptionSheet(BuildContext context, FinancialTx tx) async {
  final ops = context.read<OperationsState>();
  final cs = context.read<CompanyState>();
  final c = cs.current!;
  final reason = TextEditingController();
  final check = tx.triggered.first;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.navySurface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('طلب استثناء لمرة واحدة',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Text('القاعدة: ${check.ruleName}\nالحد في العقد: ${check.expected}\nالمطلوب: ${formatCurrency(tx.amount, tx.currency)}',
            style: const TextStyle(color: AppColors.textSecondary, height: 1.8)),
        const SizedBox(height: 10),
        const StateBanner(
          color: AppColors.warning,
          icon: Icons.info_outline_rounded,
          text: 'اعتماد هذا الطلب يفرج عن هذه العملية وحدها، ولا يعدّل العقد ولا الحد الأصلي. '
              'يقرره الشركاء غير مقدّم الطلب بأغلبية الحصص خلال 3 أيام، ورفضه يسجّل مخالفة.',
        ),
        TextField(
          controller: reason,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'السبب التجاري (إلزامي)'),
        ),
        const SizedBox(height: 14),
        ElevatedButton(
          onPressed: () {
            if (reason.text.trim().isEmpty) return;
            ops.requestException(c, tx, check, reason: reason.text, requestedBy: cs.me?.id ?? '');
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('أُرسل الطلب للشركاء، ووصلهم إشعار بذلك')));
          },
          child: const Text('إرسال الطلب للشركاء'),
        ),
      ]),
    ),
  );
  reason.dispose();
}
