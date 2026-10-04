import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/gov_status.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/company.dart';
import '../../models/family.dart';
import '../../models/questionnaire.dart';
import '../../providers/company_state.dart';
import '../../providers/family_state.dart';
import '../../services/identity_service.dart';
import '../../theme/app_theme.dart';

final _dt = DateFormat('yyyy/MM/dd HH:mm');

/// اسم صاحب المعرّف: عضو في الشركة أو فرد في شجرة العائلة
String familyName(Company c, FamilyState f, String id) =>
    c.members.where((m) => m.id == id).firstOrNull?.name ?? f.person(id)?.name ?? id;

/// R14: القرارات العائلية. تصويت مرجّح بالأوزان مع العتبة والنصاب والمهلة والخط الزمني.
class FamilyDecisionsScreen extends StatelessWidget {
  const FamilyDecisionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final f = context.watch<FamilyState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) context.read<FamilyState>().expireOverdue(c);
    });
    final list = f.decisionsFor(c.id);
    return Scaffold(
      appBar: AppBar(title: const Text('القرارات العائلية')),
      floatingActionButton: cs.me?.isPartner ?? false
          ? FloatingActionButton.extended(
              onPressed: () => _new(context, c),
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.navyDark,
              icon: const Icon(Icons.add_rounded),
              label: const Text('قرار عائلي'),
            )
          : null,
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
          children: [
            StateBanner.readOnly('عدم التصويت ليس موافقة. القرار يُعتمد ببلوغ العتبة المرجّحة بالأوزان، وينتهي دون اعتماد إن انقضت المهلة.'),
            if (list.isEmpty)
              const StateView.empty(icon: Icons.how_to_vote_outlined, title: 'لا توجد قرارات عائلية', message: ''),
            for (final d in list)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FamilyDecisionScreen(decisionId: d.id))),
                  title: Text(d.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                    '${d.type.label} · موافقة ${d.share(true).toStringAsFixed(1)}% من ${d.threshold.toStringAsFixed(2)}% · '
                    'المهلة ${_dt.format(d.deadline.toLocal())}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  trailing: Text(d.status.label,
                      style: TextStyle(
                          color: d.status == FamilyDecisionStatus.approved
                              ? AppColors.success
                              : d.status == FamilyDecisionStatus.open
                                  ? AppColors.info
                                  : AppColors.textMuted,
                          fontSize: 12)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _new(BuildContext context, Company c) async {
    final f = context.read<FamilyState>();
    final me = context.read<CompanyState>().me!;
    final title = TextEditingController();
    final details = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navySurface,
        title: const Text('قرار عائلي جديد'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'موضوع القرار')),
          TextField(controller: details, maxLines: 3, decoration: const InputDecoration(labelText: 'التفاصيل')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('فتح للتصويت')),
        ],
      ),
    );
    if (ok == true && title.text.trim().isNotEmpty) {
      f.openDecision(c, type: FamilyDecisionType.other, title: title.text.trim(), details: details.text, by: me.id);
    }
    title.dispose();
    details.dispose();
  }
}

class FamilyDecisionScreen extends StatelessWidget {
  final String decisionId;
  const FamilyDecisionScreen({super.key, required this.decisionId});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final f = context.watch<FamilyState>();
    final c = cs.current;
    final d = f.decision(decisionId);
    final me = cs.me;
    if (c == null || d == null || me == null) return const Scaffold(body: StateView.empty(title: 'القرار غير متاح', message: ''));
    final myWeight = d.weights[me.id] ?? 0;
    final voted = d.votes.containsKey(me.id);
    final events = cs.audit.where((e) => e.objectId == d.id).toList();

    return Scaffold(
      appBar: AppBar(title: Text(d.type.label)),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            Text(d.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w900)),
            if (d.details.isNotEmpty) Text(d.details, style: const TextStyle(color: AppColors.textSecondary, height: 1.7)),
            const SizedBox(height: 12),
            ApprovalPanel(
              threshold: d.threshold,
              quorum: d.quorum,
              agree: d.share(true),
              disagree: d.share(false),
              neutral: 0,
              voters: [
                for (final e in d.weights.entries)
                  VoterLine(
                    name: familyName(c, f, e.key),
                    weight: d.totalWeight == 0 ? 0 : e.value / d.totalWeight * 100,
                    vote: d.votes[e.key] == null ? null : (d.votes[e.key]!.approve ? 'موافق' : 'غير موافق'),
                    voteColor: d.votes[e.key] == null ? null : (d.votes[e.key]!.approve ? AppColors.success : AppColors.danger),
                  ),
              ],
              deadline: d.deadline,
              decision: switch (d.status) {
                FamilyDecisionStatus.approved => GovStatus.approved,
                FamilyDecisionStatus.open => null,
                _ => GovStatus.rejected,
              },
            ),
            const SizedBox(height: 12),
            if (d.status == FamilyDecisionStatus.open && myWeight > 0 && !voted) ...[
              ElevatedButton.icon(
                onPressed: () => _vote(context, c, d, true),
                icon: const Icon(Icons.check_rounded),
                label: const Text('موافق'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _vote(context, c, d, false),
                icon: const Icon(Icons.close_rounded),
                label: const Text('غير موافق'),
              ),
            ] else if (d.status == FamilyDecisionStatus.open)
              Text(voted ? 'سُجّل صوتك.' : 'ليس لك وزن تصويت في هذا القرار حسب الدستور العائلي.',
                  style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 12),
            GovCard(title: 'الخط الزمني', icon: Icons.timeline_rounded, child: AuditTimeline(events: events)),
          ],
        ),
      ),
    );
  }

  Future<void> _vote(BuildContext context, Company c, FamilyDecision d, bool approve) async {
    final me = context.read<CompanyState>().me!;
    final m = await IdentityService.confirm(context, partnerName: me.name, action: '${approve ? 'الموافقة على' : 'رفض'}: ${d.title}');
    if (m == null || !context.mounted) return;
    final err = context.read<FamilyState>().vote(c, d, me.id, approve: approve, method: m.label, name: me.name);
    if (err != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }
}
