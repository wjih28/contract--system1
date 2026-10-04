import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/company.dart';
import '../../models/professional.dart';
import '../../models/questionnaire.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../providers/professional_state.dart';
import '../../theme/app_theme.dart';

/// تكليف المستخدم الحالي (للطرف المهني)
Engagement? myEngagement(BuildContext context) {
  final cs = context.watch<CompanyState>();
  return context.watch<ProfessionalState>().engagementOf(cs.current?.id, cs.me?.id);
}

/// المستندات التي يمكن مراجعتها: المسودات الجارية أولاً ثم الإصدار الساري ثم المؤرشفة
List<ContractSession> reviewableSessions(ContractState st, String? cid) {
  final all = st.versionsFor(cid).where((s) => s.status != SessionStatus.withdrawn).toList();
  final drafts = all.where((s) => s.status != SessionStatus.completed).toList();
  final done = all.where((s) => s.status == SessionStatus.completed).toList().reversed.toList();
  return [...drafts, ...done];
}

String sessionLabel(ContractSession s) => s.status == SessionStatus.completed
    ? 'الإصدار ${s.version}${s.archived ? ' (مؤرشف)' : ' (الساري)'}'
    : 'مسودة الإصدار ${s.version} (${s.status.label})';

/// نافذة إضافة تعليق مهني على بند أو قاعدة
Future<void> showProCommentSheet(
  BuildContext context, {
  required Company c,
  required Engagement e,
  required String targetType,
  required String targetId,
  required String targetLabel,
  ContractSession? session,
  CommentKind initialKind = CommentKind.comment,
}) async {
  final pro = context.read<ProfessionalState>();
  final me = context.read<CompanyState>().me;
  final text = TextEditingController();
  final cats = e.role == ProRole.lawyer ? kLegalCategories : kAccountingCategories;
  var kind = initialKind;
  var cat = cats.first;
  var sev = Severity3.medium;
  var due = 7;
  String? error;
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
            Text('تعليق على: $targetLabel',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
            if (session != null)
              Text(sessionLabel(session), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, children: [
              for (final k in CommentKind.values)
                ChoiceChip(label: Text(k.label), selected: kind == k, onSelected: (_) => set(() => kind = k)),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final x in cats) ChoiceChip(label: Text(x), selected: cat == x, onSelected: (_) => set(() => cat = x)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const Text('الشدّة: ', style: TextStyle(color: AppColors.textMuted)),
              for (final s in Severity3.values)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 6),
                  child: ChoiceChip(label: Text(s.label), selected: sev == s, onSelected: (_) => set(() => sev = s)),
                ),
            ]),
            const SizedBox(height: 8),
            TextField(controller: text, maxLines: 4, decoration: const InputDecoration(labelText: 'نص التعليق', alignLabelWithHint: true)),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: due,
              dropdownColor: AppColors.navySurface,
              decoration: const InputDecoration(labelText: 'الرد مطلوب خلال'),
              items: const [
                DropdownMenuItem(value: 3, child: Text('3 أيام')),
                DropdownMenuItem(value: 7, child: Text('7 أيام')),
                DropdownMenuItem(value: 14, child: Text('14 يوماً')),
              ],
              onChanged: (v) => set(() => due = v!),
            ),
            if (kind == CommentKind.changeRequest)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('طلب التعديل يُحال للشركاء، ولا يغيّر النص. التغيير يتم بإصدار جديد يقرّونه.',
                    style: TextStyle(color: AppColors.warning, fontSize: 12)),
              ),
            if (error != null) Text(error!, style: const TextStyle(color: AppColors.danger)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                final err = pro.addComment(
                  c,
                  e,
                  ProComment(
                    id: 'PC${DateTime.now().microsecondsSinceEpoch}',
                    companyId: c.id,
                    engagementId: e.id,
                    authorId: me?.id ?? e.memberId,
                    authorName: me?.name ?? e.name,
                    authorRole: e.role,
                    targetType: targetType,
                    targetId: targetId,
                    targetLabel: targetLabel,
                    sessionId: session?.id,
                    version: session?.version,
                    kind: kind,
                    category: cat,
                    severity: sev,
                    text: text.text.trim(),
                    createdAt: DateTime.now(),
                    dueDate: DateTime.now().add(Duration(days: due)),
                  ),
                );
                if (err != null) return set(() => error = err);
                Navigator.pop(ctx);
              },
              child: const Text('إضافة'),
            ),
          ]),
        ),
      ),
    ),
  );
  text.dispose();
}

/// شارة صغيرة لعدد التعليقات المفتوحة على هدف
Widget openCommentsBadge(int n) => n == 0
    ? const SizedBox.shrink()
    : Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
        child: Text('$n', style: const TextStyle(color: AppColors.warning, fontSize: 11, fontWeight: FontWeight.w800)),
      );
