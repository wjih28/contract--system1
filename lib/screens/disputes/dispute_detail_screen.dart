import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/gov_status.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/company.dart';
import '../../models/dispute.dart';
import '../../models/questionnaire.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../providers/dispute_state.dart';
import '../../services/identity_service.dart';
import '../../services/report_pdf.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../establishment/decision_details_screen.dart';
import '../operations/violations_screen.dart';
import '../versions/amendment_screens.dart';
import 'disputes_screen.dart';

final _dt = DateFormat('yyyy/MM/dd HH:mm');

/// P19: تفاصيل النزاع. رأس التذكرة، متتبع المراحل والمهل، الأطراف، إجراءات المرحلة الحالية،
/// الأدلة، والخط الزمني الكامل. النزاع لا يغيّر شروط العقد بصمت: أي تغيير يمر بإصدار جديد.
class DisputeDetailScreen extends StatelessWidget {
  final String disputeId;
  const DisputeDetailScreen({super.key, required this.disputeId});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final ds = context.watch<DisputeState>();
    final c = cs.current;
    final d = ds.dispute(disputeId);
    if (c == null || d == null) {
      return const Scaffold(body: StateView.empty(title: 'التذكرة غير متاحة', message: ''));
    }
    final me = cs.me;
    final party = me != null && d.parties.contains(me.id);
    String name(String id) => id == 'system' ? 'النظام' : c.members.where((m) => m.id == id).firstOrNull?.name ?? id;
    final evidence = d.entries.where((e) => e.kind == EntryKind.evidence).toList();

    return Scaffold(
      appBar: AppBar(title: Text('تذكرة ${d.id}')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            if (!d.isOpen)
              StateBanner.readOnly(d.status == DisputeStatus.closed
                  ? 'التذكرة مغلقة ومحفوظة للقراءة فقط.'
                  : 'حُسم النزاع. ${d.needsAmendment ? 'بقي تنفيذ الحسم بإصدار جديد للعقد.' : ''}')
            else if (!party)
              StateBanner.readOnly('أنت لست طرفاً في هذا النزاع: يمكنك الاطلاع فقط.'),
            // رأس التذكرة
            GovCard(
              title: d.trigger.label,
              icon: d.trigger.icon,
              trailing: StatusBadge(disputeGov(d), overrideLabel: d.status.label, dense: true),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.issue, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.6)),
                const SizedBox(height: 8),
                Text(
                  'فُتحت ${_dt.format(d.openedAt.toLocal())} بواسطة ${name(d.openedBy)} · إصدار العقد ${d.contractVersion}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text('الأطراف: ${d.parties.map(name).join('، ')}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                if (d.relatedType != null) _related(context, d),
                if (d.outcome != null) ...[
                  const SizedBox(height: 8),
                  Text('النتيجة: ${d.outcome}',
                      style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700, height: 1.6)),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            _StageTracker(d: d),
            const SizedBox(height: 12),
            if (d.isOpen || d.needsAmendment || d.status == DisputeStatus.resolved)
              _Actions(c: c, d: d, party: party, me: me),
            const SizedBox(height: 12),
            GovCard(
              title: 'الأدلة (${evidence.length})',
              icon: Icons.attach_file_rounded,
              child: evidence.isEmpty
                  ? const Text('لم تُرفق أدلة بعد.', style: TextStyle(color: AppColors.textMuted, fontSize: 12.5))
                  : Column(children: [
                      for (final e in evidence)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.description_outlined, color: AppColors.gold),
                          title: Text(e.text),
                          subtitle: Text(
                              '${e.authorName} · ${_dt.format(e.at.toLocal())}${e.evidenceRef == null ? '' : ' · ${e.evidenceRef}'}',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                        ),
                    ]),
            ),
            const SizedBox(height: 12),
            GovCard(
              title: 'الخط الزمني',
              icon: Icons.timeline_rounded,
              child: Column(children: [
                for (final e in d.entries.reversed) _EntryTile(e: e),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _related(BuildContext context, Dispute d) {
    final st = context.read<ContractState>();
    VoidCallback? open;
    var label = 'السجل المرتبط';
    if (d.relatedType == 'clause') {
      final parts = d.relatedId!.split(':');
      final s = st.sessions.where((x) => x.id == parts.first).firstOrNull;
      final key = parts.length >= 3 ? parts.sublist(1, parts.length - 1).join(':') : null;
      if (s != null && key != null) {
        label = 'فتح القرار المتعثر';
        open = () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => DecisionDetailsScreen(sessionId: s.id, recordKey: key)));
      }
    } else if (d.relatedType == 'violation') {
      label = 'فتح المخالفة المرتبطة';
      open = () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ViolationsScreen()));
    }
    if (open == null) return const SizedBox.shrink();
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(onPressed: open, icon: const Icon(Icons.open_in_new_rounded, size: 18), label: Text(label)),
    );
  }
}

