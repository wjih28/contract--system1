import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/operations.dart';
import '../../providers/company_state.dart';
import '../../providers/operations_state.dart';
import '../../theme/app_theme.dart';
import 'tx_detail_screen.dart';
import 'tx_widgets.dart';

/// O12: المخالفات المسجلة ومتابعتها: التحقيق، الإجراء التصحيحي، التصعيد، الحل، أو الإحالة إلى نزاع.
class ViolationsScreen extends StatelessWidget {
  const ViolationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final ops = context.watch<OperationsState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final list = ops.violationsFor(c.id);
    return Scaffold(
      appBar: AppBar(title: const Text('المخالفات')),
      body: ContentWidth(
        child: list.isEmpty
            ? const StateView.empty(
                icon: Icons.verified_user_rounded,
                title: 'لا توجد مخالفات مسجلة',
                message: 'تُسجَّل المخالفة تلقائياً عند خرق قاعدة صريحة، أو عند رفض الشركاء لطلب استثناء.',
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: list.map((v) => _Card(v: v)).toList(),
              ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Violation v;
  const _Card({required this.v});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _edit(context, v),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.navySurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: v.status.color.withValues(alpha: 0.45)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.gpp_bad_rounded, color: v.status.color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(v.ruleName, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
              ),
              Text(v.status.label, style: TextStyle(color: v.status.color, fontWeight: FontWeight.w700, fontSize: 12)),
            ]),
            const SizedBox(height: 6),
            Text(v.description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
            const SizedBox(height: 4),
            Text(
              '${txTime.format(v.createdAt.toLocal())} · ${v.origin}'
              '${v.owner.isEmpty ? '' : ' · المسؤول: ${v.owner}'}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
            if (v.correctiveAction.isNotEmpty)
              Text('الإجراء التصحيحي: ${v.correctiveAction}', style: const TextStyle(color: AppColors.info, fontSize: 12)),
          ]),
        ),
      );

  Future<void> _edit(BuildContext context, Violation v) async {
    final ops = context.read<OperationsState>();
    final c = context.read<CompanyState>().current!;
    var status = v.status;
    final owner = TextEditingController(text: v.owner);
    final corrective = TextEditingController(text: v.correctiveAction);
    final evidence = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.navySurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(v.ruleName, style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(v.description, style: const TextStyle(color: AppColors.textSecondary)),
              TextButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TxDetailScreen(txId: v.txId))),
                icon: const Icon(Icons.receipt_long_rounded),
                label: const Text('فتح العملية المرتبطة'),
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final s in ViolationStatus.values)
                  ChoiceChip(label: Text(s.label), selected: status == s, onSelected: (_) => set(() => status = s)),
              ]),
              if (status == ViolationStatus.disputed)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('تذكرة النزاع ومراحل التسوية تُبنى في المرحلة 3، والإحالة محفوظة في السجل من الآن.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                ),
              const SizedBox(height: 10),
              TextField(controller: owner, decoration: const InputDecoration(labelText: 'المسؤول عن المتابعة', isDense: true)),
              const SizedBox(height: 10),
              TextField(controller: corrective, decoration: const InputDecoration(labelText: 'الإجراء التصحيحي', isDense: true)),
              const SizedBox(height: 10),
              TextField(controller: evidence, decoration: const InputDecoration(labelText: 'إضافة دليل أو ملاحظة', isDense: true)),
              if (v.evidence.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...v.evidence.map((e) => Text('• $e', style: const TextStyle(color: AppColors.textMuted, fontSize: 12))),
              ],
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () {
                  ops.updateViolation(c, v,
                      status: status, owner: owner.text.trim(), corrective: corrective.text.trim(), evidence: evidence.text);
                  Navigator.pop(ctx);
                },
                child: const Text('حفظ'),
              ),
            ]),
          ),
        ),
      ),
    );
    owner.dispose();
    corrective.dispose();
    evidence.dispose();
  }
}
