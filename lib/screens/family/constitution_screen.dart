import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/company.dart';
import '../../models/family.dart';
import '../../providers/company_state.dart';
import '../../providers/family_state.dart';
import '../../theme/app_theme.dart';
import 'family_decisions_screen.dart';

final _d = DateFormat('yyyy/MM/dd');

/// R10: الدستور العائلي. وثيقة منفصلة عن عقد التأسيس بإصدارات: الساري للقراءة، والتعديل مسودة
/// تُرفع لقرار عائلي بعتبة أعلى، ثم تصبح سارية ويُؤرشف السابق.
class ConstitutionScreen extends StatefulWidget {
  const ConstitutionScreen({super.key});

  @override
  State<ConstitutionScreen> createState() => _ConstitutionScreenState();
}

class _ConstitutionScreenState extends State<ConstitutionScreen> {
  String _q = '';
  String? _versionId;

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final f = context.watch<FamilyState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final all = f.constitutionsFor(c.id);
    final cur = f.current(c.id);
    final draft = f.pendingDraft(c.id);
    final shown = all.where((x) => x.id == _versionId).firstOrNull ?? cur ?? draft;
    final founder = cs.me?.isPartner ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('الدستور العائلي')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            if (all.isEmpty)
              StateView.empty(
                icon: Icons.menu_book_rounded,
                title: 'لا يوجد دستور عائلي بعد',
                message: 'ابدأ بمسودة تتضمن أقساماً أساسية، ثم عدّلها وارفعها لقرار عائلي.',
                actionLabel: founder ? 'بدء مسودة الدستور' : null,
                onAction: founder ? () => f.startDraft(c, by: cs.me!.id) : null,
              ),
            if (all.isNotEmpty) ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final x in all)
                  ChoiceChip(
                    label: Text('الإصدار ${x.version} · ${x.status.label}'),
                    selected: shown?.id == x.id,
                    onSelected: (_) => setState(() => _versionId = x.id),
                  ),
              ]),
              const SizedBox(height: 10),
              TextField(
                onChanged: (v) => setState(() => _q = v.trim()),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), labelText: 'بحث في الدستور', isDense: true),
              ),
            ],
            if (shown != null) ...[
              const SizedBox(height: 10),
              StateBanner(
                color: shown.status == ConstitutionStatus.current ? AppColors.success : AppColors.info,
                icon: Icons.menu_book_rounded,
                text: 'الإصدار ${shown.version} · ${shown.status.label}'
                    '${shown.effectiveAt == null ? '' : ' · ساري من ${_d.format(shown.effectiveAt!)}'}'
                    ' · الأوزان: ${shown.weightMode.label} · التوزيع: ${shown.distributionRule.label}'
                    ' · عتبة القرارات ${shown.threshold.toStringAsFixed(2)}% وتعديل الدستور ${shown.amendmentThreshold.toStringAsFixed(2)}%'
                    '${shown.changeSummary == null ? '' : '\nالتعديل: ${shown.changeSummary}'}',
              ),
              for (final (i, s) in shown.sections.indexed)
                if (_q.isEmpty || s.title.contains(_q) || s.text.contains(_q))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GovCard(
                      title: '${i + 1}. ${s.title}',
                      icon: Icons.article_outlined,
                      trailing: shown.status == ConstitutionStatus.draft && founder
                          ? IconButton(icon: const Icon(Icons.edit_rounded, size: 18), onPressed: () => _editSection(context, c, shown, i))
                          : null,
                      child: Text(s.text, style: const TextStyle(height: 1.8)),
                    ),
                  ),
              if (shown.decisionRef != null)
                TextButton.icon(
                  onPressed: () =>
                      Navigator.push(context, MaterialPageRoute(builder: (_) => FamilyDecisionScreen(decisionId: shown.decisionRef!))),
                  icon: const Icon(Icons.how_to_vote_outlined),
                  label: const Text('القرار العائلي المرتبط'),
                ),
            ],
            if (founder && all.isNotEmpty) ...[
              const SizedBox(height: 8),
              if (draft == null)
                OutlinedButton.icon(
                  onPressed: () => setState(() => _versionId = f.startDraft(c, by: cs.me!.id).id),
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('فتح مسودة تعديل'),
                )
              else if (draft.status == ConstitutionStatus.draft) ...[
                OutlinedButton.icon(
                  onPressed: () => _editSection(context, c, draft, null),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('إضافة قسم'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _editRules(context, c, draft),
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('الأوزان وقاعدة التوزيع'),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => _submit(context, c, draft),
                  icon: const Icon(Icons.send_rounded),
                  label: Text('رفع الإصدار ${draft.version} للقرار العائلي'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _editSection(BuildContext context, Company c, Constitution d, int? i) async {
    final title = TextEditingController(text: i == null ? '' : d.sections[i].title);
    final text = TextEditingController(text: i == null ? '' : d.sections[i].text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navySurface,
        title: Text(i == null ? 'قسم جديد' : 'تعديل القسم'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'العنوان')),
            TextField(controller: text, maxLines: 6, decoration: const InputDecoration(labelText: 'النص')),
          ]),
        ),
        actions: [
          if (i != null)
            TextButton(
              onPressed: () {
                d.sections = [...d.sections]..removeAt(i);
                Navigator.pop(ctx, true);
              },
              child: const Text('حذف القسم', style: TextStyle(color: AppColors.danger)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              if (title.text.trim().isEmpty) return;
              final s = ConstitutionSection(title.text.trim(), text.text.trim());
              d.sections = [...d.sections];
              i == null ? d.sections.add(s) : d.sections[i] = s;
              Navigator.pop(ctx, true);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) context.read<FamilyState>().saveDraft(c, d);
    title.dispose();
    text.dispose();
  }

  Future<void> _editRules(BuildContext context, Company c, Constitution d) async {
    final f = context.read<FamilyState>();
    var mode = d.weightMode;
    var rule = d.distributionRule;
    final weights = {for (final m in c.members.where((m) => m.active && (m.isPartner || m.roles.contains(CompanyRole.familyMember)))) m.id: TextEditingController(text: (d.customWeights[m.id] ?? m.equity).toStringAsFixed(0))};
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: AppColors.navySurface,
          title: const Text('الأوزان وقاعدة التوزيع'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('أوزان التصويت', style: TextStyle(color: AppColors.textMuted)),
              Wrap(spacing: 6, children: [
                for (final m in WeightMode.values) ChoiceChip(label: Text(m.label), selected: mode == m, onSelected: (_) => set(() => mode = m)),
              ]),
              if (mode == WeightMode.custom)
                for (final e in weights.entries)
                  TextField(
                    controller: e.value,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: 'وزن ${familyName(c, f, e.key)}'),
                  ),
              const Divider(),
              const Text('قاعدة توزيع الأرباح', style: TextStyle(color: AppColors.textMuted)),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final r in DistributionRule.values.where((r) => r != DistributionRule.custom))
                  ChoiceChip(label: Text(r.label), selected: rule == r, onSelected: (_) => set(() => rule = r)),
              ]),
            ]),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                d
                  ..weightMode = mode
                  ..distributionRule = rule
                  ..customWeights = mode == WeightMode.custom
                      ? {for (final e in weights.entries) e.key: double.tryParse(e.value.text) ?? 0}
                      : {};
                f.saveDraft(c, d);
                Navigator.pop(ctx);
              },
              child: const Text('حفظ في المسودة'),
            ),
          ],
        ),
      ),
    );
    for (final x in weights.values) {
      x.dispose();
    }
  }

  Future<void> _submit(BuildContext context, Company c, Constitution d) async {
    final t = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navySurface,
        title: const Text('ملخص التعديل'),
        content: TextField(controller: t, maxLines: 3, decoration: const InputDecoration(labelText: 'ما الذي تغيّر ولماذا')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('رفع للتصويت')),
        ],
      ),
    );
    if (ok == true && t.text.trim().isNotEmpty && context.mounted) {
      final dec = context.read<FamilyState>().submitConstitution(c, d, summary: t.text, by: context.read<CompanyState>().me!.id);
      if (dec != null) Navigator.push(context, MaterialPageRoute(builder: (_) => FamilyDecisionScreen(decisionId: dec.id)));
    }
    t.dispose();
  }
}