/// متتبع المراحل الخمس مع المهلة الحالية
class _StageTracker extends StatelessWidget {
  final Dispute d;
  const _StageTracker({required this.d});

  @override
  Widget build(BuildContext context) {
    final left = d.deadline.difference(DateTime.now());
    final timed = d.isOpen && d.stage.index < DisputeStage.arbitration.index;
    return GovCard(
      title: 'مسار الحل',
      icon: Icons.route_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in DisputeStage.values)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: s == d.stage
                    ? AppColors.gold.withValues(alpha: 0.18)
                    : s.index < d.stage.index
                        ? AppColors.success.withValues(alpha: 0.1)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: s == d.stage ? AppColors.gold : s.index < d.stage.index ? AppColors.success : AppColors.divider),
              ),
              child: Text('${s.index + 1}. ${s.label}',
                  style: TextStyle(
                      color: s == d.stage ? AppColors.gold : s.index < d.stage.index ? AppColors.success : AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: s == d.stage ? FontWeight.w800 : FontWeight.w500)),
            ),
        ]),
        const SizedBox(height: 10),
        Text(d.stage.hint, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.6)),
        if (timed) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.timer_outlined, size: 18, color: left.inDays < 3 ? AppColors.danger : AppColors.warning),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'المهلة حتى ${_dt.format(d.deadline.toLocal())} · '
                '${left.isNegative ? 'انقضت وتنتقل التذكرة آلياً' : left.inDays >= 1 ? 'باقٍ ${left.inDays} يوماً' : 'باقٍ ${left.inHours} ساعة'}. '
                'انقضاء المهلة دون اتفاق ينقل النزاع للمرحلة التالية، ولا يُعدّ قبولاً.',
                style: TextStyle(color: left.inDays < 3 ? AppColors.danger : AppColors.textSecondary, fontSize: 12, height: 1.5),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final DisputeEntry e;
  const _EntryTile({required this.e});

  @override
  Widget build(BuildContext context) {
    final c = e.isSystem ? AppColors.info : AppColors.gold;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: Icon(e.kind.icon, size: 14, color: c),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${e.kind.label} · ${e.authorName}',
                style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(e.text, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.5)),
            Text('${_dt.format(e.at.toLocal())} · ${e.stage.label}${e.evidenceRef == null ? '' : ' · ${e.evidenceRef}'}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ]),
        ),
      ]),
    );
  }
}

/// إجراءات المرحلة الحالية حسب صلاحية المستخدم
class _Actions extends StatelessWidget {
  final Company c;
  final Dispute d;
  final bool party;
  final CompanyMember? me;
  const _Actions({required this.c, required this.d, required this.party, required this.me});

