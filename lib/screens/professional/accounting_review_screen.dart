import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/operations.dart';
import '../../models/professional.dart';
import '../../models/questionnaire.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../providers/operations_state.dart';
import '../../providers/professional_state.dart';
import '../../services/rule_engine.dart';
import '../../theme/app_theme.dart';
import 'pro_common.dart';

/// R05: المراجعة المحاسبية. البنود المالية وقواعدها وحدودها وعملاتها، وربط فئات العمليات بدليل الحسابات،
/// وقائمة تحقق، وتعليقات مرتبطة بالبند أو القاعدة. المراجع لا يغيّر شروط العقد.
class AccountingReviewScreen extends StatefulWidget {
  const AccountingReviewScreen({super.key});

  @override
  State<AccountingReviewScreen> createState() => _AccountingReviewScreenState();
}

class _AccountingReviewScreenState extends State<AccountingReviewScreen> {
  String? _sessionId;

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final st = context.watch<ContractState>();
    final pro = context.watch<ProfessionalState>();
    final ops = context.watch<OperationsState>();
    final c = cs.current;
    final e = myEngagement(context);
    if (c == null || e == null || !pro.inScope(e, EngagementScope.financialRules)) {
      return const Scaffold(body: StateView.denied(message: 'البنود المالية خارج نطاق تكليفك أو التكليف غير سارٍ.'));
    }
    final sessions = reviewableSessions(st, c.id);
    if (sessions.isEmpty) {
      return const Scaffold(body: StateView.empty(title: 'لا يوجد عقد للمراجعة', message: ''));
    }
    final s = sessions.firstWhere((x) => x.id == _sessionId, orElse: () => sessions.first);
    final r = pro.review(e, s.id);
    final financial = s.records.where((x) => st.question(x.questionId).effect == EffectType.financial && x.status != ClauseStatus.notApplicable).toList();
    final keys = financial.map((x) => x.key).toList();
    final List<ActiveRule> rules = s.status == SessionStatus.completed && !s.archived ? ops.activeRules(st, c.id) : const [];
    final comments = pro.commentsFor(c.id, engagementId: e.id).where((x) => x.sessionId == s.id).toList();
    final locked = r == null || r.status == ReviewStatus.completed;

