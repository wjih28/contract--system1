import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/questionnaire.dart';
import '../../providers/contract_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../contract/finalize_screen.dart';
import 'contract_preview_screen.dart';
import 'deferred_screen.dart';
import 'voting_center_screen.dart';

/// P10: ملخص عقد التأسيس قبل التوقيع. يبرز البنود غير المحسومة والبنود الجوهرية
/// والقواعد التشغيلية وقائمة جاهزية التوقيع بموانعها الدقيقة.
class ContractSummaryScreen extends StatelessWidget {
  final String sessionId;
  const ContractSummaryScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<ContractState>();
    final s = st.sessions.where((x) => x.id == sessionId).firstOrNull;
    if (s == null) return const Scaffold(body: StateView.empty(title: 'الجلسة غير موجودة', message: ''));
    final blockers = st.signingBlockers(s);
    final ready = blockers.isEmpty;
    final rules = st.generatedRules(s);
    final validSigned = s.partners.where((p) => s.signOffs[p.id] != null && st.signOffValid(s, s.signOffs[p.id]!)).length;
    final validWitness = s.witnesses.where((w) => st.witnessValid(s, w)).length;

    return Scaffold(
      appBar: AppBar(title: const Text('ملخص العقد قبل التوقيع')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            StateBanner(
              color: AppColors.warning,
              icon: Icons.edit_note_rounded,
              text: 'مسودة: هذا ملخص قبل التوقيع وليس العقد النهائي. مرجع المسودة ${st.draftHash(s).substring(0, 16)}…',
            ),
            GovCard(
              title: 'بيانات الشركة والعقد',
              icon: Icons.business_rounded,
              child: Column(children: [
                _kv('الشركة', s.companyName),
                _kv('الشكل القانوني', s.companyType),
                _kv('رأس المال', formatCurrency(s.capital, s.currency)),
                _kv('الشركاء', s.partners.map((p) => '${p.name} ${p.equity.toStringAsFixed(p.equity % 1 == 0 ? 0 : 2)}%').join('، ')),
                _kv('الإصدار', 'المسودة قبل الإصدار 1'),
              ]),
            ),
            const SizedBox(height: 12),
            GovCard(
              title: 'الأقسام وعدد البنود',
              icon: Icons.list_alt_rounded,
              child: Column(children: [
                for (final c in ClauseCategory.values)
                  _kv('البنود ال${c.label}ة',
                      '${s.records.where((r) => st.question(r.questionId).category == c && r.status == ClauseStatus.agreed).length} معتمد '
                      'من ${s.records.where((r) => st.question(r.questionId).category == c).length}'),
                _kv('المؤجلة', '${s.count(ClauseStatus.deferred)}'),
                _kv('المحيّدة', '${s.count(ClauseStatus.neutralized)} (مستبعدة من العقد، وليست موافقة)'),
                _kv('القواعد التشغيلية', '${rules.length} قاعدة رقابية تُولَّد من البنود المالية'),
              ]),
            ),
            const SizedBox(height: 12),
            GovCard(
              title: 'جاهزية التوقيع',
              icon: Icons.checklist_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _check('كل البنود محسومة (معتمدة أو محيّدة)', ready),
                  _check('توقيع الشركاء على هذا الإصدار: $validSigned من ${s.partners.length}', validSigned == s.partners.length),
                  _check('الشهود على هذا الإصدار: $validWitness من $kMinWitnesses', validWitness >= kMinWitnesses),
                  if (!ready) ...[
                    const SizedBox(height: 10),
                    const Text('الموانع:', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800)),
                    ...blockers.map((b) => Text('• $b', style: const TextStyle(color: AppColors.textSecondary, height: 1.8))),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      OutlinedButton(
                        onPressed: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => VotingCenterScreen(sessionId: s.id))),
                        child: const Text('البنود المفتوحة'),
                      ),
                      if (s.count(ClauseStatus.deferred) > 0)
                        OutlinedButton(
                          onPressed: () => Navigator.push(
                              context, MaterialPageRoute(builder: (_) => DeferredScreen(sessionId: s.id))),
                          child: const Text('المؤجلة'),
                        ),
                    ]),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => ContractPreviewScreen(sessionId: s.id))),
              icon: const Icon(Icons.visibility_rounded),
              label: const Text('قراءة العقد كاملاً'),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: ready
                  ? () {
                      st.markAwaitingSignature(s);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => FinalizeScreen(sessionId: s.id)));
                    }
                  : null,
              icon: const Icon(Icons.draw_rounded),
              label: const Text('المتابعة إلى التوقيع'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: Text(k, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5))),
            Expanded(
              child: Text(v,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  Widget _check(String text, bool ok) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: ok ? AppColors.success : AppColors.textMuted, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
        ]),
      );
}
