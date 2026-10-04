import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/company.dart';
import '../../models/professional.dart';
import '../../models/questionnaire.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../providers/professional_state.dart';
import '../../theme/app_theme.dart';
import '../establishment/decision_details_screen.dart';
import '../versions/amendment_screens.dart';

final _dt = DateFormat('yyyy/MM/dd HH:mm');

/// R06: مركز التعليقات المهنية. محادثات مرتبطة بالبند أو القاعدة أو المستند بين الطرف المهني والشركاء.
/// التعليق لا يغيّر العقد أو القاعدة حتى يُعتمد إصدار جديد. يظهر للطرف المهني (تعليقاته)، ولكل الشركاء.
class ProCommentsScreen extends StatefulWidget {
  const ProCommentsScreen({super.key});

  @override
  State<ProCommentsScreen> createState() => _ProCommentsScreenState();
}

class _ProCommentsScreenState extends State<ProCommentsScreen> {
  CommentStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final pro = context.watch<ProfessionalState>();
    final c = cs.current;
    final me = cs.me;
    if (c == null || me == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final mine = pro.engagementOf(c.id, me.id);
    final all = pro.commentsFor(c.id, engagementId: me.isPartner ? null : mine?.id);
    final list = all.where((x) => _filter == null || x.status == _filter).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('التعليقات المهنية')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            StateBanner.readOnly('التعليقات أدلة محفوظة. لا تغيّر نص العقد أو القواعد حتى يُعتمد إصدار جديد يقرّه الشركاء.'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(label: Text('الكل (${all.length})'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
              for (final s in CommentStatus.values)
                ChoiceChip(
                  label: Text('${s.label} (${all.where((x) => x.status == s).length})'),
                  selected: _filter == s,
                  onSelected: (_) => setState(() => _filter = s),
                ),
            ]),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const StateView.empty(icon: Icons.forum_outlined, title: 'لا توجد تعليقات هنا', message: ''),
            for (final x in list) _Thread(c: c, x: x, me: me),
          ],
        ),
      ),
    );
  }
}

class _Thread extends StatelessWidget {
  final Company c;
  final ProComment x;
  final CompanyMember me;
  const _Thread({required this.c, required this.x, required this.me});

  @override
  Widget build(BuildContext context) {
    final pro = context.read<ProfessionalState>();
    final st = context.read<ContractState>();
    final overdue = x.status.isOpen && x.dueDate != null && x.dueDate!.isBefore(DateTime.now());
    final session = x.sessionId == null ? null : st.sessions.where((s) => s.id == x.sessionId).firstOrNull;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: Icon(x.kind == CommentKind.changeRequest ? Icons.edit_note_rounded : Icons.chat_bubble_outline_rounded,
            color: x.severity.color),
        title: Text('${x.kind.label}: ${x.targetLabel}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
        subtitle: Text(
          '${x.authorName} (${x.authorRole.label}) · ${x.category} · ${x.severity.label} · ${x.status.label}'
          '${x.version == null ? '' : ' · الإصدار ${x.version}'}'
          '${x.dueDate == null ? '' : ' · الاستحقاق ${_dt.format(x.dueDate!.toLocal())}${overdue ? ' (متأخر)' : ''}'}',
          style: TextStyle(color: overdue ? AppColors.danger : AppColors.textMuted, fontSize: 11.5),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(x.text, style: const TextStyle(height: 1.7)),
          for (final r in x.replies)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (r.professional ? AppColors.info : AppColors.gold).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('${r.authorName} · ${_dt.format(r.at.toLocal())}\n${r.text}', style: const TextStyle(fontSize: 12.5, height: 1.5)),
            ),
          Wrap(spacing: 4, children: [
            TextButton.icon(onPressed: () => _reply(context), icon: const Icon(Icons.reply_rounded, size: 18), label: const Text('رد')),
            if (x.status.isOpen)
              TextButton.icon(
                onPressed: () => pro.setCommentStatus(c, x, CommentStatus.resolved, byName: me.name),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('حل'),
              )
            else
              TextButton.icon(
                onPressed: () => pro.setCommentStatus(c, x, CommentStatus.reopened, byName: me.name),
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: const Text('إعادة فتح'),
              ),
            if (session != null && x.targetType == 'clause' && session.records.any((r) => r.key == x.targetId))
              TextButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => DecisionDetailsScreen(sessionId: session.id, recordKey: x.targetId))),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('فتح البند'),
              ),
            // طلب التعديل على عقد معتمد: يفتح الشركاء مقترح إصدار جديد بنفس رحلة التعديل
            if (me.isPartner && x.kind == CommentKind.changeRequest && x.amendmentRef == null && session?.status == SessionStatus.completed)
              TextButton.icon(
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const AmendmentProposalScreen()));
                  final a = st.activeAmendment(c.id);
                  if (a != null) pro.linkAmendment(c, x, a.id);
                },
                icon: const Icon(Icons.history_edu_rounded, size: 18),
                label: const Text('فتح مقترح تعديل'),
              ),
            if (x.amendmentRef != null)
              TextButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AmendmentDetailScreen(sessionId: x.amendmentRef!))),
                icon: const Icon(Icons.layers_rounded, size: 18),
                label: const Text('المقترح المرتبط'),
              ),
          ]),
        ],
      ),
    );
  }

  Future<void> _reply(BuildContext context) async {
    final t = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navySurface,
        title: const Text('رد'),
        content: TextField(controller: t, maxLines: 4, decoration: const InputDecoration(labelText: 'نص الرد')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إرسال')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      context.read<ProfessionalState>().reply(c, x, authorId: me.id, authorName: me.name, professional: !me.isPartner, text: t.text);
    }
    t.dispose();
  }
}
