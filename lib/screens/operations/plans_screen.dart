import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/company.dart';
import '../../models/ops_extra.dart';
import '../../models/questionnaire.dart';
import '../../providers/company_state.dart';
import '../../providers/daily_ops_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import 'payroll_screen.dart';

/// O14: الخطط التشغيلية السنوية (مالية، إدارية، تقنية، تسويقية) مقسّمة على فترات.
/// اعتماد خطة لا يتجاوز حدود الصرف في العقد.
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  PlanCategory? _cat;

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final daily = context.watch<DailyOpsState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final list = daily.plansFor(c.id).where((p) => _cat == null || p.category == _cat).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('الخطط التشغيلية')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, c),
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.navyDark,
        icon: const Icon(Icons.add_rounded),
        label: const Text('خطة جديدة'),
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(label: const Text('كل الخطط'), selected: _cat == null, onSelected: (_) => setState(() => _cat = null)),
              for (final x in PlanCategory.values)
                ChoiceChip(label: Text(x.label), selected: _cat == x, onSelected: (_) => setState(() => _cat = x)),
            ]),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const StateView.empty(
                  icon: Icons.event_note_rounded,
                  title: 'لا توجد خطط',
                  message: 'أنشئ خطة سنوية وقسّمها إلى مراحل شهرية أو ربعية، ثم ارفعها للاعتماد وتابع تنفيذها.'),
            for (final p in list)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlanDetailScreen(planId: p.id))),
                  title: Text('${p.title} · ${p.year}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                    'خطة ${p.category.label} · ${p.segment.label} · المسؤول ${p.owner}\n'
                    '${p.milestones.where((m) => m.status == MilestoneStatus.completed).length} من ${p.milestones.length} مراحل مكتملة'
                    '${p.milestones.any((m) => m.status == MilestoneStatus.delayed || m.status == MilestoneStatus.blocked) ? ' · يوجد انحراف' : ''}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.5),
                  ),
                  isThreeLine: true,
                  trailing: Text(p.status.label, style: const TextStyle(color: AppColors.gold, fontSize: 12)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, Company c) async {
    final cs = context.read<CompanyState>();
    final daily = context.read<DailyOpsState>();
    final title = TextEditingController();
    final owner = TextEditingController(text: cs.me?.name ?? '');
    final objectives = TextEditingController();
    final budget = TextEditingController();
    var cat = PlanCategory.financial;
    var seg = PlanSegment.quarterly;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: AppColors.navySurface,
          title: Text('خطة ${DateTime.now().year}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<PlanCategory>(
                initialValue: cat,
                dropdownColor: AppColors.navySurface,
                decoration: const InputDecoration(labelText: 'نوع الخطة'),
                items: [for (final x in PlanCategory.values) DropdownMenuItem(value: x, child: Text(x.label))],
                onChanged: (v) => set(() => cat = v!),
              ),
              DropdownButtonFormField<PlanSegment>(
                initialValue: seg,
                dropdownColor: AppColors.navySurface,
                decoration: const InputDecoration(labelText: 'التقسيم'),
                items: [for (final x in PlanSegment.values) DropdownMenuItem(value: x, child: Text(x.label))],
                onChanged: (v) => set(() => seg = v!),
              ),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'العنوان')),
              TextField(controller: owner, decoration: const InputDecoration(labelText: 'المسؤول')),
              TextField(controller: objectives, maxLines: 3, decoration: const InputDecoration(labelText: 'الأهداف')),
              TextField(controller: budget, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'الميزانية (اختياري)', suffixText: c.currency.code)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إنشاء')),
          ],
        ),
      ),
    );
    if (ok == true && title.text.trim().isNotEmpty) {
      final p = OpsPlan(
        id: 'PL${DateTime.now().microsecondsSinceEpoch}',
        companyId: c.id,
        category: cat,
        year: DateTime.now().year,
        title: title.text.trim(),
        owner: owner.text.trim(),
        objectives: objectives.text.trim(),
        budget: double.tryParse(budget.text),
        segment: seg,
        milestones: [
          for (final (i, period) in seg.periods().indexed)
            Milestone(id: 'M${DateTime.now().microsecondsSinceEpoch}$i', title: 'مستهدف $period', period: period),
        ],
        createdBy: cs.me?.id ?? '',
        createdAt: DateTime.now(),
      );
      daily.savePlan(c, p);
      if (context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => PlanDetailScreen(planId: p.id)));
    }
    for (final x in [title, owner, objectives, budget]) {
      x.dispose();
    }
  }
}