    return Scaffold(
      appBar: AppBar(title: const Text('المراجعة المحاسبية')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            DropdownButtonFormField<String>(
              initialValue: s.id,
              isExpanded: true,
              dropdownColor: AppColors.navySurface,
              decoration: const InputDecoration(labelText: 'المستند قيد المراجعة'),
              items: [for (final x in sessions) DropdownMenuItem(value: x.id, child: Text(sessionLabel(x)))],
              onChanged: (v) => setState(() => _sessionId = v),
            ),
            const SizedBox(height: 10),
            StateBanner(
              color: r?.status == ReviewStatus.completed ? AppColors.success : AppColors.info,
              icon: Icons.calculate_rounded,
              text: r == null
                  ? 'عملة العقد: ${s.currency.label}. ابدأ المراجعة لتسجيل نتائجك.'
                  : '${r.status.label} · ${r.reviewedKeys.length} من ${keys.length} بنود مالية · عملة العقد ${s.currency.label}'
                      '${r.summary == null ? '' : '\n${r.summary}'}',
            ),
            if (r == null)
              ElevatedButton.icon(
                onPressed: () => pro.startReview(c, e, s),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('بدء المراجعة المحاسبية'),
              ),
            const SizedBox(height: 10),
            GovCard(
              title: 'البنود المالية وحدودها',
              icon: Icons.account_balance_rounded,
              child: Column(children: [
                for (final x in financial)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: IconButton(
                      onPressed: locked ? null : () => pro.toggleReviewed(c, r, x.key),
                      icon: Icon(r?.reviewedKeys.contains(x.key) ?? false ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                          color: r?.reviewedKeys.contains(x.key) ?? false ? AppColors.success : AppColors.textMuted),
                    ),
                    title: Text(st.question(x.questionId).title),
                    subtitle: Text(
                        'القيمة ${x.value == null ? '—' : st.formatValue(s, st.question(x.questionId), x.value)}'
                        '${st.question(x.questionId).paramKind == ParamKind.percent ? '%' : ''} · ${x.status.label}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      openCommentsBadge(comments.where((k) => k.targetId == x.key && k.status.isOpen).length),
                      IconButton(
                        tooltip: 'تعليق',
                        icon: const Icon(Icons.add_comment_rounded, size: 18),
                        onPressed: () => showProCommentSheet(context,
                            c: c, e: e, targetType: 'clause', targetId: x.key, targetLabel: st.question(x.questionId).title, session: s),
                      ),
                    ]),
                  ),
                if (financial.isEmpty) const Text('لا توجد بنود مالية في هذا المستند.', style: TextStyle(color: AppColors.textMuted)),
              ]),
            ),
            if (rules.isNotEmpty) ...[
              const SizedBox(height: 10),
              GovCard(
                title: 'القواعد الرقابية السارية',
                icon: Icons.rule_rounded,
                child: Column(children: [
                  for (final a in rules)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(a.rule.name),
                      subtitle: Text('${a.rule.describe(value: (_) => a.valueLabel)} · ${a.rule.id} ج${a.rule.version}',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                      trailing: IconButton(
                        tooltip: 'تعليق على القاعدة',
                        icon: const Icon(Icons.add_comment_rounded, size: 18),
                        onPressed: () => showProCommentSheet(context,
                            c: c, e: e, targetType: 'rule', targetId: a.rule.id, targetLabel: a.rule.name, session: s),
                      ),
                    ),
                ]),
              ),
            ],
            const SizedBox(height: 10),
            GovCard(
              title: 'الربط بدليل الحسابات',
              icon: Icons.account_tree_rounded,
              child: Column(children: [
                for (final cat in TxCategory.values)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(cat.icon, size: 18, color: AppColors.gold),
                    title: Text(cat.label),
                    trailing: TextButton(
                      onPressed: locked ? null : () => _map(context, r, cat.label),
                      child: Text(r?.accountMapping[cat.label] ?? 'تحديد الحساب'),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            GovCard(
              title: 'قائمة التحقق',
              icon: Icons.checklist_rounded,
              child: Column(children: [
                for (final item in kAccountingChecklist)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppColors.gold,
                    value: r?.checklist[item] ?? false,
                    onChanged: locked ? null : (v) => pro.setChecklist(c, r, item, v ?? false),
                    title: Text(item, style: const TextStyle(fontSize: 12.5)),
                  ),
              ]),
            ),
            if (!locked) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => showProCommentSheet(context,
                    c: c, e: e, targetType: 'document', targetId: s.id, targetLabel: sessionLabel(s), session: s, initialKind: CommentKind.clarification),
                icon: const Icon(Icons.help_outline_rounded),
                label: const Text('طلب إيضاح من الشركة'),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () {
                  final err = pro.completeReview(c, r, keys,
                      summary: 'اعتماد المراجعة المحاسبية · ${r.accountMapping.length} فئات مربوطة بالحسابات', byName: cs.me?.name ?? e.name);
                  if (err != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('لا يمكن الاعتماد بعد: $err')));
                },
                icon: const Icon(Icons.verified_rounded),
                label: const Text('اعتماد المراجعة'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _map(BuildContext context, ProReview r, String category) async {
    final c = context.read<CompanyState>().current!;
    final t = TextEditingController(text: r.accountMapping[category] ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navySurface,
        title: Text('حساب "$category"'),
        content: TextField(controller: t, decoration: const InputDecoration(labelText: 'رمز الحساب واسمه (مثل 5101 مصروفات إدارية)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true && t.text.trim().isNotEmpty && context.mounted) {
      context.read<ProfessionalState>().setMapping(c, r, category, t.text);
    }
    t.dispose();
  }
}
