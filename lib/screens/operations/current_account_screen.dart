import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/admin.dart';
import '../../models/company.dart';
import '../../models/ops_extra.dart';
import '../../models/questionnaire.dart';
import '../../providers/company_state.dart';
import '../../providers/daily_ops_state.dart';
import '../../providers/operations_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import 'tx_detail_screen.dart';
import 'tx_widgets.dart';

/// O08: الحساب الجاري للشريك المدير. رصيد لكل عملة في سطر منفصل دون جمع عملات مختلفة.
/// السلف المقبولة تُرحَّل آلياً من العمليات، والقيود اليدوية تُسجَّل في سجل التدقيق.
class CurrentAccountScreen extends StatelessWidget {
  const CurrentAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final ops = context.watch<OperationsState>();
    final daily = context.watch<DailyOpsState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    if (!cs.canSee('partner.currentAccount')) {
      return const Scaffold(
          body: StateView.denied(message: 'الحساب الجاري بيانات شخصية للشريك المدير، وتحتاج موافقة الشركاء لإتاحتها لهذا الدور.'));
    }
    final mp = c.partners.where((p) => p.roles.contains(CompanyRole.managingPartner)).firstOrNull;
    final entries = daily.ledgerFor(c, ops).where((e) => mp == null || e.partnerId == mp.id).toList();
    final balances = mp == null ? const <AppCurrency, double>{} : (daily.balances(c, ops)[mp.id] ?? const {});
    final canAdd = cs.canSee('partner.currentAccount', PermAction.add) || cs.myRoles.contains(CompanyRole.financialManager);

    return Scaffold(
      appBar: AppBar(title: Text('الحساب الجاري${mp == null ? '' : ' · ${mp.name}'}')),
      floatingActionButton: canAdd && mp != null
          ? FloatingActionButton.extended(
              onPressed: () => _add(context, c, mp),
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.navyDark,
              icon: const Icon(Icons.add_rounded),
              label: const Text('قيد مأذون'),
            )
          : null,
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
          children: [
            if (mp == null)
              const StateView.empty(title: 'لا يوجد شريك مدير', message: 'يظهر الحساب بعد تحديد الشريك المدير في الشركة.'),
            for (final cur in AppCurrency.values)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.navySurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('الرصيد بـ${cur.label}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      Text(formatCurrency((balances[cur] ?? 0).abs(), cur),
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w900)),
                    ]),
                  ),
                  Text(
                    (balances[cur] ?? 0) > 0
                        ? 'على الشريك للشركة'
                        : (balances[cur] ?? 0) < 0
                            ? 'للشريك على الشركة'
                            : 'متوازن',
                    style: TextStyle(
                        color: (balances[cur] ?? 0) > 0 ? AppColors.warning : AppColors.success, fontWeight: FontWeight.w700),
                  ),
                ]),
              ),
            const Text('لا تُجمع العملات المختلفة في رصيد واحد دون سعر تحويل معتمد.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
            const SizedBox(height: 12),
            GovCard(
              title: 'القيود (${entries.length})',
              icon: Icons.receipt_long_rounded,
              child: entries.isEmpty
                  ? const Text('لا توجد قيود بعد. السلف الشخصية المقبولة تظهر هنا آلياً.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12.5))
                  : Column(children: [
                      for (final e in entries)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          onTap: e.txId == null
                              ? null
                              : () => Navigator.push(context, MaterialPageRoute(builder: (_) => TxDetailScreen(txId: e.txId!))),
                          leading: Icon(e.automatic ? Icons.sync_rounded : Icons.edit_note_rounded,
                              color: e.signed > 0 ? AppColors.warning : AppColors.success),
                          title: Text('${e.kind.label}${e.pending ? ' · معلّق على قرار الشركاء' : ''}'),
                          subtitle: Text('${txDate.format(e.date)} · ${e.reference}${e.note.isEmpty ? '' : '\n${e.note}'}',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.5)),
                          trailing: Text('${e.signed > 0 ? '+' : '−'}${formatCurrency(e.amount, e.currency)}',
                              style: TextStyle(
                                  color: e.pending ? AppColors.textMuted : AppColors.textPrimary, fontWeight: FontWeight.w800)),
                        ),
                    ]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, Company c, CompanyMember mp) async {
    final cs = context.read<CompanyState>();
    final daily = context.read<DailyOpsState>();
    final amount = TextEditingController();
    final ref = TextEditingController();
    final note = TextEditingController();
    var kind = LedgerKind.settlement;
    var cur = c.currency;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: AppColors.navySurface,
          title: const Text('قيد على الحساب الجاري'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<LedgerKind>(
                initialValue: kind,
                isExpanded: true,
                dropdownColor: AppColors.navySurface,
                decoration: const InputDecoration(labelText: 'نوع القيد'),
                items: [
                  for (final k in LedgerKind.values.where((k) => k != LedgerKind.advance))
                    DropdownMenuItem(value: k, child: Text(k.label)),
                ],
                onChanged: (v) => set(() => kind = v!),
              ),
              DropdownButtonFormField<AppCurrency>(
                initialValue: cur,
                dropdownColor: AppColors.navySurface,
                decoration: const InputDecoration(labelText: 'العملة'),
                items: [for (final x in AppCurrency.values) DropdownMenuItem(value: x, child: Text(x.label))],
                onChanged: (v) => set(() => cur = v!),
              ),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: const InputDecoration(labelText: 'المبلغ'),
              ),
              TextField(controller: ref, decoration: const InputDecoration(labelText: 'المرجع (سند أو قرار)')),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'البيان')),
              const SizedBox(height: 8),
              const Text('السلف لا تُقيَّد يدوياً: تُسجَّل كعملية تمر بقواعد العقد ثم تُرحَّل آلياً.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تسجيل')),
          ],
        ),
      ),
    );
    final v = double.tryParse(amount.text);
    if (ok == true && v != null && v > 0 && ref.text.trim().isNotEmpty) {
      daily.addLedger(
          c,
          LedgerEntry(
            id: 'L${DateTime.now().microsecondsSinceEpoch}',
            companyId: c.id,
            partnerId: mp.id,
            kind: kind,
            amount: v,
            currency: cur,
            date: DateTime.now(),
            reference: ref.text.trim(),
            note: note.text.trim(),
            createdBy: cs.me?.id ?? '',
          ));
    } else if (ok == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل مبلغاً صحيحاً ومرجعاً للقيد.')));
    }
    amount.dispose();
    ref.dispose();
    note.dispose();
  }
}