  @override
  Widget build(BuildContext context) {
    final ds = context.read<DisputeState>();
    String name(String id) => c.members.where((m) => m.id == id).firstOrNull?.name ?? id;
    final children = <Widget>[];

    void button(String label, IconData icon, VoidCallback? on, {bool primary = false}) => children.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: primary
              ? ElevatedButton.icon(onPressed: on, icon: Icon(icon), label: Text(label))
              : OutlinedButton.icon(onPressed: on, icon: Icon(icon), label: Text(label)),
        ));

    // ───── بعد الحسم ─────
    if (d.status == DisputeStatus.resolved) {
      if (d.needsAmendment && party) {
        button('إنشاء الإصدار الجديد لتنفيذ الحسم', Icons.history_edu_rounded, () => _createVersion(context), primary: true);
      } else if (d.amendmentRef != null) {
        button('فتح الإصدار المرتبط', Icons.open_in_new_rounded, () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => AmendmentDetailScreen(sessionId: d.amendmentRef!))));
      }
      if (!d.needsAmendment && party) {
        button('إغلاق التذكرة', Icons.archive_rounded, () => ds.close(c, d, byName: me!.name));
      }
      return GovCard(title: 'تنفيذ الحسم', icon: Icons.task_alt_rounded, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children));
    }
    if (!party) return const SizedBox.shrink();

    // ───── مدخلات عامة ─────
    if (d.stage.index <= DisputeStage.arbitration.index) {
      button('إضافة رد', Icons.chat_bubble_outline_rounded, () async {
        final t = await _ask(context, 'ردك في النزاع', ['النص']);
        if (t != null) ds.addEntry(c, d, EntryKind.response, t[0], authorId: me!.id, authorName: me!.name);
      });
      button('إرفاق دليل', Icons.attach_file_rounded, () async {
        final t = await _ask(context, 'إرفاق دليل', ['وصف الدليل', 'المرجع (رقم مستند أو رابط)']);
        if (t != null) {
          ds.addEntry(c, d, EntryKind.evidence, t[0],
              authorId: me!.id, authorName: me!.name, evidenceRef: t[1].isEmpty ? null : t[1]);
        }
      });
    }

    switch (d.stage) {
      case DisputeStage.negotiation:
      case DisputeStage.mediation:
        if (d.stage == DisputeStage.mediation) {
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('جهة الوساطة: ${d.mediator ?? 'لم تُحدد بعد'}',
                style: const TextStyle(color: AppColors.textSecondary)),
          ));
          button('تحديد جهة الوساطة', Icons.account_balance_rounded, () async {
            final t = await _ask(context, 'جهة الوساطة', ['اسم الجهة (مجلس العائلة، الغرفة التجارية، مركز توفيق)']);
            if (t != null) ds.setMediator(c, d, t[0]);
          });
        }
        final s = d.settlement;
        if (s != null) {
          children.add(Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('محضر صلح مقترح من ${name(s.proposedBy)}',
                  style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(s.text, style: const TextStyle(color: AppColors.textPrimary, height: 1.6)),
              const SizedBox(height: 4),
              Text(
                'الموافقون: ${s.approvals.keys.map(name).join('، ')} (${s.approvals.length} من ${d.parties.length})'
                '${s.requiresAmendment ? '\nيغيّر شروط العقد: يُنفَّذ بإصدار جديد بعد اعتماده' : ''}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.5),
              ),
            ]),
          ));
          if (!s.approvals.containsKey(me!.id)) {
            button('الموافقة على محضر الصلح', Icons.handshake_rounded, () async {
              final m = await IdentityService.confirm(context, partnerName: me!.name, action: 'الموافقة على محضر الصلح');
              if (m != null) ds.approveSettlement(c, d, me!.id, memberName: me!.name, method: m.label);
            }, primary: true);
          }
        }
        button(s == null ? 'اقتراح محضر صلح' : 'اقتراح محضر بديل', Icons.edit_document, () => _propose(context));
        button(
          d.escalationConsents.contains(me!.id)
              ? 'طلبت إنهاء المرحلة (${d.escalationConsents.length} من ${d.parties.length})'
              : 'إنهاء ${d.stage.label} دون اتفاق',
          Icons.trending_flat_rounded,
          d.escalationConsents.contains(me!.id) ? null : () => _confirmEscalate(context),
        );
      case DisputeStage.deadlockBreak:
        final o = d.buyOut;
        if (o != null && !o.decided) {
          final share = c.partners.where((p) => p.id == o.targetId).firstOrNull?.equity ?? 0;
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'عرض ${name(o.offerorId)}: شراء حصة ${name(o.targetId)} (${share.toStringAsFixed(2)}%) بمبلغ '
              '${formatCurrency(o.price, c.currency)}. المهلة حتى ${_dt.format(o.deadline.toLocal())}.',
              style: const TextStyle(color: AppColors.textPrimary, height: 1.6),
            ),
          ));
          if (o.targetId == me!.id) {
            button('أبيع حصتي بهذا السعر', Icons.sell_rounded, () => _choose(context, sell: true), primary: true);
            button('أشتري حصة ${name(o.offerorId)} بنفس السعر', Icons.shopping_bag_rounded, () => _choose(context, sell: false));
          }
        } else {
          button('تقديم عرض شراء مغلق وملزم', Icons.local_offer_rounded, () => _offer(context), primary: true);
          button(
            d.escalationConsents.contains(me!.id) ? 'طلبت الإحالة للتحكيم' : 'الإحالة للتحكيم باتفاق الأطراف',
            Icons.gavel_rounded,
            d.escalationConsents.contains(me!.id) ? null : () => _confirmEscalate(context),
          );
        }
      case DisputeStage.arbitration:
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'مركز التحكيم: ${d.arbitrationCenter ?? 'لم يُحدد بعد'}${d.caseFileHash == null ? '' : '\nملف القضية مُصدَّر · مرجع السلامة ${d.caseFileHash!.substring(0, 16)}…'}\n'
            'الاستثناءات المالية موقوفة حتى صدور الحكم.',
            style: const TextStyle(color: AppColors.textSecondary, height: 1.6),
          ),
        ));
        button('تحديد مركز التحكيم', Icons.account_balance_rounded, () async {
          final t = await _ask(context, 'مركز التحكيم', ['اسم المركز (مثل المركز اليمني للتوفيق والتحكيم)']);
          if (t != null) ds.setArbitrationCenter(c, d, t[0]);
        });
        button('تصدير ملف القضية', Icons.picture_as_pdf_rounded, () => _exportCase(context), primary: d.caseFileHash == null);
        button('تسجيل حكم التحكيم', Icons.gavel_rounded, () => _award(context), primary: d.caseFileHash != null);
      case DisputeStage.liquidation:
        children.add(_LiquidationPanel(c: c, d: d));
    }

    return GovCard(
      title: 'إجراءات ${d.stage.label}',
      icon: Icons.touch_app_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  Future<void> _confirmEscalate(BuildContext context) async {
    final m = await IdentityService.confirm(context, partnerName: me!.name, action: 'إنهاء ${d.stage.label} دون اتفاق');
    if (m != null && context.mounted) context.read<DisputeState>().consentEscalate(c, d, me!.id, memberName: me!.name);
  }

  Future<void> _propose(BuildContext context) async {
    final text = TextEditingController();
    var amend = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: AppColors.navySurface,
          title: const Text('محضر صلح'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: text, maxLines: 4, decoration: const InputDecoration(labelText: 'نص الاتفاق')),
            CheckboxListTile(
              value: amend,
              onChanged: (v) => set(() => amend = v!),
              contentPadding: EdgeInsets.zero,
              title: const Text('يغيّر شروط العقد (يُنفَّذ بإصدار جديد)', style: TextStyle(fontSize: 13)),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('اقتراح')),
          ],
        ),
      ),
    );
    if (ok == true && text.text.trim().isNotEmpty && context.mounted) {
      context.read<DisputeState>().proposeSettlement(c, d, text.text,
          authorId: me!.id, authorName: me!.name, requiresAmendment: amend);
    }
    text.dispose();
  }

  Future<void> _offer(BuildContext context) async {
    final others = d.parties.where((p) => p != me!.id).toList();
    if (others.isEmpty) return;
    var target = others.first;
    final price = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: AppColors.navySurface,
          title: const Text('عرض شراء مغلق وملزم'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: target,
              dropdownColor: AppColors.navySurface,
              decoration: const InputDecoration(labelText: 'شراء حصة'),
              items: [
                for (final p in others)
                  DropdownMenuItem(
                      value: p,
                      child: Text(
                          '${c.members.firstWhere((m) => m.id == p).name} (${c.members.firstWhere((m) => m.id == p).equity.toStringAsFixed(2)}%)')),
              ],
              onChanged: (v) => set(() => target = v!),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: InputDecoration(labelText: 'السعر لكامل الحصة', suffixText: c.currency.code),
            ),
            const SizedBox(height: 8),
            const Text(
              'العرض ملزم: للطرف الآخر أن يبيع بهذا السعر أو يشتري حصتك بنفس سعر النسبة الواحدة. لا يجري أي دفع داخل التطبيق.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.6),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تقديم العرض')),
          ],
        ),
      ),
    );
    final v = double.tryParse(price.text);
    price.dispose();
    if (ok != true || v == null || !context.mounted) return;
    final m = await IdentityService.confirm(context, partnerName: me!.name, action: 'تقديم عرض شراء ملزم');
    if (m == null || !context.mounted) return;
    final err = context
        .read<DisputeState>()
        .submitBuyOut(c, d, offerorId: me!.id, targetId: target, price: v, offerorName: me!.name);
    if (err != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }

  Future<void> _choose(BuildContext context, {required bool sell}) async {
    final m = await IdentityService.confirm(context,
        partnerName: me!.name, action: sell ? 'بيع حصتي بالسعر المعروض' : 'شراء حصة صاحب العرض بنفس السعر');
    if (m != null && context.mounted) context.read<DisputeState>().chooseBuyOut(c, d, sell: sell, method: m.label);
  }

  Future<void> _exportCase(BuildContext context) async {
    final cs = context.read<CompanyState>();
    final ds = context.read<DisputeState>();
    final audit = cs.audit.where((e) => e.companyId == c.id).toList().reversed.toList();
    final hash = ReportPdf.caseHash(c, d, audit);
    ds.recordCaseFile(c, d, hash);
    await ReportPdf.shareCaseFile(c, d, audit, hash);
  }

  Future<void> _award(BuildContext context) async {
    final text = TextEditingController();
    final ref = TextEditingController();
    var outcome = AwardOutcome.dismiss;
    final eq = {for (final p in c.partners) p.id: TextEditingController(text: p.equity.toStringAsFixed(2))};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: AppColors.navySurface,
          title: const Text('تسجيل حكم التحكيم'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<AwardOutcome>(
                initialValue: outcome,
                dropdownColor: AppColors.navySurface,
                decoration: const InputDecoration(labelText: 'منطوق الحكم'),
                items: [for (final o in AwardOutcome.values) DropdownMenuItem(value: o, child: Text(o.label))],
                onChanged: (v) => set(() => outcome = v!),
              ),
              TextField(controller: text, maxLines: 3, decoration: const InputDecoration(labelText: 'ملخص الحكم')),
              TextField(controller: ref, decoration: const InputDecoration(labelText: 'رقم الحكم ومرجعه')),
              if (outcome == AwardOutcome.equityChange)
                for (final p in c.partners)
                  TextField(
                    controller: eq[p.id],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'حصة ${p.name} بعد الحكم', suffixText: '%'),
                  ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تسجيل')),
          ],
        ),
      ),
    );
    final equity = {for (final e in eq.entries) e.key: double.tryParse(e.value.text) ?? 0};
    final total = equity.values.fold<double>(0, (a, b) => a + b);
    if (ok == true && context.mounted) {
      if (text.text.trim().isEmpty || ref.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل ملخص الحكم ومرجعه.')));
      } else if (outcome == AwardOutcome.equityChange && (total - 100).abs() > 0.01) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('مجموع الحصص يجب أن يساوي 100% (الحالي ${total.toStringAsFixed(2)}%).')));
      } else {
        context.read<DisputeState>().recordAward(c, d,
            text: text.text, outcome: outcome, ref: ref.text, equity: outcome == AwardOutcome.equityChange ? equity : null);
      }
    }
    text.dispose();
    ref.dispose();
    for (final x in eq.values) {
      x.dispose();
    }
  }

  /// تنفيذ الحسم بإصدار جديد: جدول حصص من الشراء أو الحكم، أو تعديل بنود من محضر صلح
  Future<void> _createVersion(BuildContext context) async {
    final st = context.read<ContractState>();
    final ds = context.read<DisputeState>();
    final base = st.currentContract(c.id);
    if (base == null) return;
    if (d.equityAfter == null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => AmendmentProposalScreen(disputeRef: d.id)));
      return;
    }
    final blocked = st.amendmentBlocker(c.id, disputeRef: d.id);
    if (blocked != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(blocked)));
      return;
    }
    final m = await IdentityService.confirm(context, partnerName: me!.name, action: 'إنشاء إصدار جدول الحصص الجديد');
    if (m == null || !context.mounted) return;
    final s = st.proposeCapTable(base,
        equity: d.equityAfter!, reason: d.outcome ?? 'تنفيذ حسم النزاع', proposedBy: me!.id, disputeRef: d.id);
    ds.linkAmendment(c, d, s.id);
    Navigator.push(context, MaterialPageRoute(builder: (_) => AmendmentDetailScreen(sessionId: s.id)));
  }
}

