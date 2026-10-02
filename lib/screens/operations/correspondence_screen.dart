import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/company.dart';
import '../../models/dispute.dart';
import '../../models/ops_extra.dart';
import '../../models/questionnaire.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../providers/daily_ops_state.dart';
import '../../providers/dispute_state.dart';
import '../../theme/app_theme.dart';
import 'tx_widgets.dart';

/// O16: المراسلات. سجل الصادر والوارد بمراجعه وربطه بالعقد أو القرار أو النزاع.
/// الصادرة تُسجَّل ويُقفل نصها؛ الإرسال الفعلي يحتاج مزوّد بريد أو رسائل. المراسلات الرسمية لا تُحذف.
class CorrespondenceScreen extends StatefulWidget {
  const CorrespondenceScreen({super.key});

  @override
  State<CorrespondenceScreen> createState() => _CorrespondenceScreenState();
}

class _CorrespondenceScreenState extends State<CorrespondenceScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final daily = context.watch<DailyOpsState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    bool match(Letter l) =>
        _q.isEmpty || l.reference.contains(_q) || l.subject.contains(_q) || l.party.contains(_q) || (l.relatedLabel ?? '').contains(_q);
    final all = daily.lettersFor(c.id).where(match).toList();

    Widget list(bool out) {
      final items = all.where((l) => l.outgoing == out).toList();
      return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 90), children: [
        if (items.isEmpty)
          StateView.empty(
              icon: Icons.mail_outline_rounded,
              title: out ? 'لا توجد مراسلات صادرة' : 'لا توجد مراسلات واردة',
              message: 'سجّل المراسلة بمرجعها وجهتها، واربطها بالقرار أو العقد أو النزاع.'),
        for (final l in items)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              onTap: () => _open(context, c, l),
              leading: Icon(out ? Icons.outbox_rounded : Icons.move_to_inbox_rounded, color: AppColors.gold),
              title: Text(l.subject, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                '${l.reference} · ${txDate.format(l.date)} · ${out ? 'إلى' : 'من'} ${l.party}'
                '${l.relatedLabel == null ? '' : '\nمرتبطة بـ: ${l.relatedLabel}'}${l.attachments.isEmpty ? '' : ' · ${l.attachments.length} مرفقات'}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.5),
              ),
              isThreeLine: l.relatedLabel != null,
              trailing: Text(l.status.label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
            ),
          ),
      ]);
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المراسلات'),
          bottom: const TabBar(tabs: [Tab(text: 'الصادر'), Tab(text: 'الوارد')]),
        ),
        floatingActionButton: Builder(
          builder: (ctx) => FloatingActionButton.extended(
            onPressed: () => _edit(context, c, null, DefaultTabController.of(ctx).index == 0),
            backgroundColor: AppColors.gold,
            foregroundColor: AppColors.navyDark,
            icon: const Icon(Icons.add_rounded),
            label: const Text('مراسلة'),
          ),
        ),
        body: ContentWidth(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: TextField(
                onChanged: (v) => setState(() => _q = v.trim()),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), labelText: 'بحث بالمرجع أو الموضوع أو الجهة', isDense: true),
              ),
            ),
            Expanded(child: TabBarView(children: [list(true), list(false)])),
          ]),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, Company c, Letter? l, bool outgoing) async {
    final cs = context.read<CompanyState>();
    final daily = context.read<DailyOpsState>();
    final st = context.read<ContractState>();
    final ds = context.read<DisputeState>();
    final party = TextEditingController(text: l?.party ?? '');
    final subject = TextEditingController(text: l?.subject ?? '');
    final body = TextEditingController(text: l?.body ?? '');
    final attach = TextEditingController();
    // ما يمكن الربط به: إصدارات العقد المعتمدة والنزاعات
    final targets = <String, (String, String)>{
      for (final s in st.versionsFor(c.id).where((s) => s.status == SessionStatus.completed))
        's:${s.id}': ('contract', 'العقد الإصدار ${s.version}'),
      for (final d in ds.disputesFor(c.id)) 'd:${d.id}': ('dispute', 'نزاع: ${d.trigger.label}'),
    };
    String? related = l?.relatedId == null ? null : '${l!.relatedType == 'contract' ? 's' : 'd'}:${l.relatedId}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: AppColors.navySurface,
          title: Text('${outgoing ? 'مراسلة صادرة' : 'مراسلة واردة'} ${l?.reference ?? daily.nextReference(c.id, outgoing)}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: party, decoration: InputDecoration(labelText: outgoing ? 'الجهة المرسل إليها' : 'الجهة المرسلة')),
              TextField(controller: subject, decoration: const InputDecoration(labelText: 'الموضوع')),
              TextField(controller: body, maxLines: 4, decoration: const InputDecoration(labelText: 'النص أو الملخص')),
              DropdownButtonFormField<String?>(
                initialValue: targets.containsKey(related) ? related : null,
                isExpanded: true,
                dropdownColor: AppColors.navySurface,
                decoration: const InputDecoration(labelText: 'ربط بـ'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('بدون ربط')),
                  for (final e in targets.entries) DropdownMenuItem(value: e.key, child: Text(e.value.$2)),
                ],
                onChanged: (v) => set(() => related = v),
              ),
              TextField(controller: attach, decoration: const InputDecoration(labelText: 'مرفق (اسم المستند ومرجعه)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ كمسودة')),
          ],
        ),
      ),
    );
    if (ok == true && subject.text.trim().isNotEmpty && party.text.trim().isNotEmpty) {
      final t = related == null ? null : targets[related];
      final x = l ??
          Letter(
            id: 'LT${DateTime.now().microsecondsSinceEpoch}',
            companyId: c.id,
            reference: daily.nextReference(c.id, outgoing),
            outgoing: outgoing,
            date: DateTime.now(),
            party: '',
            subject: '',
            createdBy: cs.me?.id ?? '',
          );
      x
        ..party = party.text.trim()
        ..subject = subject.text.trim()
        ..body = body.text.trim()
        ..relatedType = t?.$1
        ..relatedId = related?.substring(2)
        ..relatedLabel = t?.$2;
      if (attach.text.trim().isNotEmpty) x.attachments = [...x.attachments, attach.text.trim()];
      daily.saveLetter(c, x);
    }
    for (final y in [party, subject, body, attach]) {
      y.dispose();
    }
  }

  void _open(BuildContext context, Company c, Letter l) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.navySurface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) {
          final daily = context.read<DailyOpsState>();
          void go(LetterStatus s) {
            daily.setLetterStatus(c, l, s);
            Navigator.pop(ctx);
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(l.subject, style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
                  Text('${l.reference} · ${l.status.label} · ${l.outgoing ? 'إلى' : 'من'} ${l.party}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  const SizedBox(height: 10),
                  if (l.body.isNotEmpty) Text(l.body, style: const TextStyle(height: 1.7)),
                  for (final a in l.attachments) Text('• $a', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                  if (l.locked)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('صدرت المراسلة: نصها مقفل ولا تُحذف. يمكن تحديث حالة التسليم أو أرشفتها.',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                    ),
                  const SizedBox(height: 12),
                  if (l.status == LetterStatus.draft) ...[
                    ElevatedButton.icon(
                      onPressed: () => go(LetterStatus.sent),
                      icon: const Icon(Icons.send_rounded),
                      label: Text(l.outgoing ? 'إصدار وتسجيل (الإرسال يحتاج مزوّد بريد)' : 'تسجيل الوارد'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _edit(context, c, l, l.outgoing);
                      },
                      child: const Text('تعديل المسودة'),
                    ),
                    TextButton(
                      onPressed: () {
                        daily.deleteDraft(c, l);
                        Navigator.pop(ctx);
                      },
                      child: const Text('حذف المسودة', style: TextStyle(color: AppColors.danger)),
                    ),
                  ],
                  if (l.status == LetterStatus.sent) ...[
                    OutlinedButton(onPressed: () => go(LetterStatus.delivered), child: const Text('تأكيد الاستلام')),
                    OutlinedButton(onPressed: () => go(LetterStatus.failed), child: const Text('تعذّر التسليم')),
                  ],
                  if (l.locked && l.status != LetterStatus.archived)
                    TextButton(onPressed: () => go(LetterStatus.archived), child: const Text('أرشفة')),
                ]),
              ),
            ),
          );
        },
      );
}
