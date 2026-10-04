import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/company.dart';
import '../../models/family.dart';
import '../../models/questionnaire.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../providers/family_state.dart';
import '../../services/identity_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../versions/amendment_screens.dart';
import 'family_decisions_screen.dart';

final _d = DateFormat('yyyy/MM/dd');

/// R12: توزيع الأرباح العائلية حسب قاعدة الدستور الساري وإصداره. المعتمد والمنفّذ لا يتغيران.
class DistributionScreen extends StatelessWidget {
  const DistributionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final f = context.watch<FamilyState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final cur = f.current(c.id);
    final list = f.distributionsFor(c.id);
    final founder = cs.me?.isPartner ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('توزيع الأرباح العائلية')),
      floatingActionButton: founder && cur != null
          ? FloatingActionButton.extended(
              onPressed: () => _create(context, c),
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.navyDark,
              icon: const Icon(Icons.add_rounded),
              label: const Text('توزيع جديد'),
            )
          : null,
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
          children: [
            StateBanner(
              color: cur == null ? AppColors.warning : AppColors.info,
              icon: Icons.rule_rounded,
              text: cur == null
                  ? 'لا يوجد دستور عائلي ساري يحدد قاعدة التوزيع. اعتمدوا الدستور أولاً.'
                  : 'القاعدة السارية: ${cur.distributionRule.label} (الدستور الإصدار ${cur.version}). التوزيعات المعتمدة لا يُعاد حسابها.',
            ),
            if (list.isEmpty) const StateView.empty(icon: Icons.volunteer_activism_rounded, title: 'لا توجد توزيعات', message: ''),
            for (final x in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GovCard(
                  title: 'توزيع ${x.period} · ${formatCurrency(x.available, x.currency)}',
                  icon: Icons.volunteer_activism_rounded,
                  trailing: Text(x.status.label, style: TextStyle(color: x.status.color, fontWeight: FontWeight.w800, fontSize: 12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('${x.rule.label} · الدستور الإصدار ${x.constitutionVersion}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    for (final e in x.allocations.entries)
                      Row(children: [
                        Expanded(child: Text(familyName(c, f, e.key))),
                        Text(formatCurrency(e.value, x.currency), style: const TextStyle(fontWeight: FontWeight.w800)),
                      ]),
                    if (x.executionRef != null)
                      Text('نُفّذ ${_d.format(x.executedAt!)} · المرجع ${x.executionRef}', style: const TextStyle(color: AppColors.success, fontSize: 12)),
                    Wrap(spacing: 4, children: [
                      if (founder && (x.status == DistributionStatus.draft || x.status == DistributionStatus.rejected))
                        TextButton(onPressed: () => f.submitDistribution(c, x, by: cs.me!.id), child: const Text('رفع للقرار العائلي')),
                      if (x.decisionRef != null)
                        TextButton(
                          onPressed: () => Navigator.push(
                              context, MaterialPageRoute(builder: (_) => FamilyDecisionScreen(decisionId: x.decisionRef!))),
                          child: const Text('القرار'),
                        ),
                      if (founder && x.status == DistributionStatus.approved)
                        TextButton(onPressed: () => _execute(context, c, x), child: const Text('تسجيل التنفيذ')),
                    ]),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, Company c) async {
    final f = context.read<FamilyState>();
    final period = TextEditingController(text: '${DateTime.now().year}');
    final amount = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navySurface,
        title: const Text('توزيع أرباح'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: period, decoration: const InputDecoration(labelText: 'الفترة (مثل 2026 أو الربع الثالث 2026)')),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: InputDecoration(labelText: 'الربح المتاح للتوزيع', suffixText: c.currency.code),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('معاينة')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      final err = f.createDistribution(c, period: period.text, available: double.tryParse(amount.text) ?? 0, by: context.read<CompanyState>().me!.id);
      if (err != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
    period.dispose();
    amount.dispose();
  }

  Future<void> _execute(BuildContext context, Company c, FamilyDistribution x) async {
    final t = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navySurface,
        title: const Text('تسجيل التنفيذ'),
        content: TextField(controller: t, decoration: const InputDecoration(labelText: 'مرجع السداد (سند أو حوالة)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تسجيل')),
        ],
      ),
    );
    if (ok == true && context.mounted) context.read<FamilyState>().executeDistribution(c, x, reference: t.text);
    t.dispose();
  }
}

/// R13: الخلافة ونقل القرار. لا تبدأ إلا بحدث مسجّل بدليل، وتُعتمد بقرار عائلي،
/// وانتقال الحصص يُنفَّذ بإصدار جديد لجدول الحصص في العقد يوقّعه أصحاب الحصص الجديدة.
class SuccessionScreen extends StatelessWidget {
  const SuccessionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final f = context.watch<FamilyState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final list = f.successionsFor(c.id);
    final founder = cs.me?.isPartner ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('الخلافة ونقل القرار')),
      floatingActionButton: founder
          ? FloatingActionButton.extended(
              onPressed: () => _start(context, c),
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.navyDark,
              icon: const Icon(Icons.add_rounded),
              label: const Text('تسجيل حدث'),
            )
          : null,
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
          children: [
            StateBanner.readOnly('لا يستنتج التطبيق أي حدث: تبدأ الخلافة بتسجيل حدث موثَّق، ولا تُعتمد قبل إرفاق الدليل وقرار العائلة.'),
            if (list.isEmpty) const StateView.empty(icon: Icons.swap_horiz_rounded, title: 'لا توجد إجراءات خلافة', message: ''),
            for (final x in list) _CaseCard(c: c, x: x, founder: founder),
          ],
        ),
      ),
    );
  }

  Future<void> _start(BuildContext context, Company c) async {
    final f = context.read<FamilyState>();
    final people = f.peopleFor(c.id);
    if (people.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف أفراد العائلة في شجرة العائلة أولاً.')));
      return;
    }
    var event = SuccessionEvent.death;
    var subject = people.first.id;
    var successor = people[1].id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: AppColors.navySurface,
          title: const Text('تسجيل حدث خلافة'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<SuccessionEvent>(
              initialValue: event,
              dropdownColor: AppColors.navySurface,
              decoration: const InputDecoration(labelText: 'الحدث'),
              items: [for (final e in SuccessionEvent.values) DropdownMenuItem(value: e, child: Text(e.label))],
              onChanged: (v) => set(() => event = v!),
            ),
            DropdownButtonFormField<String>(
              initialValue: subject,
              isExpanded: true,
              dropdownColor: AppColors.navySurface,
              decoration: const InputDecoration(labelText: 'صاحب الحدث'),
              items: [for (final p in people) DropdownMenuItem(value: p.id, child: Text(p.name))],
              onChanged: (v) => set(() => subject = v!),
            ),
            DropdownButtonFormField<String>(
              initialValue: successor,
              isExpanded: true,
              dropdownColor: AppColors.navySurface,
              decoration: const InputDecoration(labelText: 'الخلف في القرار'),
              items: [for (final p in people) DropdownMenuItem(value: p.id, child: Text(p.name))],
              onChanged: (v) => set(() => successor = v!),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تسجيل')),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      final err = f.startSuccession(c, event: event, subjectId: subject, eventDate: DateTime.now(), successorId: successor, by: context.read<CompanyState>().me!.id);
      if (err != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }
}

class _CaseCard extends StatelessWidget {
  final Company c;
  final SuccessionCase x;
  final bool founder;
  const _CaseCard({required this.c, required this.x, required this.founder});

  @override
  Widget build(BuildContext context) {
    final f = context.read<FamilyState>();
    final st = context.read<ContractState>();
    final eq = x.status == SuccessionStatus.effective ? f.equityAfterSuccession(c, x) : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GovCard(
        title: '${x.event.label}: ${x.currentAuthority}',
        icon: Icons.swap_horiz_rounded,
        trailing: Text(x.status.label, style: const TextStyle(color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.w800)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('صاحب القرار الحالي: ${x.currentAuthority} ← الخلف: ${f.person(x.successorId)?.name ?? ''}', style: const TextStyle(height: 1.7)),
          Text('تاريخ الحدث ${_d.format(x.eventDate)}${x.effectiveAt == null ? '' : ' · نافذة من ${_d.format(x.effectiveAt!)}'}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          for (final e in x.evidence) Text('• $e', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          if (eq != null) ...[
            const SizedBox(height: 6),
            Text(
              'الحصص بعد الخلافة: ${eq.$1.entries.where((e) => e.value > 0).map((e) => '${familyName(c, f, e.key)} ${e.value.toStringAsFixed(2)}%').join('، ')}',
              style: const TextStyle(color: AppColors.gold, fontSize: 12.5),
            ),
            if (eq.$2.isNotEmpty)
              Text('ورثة بلا حساب في التطبيق: ${eq.$2.join('، ')}. ادعُهم من شجرة العائلة واربطهم بأسمائهم ليوقّعوا الإصدار.',
                  style: const TextStyle(color: AppColors.warning, fontSize: 12)),
          ],
          if (x.status == SuccessionStatus.effective && x.event == SuccessionEvent.death && f.approvedDeedFor(c.id, x.subjectId) == null)
            const Text('اعتمدوا حصر الوراثة الرسمي من شاشة العائلة والورثة لتحديد أنصبة الحصص.',
                style: TextStyle(color: AppColors.warning, fontSize: 12)),
          if (founder)
            Wrap(spacing: 4, children: [
              if (x.status == SuccessionStatus.pendingEvidence || x.status == SuccessionStatus.rejected) ...[
                TextButton(onPressed: () => _evidence(context), child: const Text('إرفاق دليل')),
                TextButton(
                  onPressed: () {
                    final err = f.submitSuccession(c, x, by: context.read<CompanyState>().me!.id);
                    if (err != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                  },
                  child: const Text('رفع للقرار العائلي'),
                ),
              ],
              if (x.decisionRef != null)
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FamilyDecisionScreen(decisionId: x.decisionRef!))),
                  child: const Text('القرار'),
                ),
              if (eq != null && eq.$2.isEmpty && x.amendmentRef == null)
                TextButton(onPressed: () => _transfer(context, eq.$1), child: const Text('إنشاء إصدار جدول الحصص')),
              if (x.amendmentRef != null)
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AmendmentDetailScreen(sessionId: x.amendmentRef!))),
                  child: const Text('الإصدار المرتبط'),
                ),
            ]),
          if (eq == null && x.status == SuccessionStatus.effective && st.currentContract(c.id) == null)
            const Text('لا يوجد عقد معتمد لنقل الحصص.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ]),
      ),
    );
  }

  Future<void> _evidence(BuildContext context) async {
    final t = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navySurface,
        title: const Text('دليل رسمي'),
        content: TextField(controller: t, decoration: const InputDecoration(labelText: 'نوع الدليل ورقمه (شهادة وفاة رقم...)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إرفاق')),
        ],
      ),
    );
    if (ok == true && context.mounted) context.read<FamilyState>().addEvidence(c, x, t.text);
    t.dispose();
  }

  /// إصدار جدول الحصص: الورثة الأعضاء غير الشركاء يدخلون العقد شركاء جدداً ويوقّعون
  Future<void> _transfer(BuildContext context, Map<String, double> equity) async {
    final st = context.read<ContractState>();
    final f = context.read<FamilyState>();
    final me = context.read<CompanyState>().me!;
    final base = st.currentContract(c.id);
    if (base == null) return;
    final blocked = st.amendmentBlocker(c.id);
    if (blocked != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(blocked)));
      return;
    }
    final m = await IdentityService.confirm(context, partnerName: me.name, action: 'إنشاء إصدار جدول الحصص لتنفيذ الخلافة');
    if (m == null || !context.mounted) return;
    final newPartners = [
      for (final e in equity.entries)
        if (e.value > 0 && !base.partners.any((p) => p.id == e.key))
          for (final mem in c.members.where((x) => x.id == e.key))
            SessionPartner(id: mem.id, name: mem.name, nationalId: mem.nationalId, phone: mem.phone, equity: e.value),
    ];
    final s = st.proposeCapTable(base,
        equity: equity, reason: 'خلافة ${x.currentAuthority} (${x.event.label})', proposedBy: me.id, newPartners: newPartners);
    f.linkAmendment(c, x, s.id);
    Navigator.push(context, MaterialPageRoute(builder: (_) => AmendmentDetailScreen(sessionId: s.id)));
  }
}
