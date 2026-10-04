import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/professional.dart';
import '../../models/questionnaire.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../providers/professional_state.dart';
import '../../theme/app_theme.dart';
import 'pro_common.dart';

/// R04: المراجعة القانونية. نص المسودة أو الإصدار مع تنقّل بين البنود، وتعليقات بالفئة والشدّة،
/// ووسم البند كمراجَع، وطلب تعديل يُحال للشركاء، ثم إكمال المراجعة. لا يُعدَّل أي نص من هنا.
class LegalReviewScreen extends StatefulWidget {
  const LegalReviewScreen({super.key});

  @override
  State<LegalReviewScreen> createState() => _LegalReviewScreenState();
}

class _LegalReviewScreenState extends State<LegalReviewScreen> {
  String? _sessionId;
  String? _focus;

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final st = context.watch<ContractState>();
    final pro = context.watch<ProfessionalState>();
    final c = cs.current;
    final e = myEngagement(context);
    if (c == null || e == null || !pro.inScope(e, EngagementScope.contract)) {
      return const Scaffold(body: StateView.denied(message: 'مسودات العقد خارج نطاق تكليفك أو التكليف غير سارٍ.'));
    }
    final sessions = reviewableSessions(st, c.id);
    if (sessions.isEmpty) {
      return const Scaffold(body: StateView.empty(title: 'لا توجد مسودة للمراجعة', message: 'تظهر هنا مسودة العقد عند بدء جلسة التأسيس.'));
    }
    final s = sessions.firstWhere((x) => x.id == _sessionId, orElse: () => sessions.first);
    final r = pro.review(e, s.id);
    final clauses = s.records.where((x) => x.status != ClauseStatus.notApplicable).toList();
    final keys = clauses.map((x) => x.key).toList();
    final comments = pro.commentsFor(c.id, engagementId: e.id).where((x) => x.sessionId == s.id).toList();
    final wide = context.screenSize == ScreenSize.desktop;

    Widget nav() => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final x in clauses)
              ListTile(
                dense: true,
                selected: _focus == x.key,
                leading: Icon(r?.reviewedKeys.contains(x.key) ?? false ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    size: 18, color: r?.reviewedKeys.contains(x.key) ?? false ? AppColors.success : AppColors.textMuted),
                title: Text(st.question(x.questionId).title, style: const TextStyle(fontSize: 12.5)),
                trailing: openCommentsBadge(comments.where((k) => k.targetId == x.key && k.status.isOpen).length),
                onTap: () => setState(() => _focus = x.key),
              ),
          ],
        );

    final body = ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      children: [
        DropdownButtonFormField<String>(
          initialValue: s.id,
          isExpanded: true,
          dropdownColor: AppColors.navySurface,
          decoration: const InputDecoration(labelText: 'المستند قيد المراجعة'),
          items: [for (final x in sessions) DropdownMenuItem(value: x.id, child: Text(sessionLabel(x)))],
          onChanged: (v) => setState(() {
            _sessionId = v;
            _focus = null;
          }),
        ),
        const SizedBox(height: 10),
        StateBanner(
          color: r?.status == ReviewStatus.completed ? AppColors.success : AppColors.info,
          icon: Icons.gavel_rounded,
          text: r == null
              ? 'لم تبدأ المراجعة بعد. ابدأها لتسجيل البنود التي راجعتها.'
              : '${r.status.label} · ${r.reviewedKeys.length} من ${keys.length} بنود مراجعة · ${comments.where((k) => k.status.isOpen).length} تعليقات مفتوحة'
                  '${r.summary == null ? '' : '\n${r.summary}'}',
        ),
        if (r == null)
          ElevatedButton.icon(
            onPressed: () => pro.startReview(c, e, s),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('بدء المراجعة القانونية'),
          ),
        for (final x in clauses.where((x) => _focus == null || x.key == _focus))
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: GovCard(
              title: st.question(x.questionId).title,
              icon: Icons.article_rounded,
              trailing: Text(x.status.label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(x.status == ClauseStatus.agreed ? st.renderClause(s, x) : (x.clauseText ?? st.question(x.questionId).clauseTemplate),
                    style: const TextStyle(height: 1.8)),
                for (final k in comments.where((k) => k.targetId == x.key))
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: k.severity.color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: k.severity.color.withValues(alpha: 0.4)),
                    ),
                    child: Text('${k.kind.label} · ${k.category} · ${k.severity.label} · ${k.status.label}\n${k.text}'
                        '${k.replies.isEmpty ? '' : '\nآخر رد: ${k.replies.last.authorName}: ${k.replies.last.text}'}',
                        style: const TextStyle(fontSize: 12.5, height: 1.5)),
                  ),
                Wrap(spacing: 4, children: [
                  TextButton.icon(
                    onPressed: () => showProCommentSheet(context,
                        c: c, e: e, targetType: 'clause', targetId: x.key, targetLabel: st.question(x.questionId).title, session: s),
                    icon: const Icon(Icons.add_comment_rounded, size: 18),
                    label: const Text('تعليق'),
                  ),
                  TextButton.icon(
                    onPressed: () => showProCommentSheet(context,
                        c: c,
                        e: e,
                        targetType: 'clause',
                        targetId: x.key,
                        targetLabel: st.question(x.questionId).title,
                        session: s,
                        initialKind: CommentKind.changeRequest),
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: const Text('طلب تعديل'),
                  ),
                  if (r != null && r.status != ReviewStatus.completed)
                    TextButton.icon(
                      onPressed: () => pro.toggleReviewed(c, r, x.key),
                      icon: Icon(r.reviewedKeys.contains(x.key) ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 18),
                      label: const Text('تمت مراجعته'),
                    ),
                ]),
              ]),
            ),
          ),
        if (r != null && r.status != ReviewStatus.completed) ...[
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: () async {
              final summary = await _summary(context);
              if (summary == null || !context.mounted) return;
              final err = pro.completeReview(c, r, keys, summary: summary, byName: cs.me?.name ?? e.name);
              if (err != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('لا يمكن الإكمال بعد: $err')));
            },
            icon: const Icon(Icons.task_alt_rounded),
            label: const Text('إكمال المراجعة'),
          ),
        ],
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('المراجعة القانونية')),
      body: wide
          ? Row(children: [
              SizedBox(width: 260, child: nav()),
              const VerticalDivider(width: 1),
              Expanded(child: ContentWidth(child: body)),
            ])
          : ContentWidth(child: body),
    );
  }

  Future<String?> _summary(BuildContext context) async {
    final t = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navySurface,
        title: const Text('خلاصة المراجعة'),
        content: TextField(controller: t, maxLines: 4, decoration: const InputDecoration(labelText: 'رأيك القانوني باختصار')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إكمال')),
        ],
      ),
    );
    final v = t.text.trim();
    t.dispose();
    return ok == true && v.isNotEmpty ? v : null;
  }
}