/// O14 تفاصيل الخطة + O15 متابعة التنفيذ: المستهدف مقابل الفعلي والفرق والأدلة والانحرافات.
class PlanDetailScreen extends StatelessWidget {
  final String planId;
  const PlanDetailScreen({super.key, required this.planId});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final daily = context.watch<DailyOpsState>();
    final c = cs.current;
    final p = daily.plan(planId);
    if (c == null || p == null) return const Scaffold(body: StateView.empty(title: 'الخطة غير متاحة', message: ''));
    final draft = p.status == PlanStatus.draft || p.status == PlanStatus.rejected;
    final approver = canApproveOps(cs.myRoles);
    final name = cs.me?.name ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(p.title)),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            StateBanner(
              color: AppColors.info,
              icon: Icons.event_note_rounded,
              text: 'خطة ${p.category.label} ${p.year} · ${p.segment.label} · ${p.status.label}'
                  '${p.budget == null ? '' : ' · الميزانية ${formatCurrency(p.budget!, c.currency)}'}. '
                  'اعتماد الخطة لا يتجاوز حدود الصرف في العقد: كل عملية تمر بالفحص.',
            ),
            if (p.objectives.isNotEmpty)
              GovCard(title: 'الأهداف', icon: Icons.flag_rounded, child: Text(p.objectives, style: const TextStyle(height: 1.6))),
            const SizedBox(height: 12),
            GovCard(
              title: p.status == PlanStatus.approved ? 'متابعة التنفيذ' : 'المراحل',
              icon: Icons.timeline_rounded,
              child: Column(children: [
                for (final m in p.milestones)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onTap: () => draft ? _editTarget(context, c, p, m) : (p.status == PlanStatus.approved ? _progress(context, c, p, m) : null),
                    leading: Icon(Icons.circle, size: 12, color: m.status.color),
                    title: Text('${m.period}: ${m.title}'),
                    subtitle: Text(
                      '${m.target == null ? 'بلا مستهدف رقمي' : 'المستهدف ${m.target!.toStringAsFixed(0)}'}'
                      '${m.actual == null ? '' : ' · الفعلي ${m.actual!.toStringAsFixed(0)} · الفرق ${m.variance?.toStringAsFixed(0) ?? '—'}'}'
                      ' · ${m.status.label}${m.evidence.isEmpty ? '' : ' · ${m.evidence.length} أدلة'}'
                      '${m.deviation == null || m.deviation!.isEmpty ? '' : '\nالانحراف: ${m.deviation}${m.corrective == null || m.corrective!.isEmpty ? '' : ' · التصحيح: ${m.corrective}'}'}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.5),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            if (draft)
              ElevatedButton.icon(
                onPressed: () => daily.setPlanStatus(c, p, PlanStatus.pending, byName: name),
                icon: const Icon(Icons.send_rounded),
                label: const Text('رفع للاعتماد'),
              ),
            if (p.status == PlanStatus.pending && approver) ...[
              ElevatedButton.icon(
                onPressed: () => daily.setPlanStatus(c, p, PlanStatus.approved, byName: name),
                icon: const Icon(Icons.check_rounded),
                label: const Text('اعتماد الخطة'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => daily.setPlanStatus(c, p, PlanStatus.rejected, byName: name, reason: 'تحتاج مراجعة'),
                icon: const Icon(Icons.undo_rounded),
                label: const Text('رفض وإعادة'),
              ),
            ],
            if (p.status == PlanStatus.approved) ...[
              OutlinedButton.icon(
                onPressed: () {
                  final n = daily.clonePlan(c, p, by: cs.me?.id ?? '');
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PlanDetailScreen(planId: n.id)));
                },
                icon: const Icon(Icons.copy_rounded),
                label: Text('نسخها لسنة ${p.year + 1}'),
              ),
              TextButton(onPressed: () => daily.setPlanStatus(c, p, PlanStatus.archived, byName: name), child: const Text('أرشفة الخطة')),
            ],
            if (p.decidedBy != null)
              Text('آخر قرار: ${p.decidedBy}${p.reason == null ? '' : ' · ${p.reason}'}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Future<void> _editTarget(BuildContext context, Company c, OpsPlan p, Milestone m) async {
    final title = TextEditingController(text: m.title);
    final target = TextEditingController(text: m.target?.toStringAsFixed(0) ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navySurface,
        title: Text(m.period),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'المستهدف (وصف)')),
          TextField(controller: target, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'القيمة المستهدفة (اختياري)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      final i = p.milestones.indexOf(m);
      p.milestones[i] = Milestone(id: m.id, title: title.text.trim().isEmpty ? m.title : title.text.trim(), period: m.period, target: double.tryParse(target.text));
      context.read<DailyOpsState>().savePlan(c, p);
    }
    title.dispose();
    target.dispose();
  }

  Future<void> _progress(BuildContext context, Company c, OpsPlan p, Milestone m) async {
    final actual = TextEditingController(text: m.actual?.toStringAsFixed(0) ?? '');
    final evidence = TextEditingController();
    final deviation = TextEditingController(text: m.deviation ?? '');
    final corrective = TextEditingController(text: m.corrective ?? '');
    var status = m.status;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: AppColors.navySurface,
          title: Text('${m.period}: ${m.title}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final s in MilestoneStatus.values)
                  ChoiceChip(label: Text(s.label), selected: status == s, onSelected: (_) => set(() => status = s)),
              ]),
              TextField(controller: actual, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الفعلي')),
              TextField(controller: evidence, decoration: const InputDecoration(labelText: 'إضافة دليل (مستند أو مرجع)')),
              if (status == MilestoneStatus.delayed || status == MilestoneStatus.blocked || status == MilestoneStatus.atRisk) ...[
                TextField(controller: deviation, decoration: const InputDecoration(labelText: 'سبب الانحراف (إلزامي)')),
                TextField(controller: corrective, decoration: const InputDecoration(labelText: 'الإجراء التصحيحي')),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    final deviating = status == MilestoneStatus.delayed || status == MilestoneStatus.blocked || status == MilestoneStatus.atRisk;
    if (ok == true && context.mounted) {
      if (deviating && deviation.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب سبب الانحراف.')));
      } else if (status == MilestoneStatus.completed && m.evidence.isEmpty && evidence.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أرفق دليلاً قبل اعتبار المرحلة مكتملة.')));
      } else {
        context.read<DailyOpsState>().updateMilestone(c, p, m,
            actual: double.tryParse(actual.text),
            status: status,
            evidence: evidence.text,
            deviation: deviating ? deviation.text : null,
            corrective: deviating ? corrective.text : null);
      }
    }
    for (final x in [actual, evidence, deviation, corrective]) {
      x.dispose();
    }
  }
}