/// المرحلة 5: جرد الأصول والديون وجدول السداد والقسمة
class _LiquidationPanel extends StatelessWidget {
  final Company c;
  final Dispute d;
  const _LiquidationPanel({required this.c, required this.d});

  @override
  Widget build(BuildContext context) {
    final ds = context.read<DisputeState>();
    final me = context.read<CompanyState>().me;
    final p = DisputeState.plan(c, d);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        'المصفّي: ${d.liquidator ?? 'لم يُعيَّن'} · الأصول: ${d.liquidationAssets == null ? 'لم تُجرد' : formatCurrency(p.assets, c.currency)}',
        style: const TextStyle(color: AppColors.textSecondary),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () async {
          final t = await _ask(context, 'بيانات التصفية', ['اسم المصفّي المعتمد', 'إجمالي الأصول بعد الجرد']);
          if (t != null) ds.setLiquidation(c, d, liquidator: t[0].isEmpty ? null : t[0], assets: double.tryParse(t[1]));
        },
        icon: const Icon(Icons.inventory_rounded),
        label: const Text('المصفّي والأصول'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () async {
          final t = await _ask(context, 'دين على الشركة', ['الدائن', 'المبلغ', 'ممتاز؟ (اكتب نعم للديون الممتازة كالرواتب)']);
          final amount = t == null ? null : double.tryParse(t[1]);
          if (t != null && amount != null) {
            ds.addDebt(c, d, LiquidationDebt(creditor: t[0], amount: amount, preferred: t[2].trim() == 'نعم'));
          }
        },
        icon: const Icon(Icons.request_quote_rounded),
        label: const Text('إضافة دين'),
      ),
      const SizedBox(height: 10),
      for (final (debt, paid) in p.payments)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('${debt.creditor}${debt.preferred ? ' · ممتاز' : ''}'),
          trailing: Text('${formatCurrency(paid, c.currency)} من ${formatCurrency(debt.amount, c.currency)}',
              style: TextStyle(color: paid + 0.01 >= debt.amount ? AppColors.success : AppColors.warning)),
        ),
      const Divider(),
      Text('الصافي للتوزيع: ${formatCurrency(p.net, c.currency)}',
          style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800)),
      for (final m in c.partners)
        Text('${m.name} (${m.equity.toStringAsFixed(2)}%): ${formatCurrency(p.distribution[m.id] ?? 0, c.currency)}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
      const SizedBox(height: 10),
      ElevatedButton.icon(
        onPressed: d.liquidationAssets == null || me == null
            ? null
            : () async {
                final m = await IdentityService.confirm(context, partnerName: me.name, action: 'إغلاق التصفية وأرشفة الشركة');
                if (m != null) ds.closeLiquidation(c, d, method: m.label);
              },
        icon: const Icon(Icons.inventory_2_rounded),
        label: const Text('إغلاق التصفية وأرشفة الشركة'),
      ),
    ]);
  }
}

/// نافذة إدخال نصية بعدة حقول؛ تعيد null عند الإلغاء
Future<List<String>?> _ask(BuildContext context, String title, List<String> fields) async {
  final ctrls = [for (final _ in fields) TextEditingController()];
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.navySurface,
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < fields.length; i++)
            TextField(controller: ctrls[i], maxLines: i == 0 ? 3 : 1, minLines: 1, decoration: InputDecoration(labelText: fields[i])),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
      ],
    ),
  );
  final out = ctrls.map((c) => c.text.trim()).toList();
  for (final c in ctrls) {
    c.dispose();
  }
  return ok == true && out.first.isNotEmpty ? out : null;
}
