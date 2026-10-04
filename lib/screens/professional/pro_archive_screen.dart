import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/dispute.dart';
import '../../models/ops_extra.dart';
import '../../models/professional.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../providers/daily_ops_state.dart';
import '../../providers/dispute_state.dart';
import '../../providers/professional_state.dart';
import '../../theme/app_theme.dart';
import '../establishment/contract_preview_screen.dart';
import 'pro_common.dart';

final _d = DateFormat('yyyy/MM/dd');

/// R08: أرشيف المستندات للطرف المهني. قراءة فقط لما يسمح به نطاق التكليف ومدته،
/// مع مرجع السلامة لكل مستند. يُغلق الوصول عند انتهاء التكليف.
class ProArchiveScreen extends StatelessWidget {
  const ProArchiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final st = context.watch<ContractState>();
    final pro = context.watch<ProfessionalState>();
    final c = cs.current;
    final e = myEngagement(context);
    if (c == null || e == null || !e.activeAt(pro.now())) {
      return const Scaffold(body: StateView.denied(message: 'انتهى التكليف أو لم يبدأ، فأُغلق الوصول إلى الأرشيف.'));
    }
    final docs = <(String, String, String, IconData, VoidCallback?)>[];
    if (pro.inScope(e, EngagementScope.contract) || pro.inScope(e, EngagementScope.financialRules)) {
      for (final s in reviewableSessions(st, c.id)) {
        docs.add((
          'العقد',
          sessionLabel(s),
          s.contentHash == null ? 'مسودة: بلا مرجع سلامة بعد' : 'SHA-256 ${s.contentHash!.substring(0, 16)}… · ${_d.format(s.completedAt!)}',
          Icons.description_rounded,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => ContractPreviewScreen(sessionId: s.id))),
        ));
      }
    }
    for (final r in pro.reviewsFor(c.id).where((r) => r.engagementId == e.id)) {
      docs.add((
        'مراجعاتي',
        '${r.type == ProRole.lawyer ? 'مراجعة قانونية' : 'مراجعة محاسبية'} للإصدار ${r.version}',
        '${r.status.label}${r.summary == null ? '' : ' · ${r.summary}'}',
        Icons.rate_review_rounded,
        null,
      ));
    }
    if (pro.inScope(e, EngagementScope.correspondence)) {
      for (final l in context.watch<DailyOpsState>().lettersFor(c.id).where((l) => l.status != LetterStatus.draft)) {
        docs.add(('المراسلات', '${l.reference}: ${l.subject}', '${l.status.label} · ${_d.format(l.date)}', Icons.mail_rounded, null));
      }
    }
    if (pro.inScope(e, EngagementScope.disputes)) {
      for (final d in context.watch<DisputeState>().disputesFor(c.id)) {
        docs.add((
          'النزاعات',
          '${d.trigger.label}: ${d.issue}',
          '${d.stage.label} · ${d.status.label}${d.caseFileHash == null ? '' : ' · ملف القضية ${d.caseFileHash!.substring(0, 12)}…'}',
          Icons.gavel_rounded,
          null,
        ));
      }
    }
    final cats = docs.map((d) => d.$1).toSet();

    return Scaffold(
      appBar: AppBar(title: const Text('أرشيف المستندات')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            StateBanner.readOnly('للقراءة فقط · الوصول ينتهي في ${_d.format(e.end)} · النطاق: ${e.scope.map((s) => s.label).join('، ')}'),
            if (docs.isEmpty) const StateView.empty(icon: Icons.folder_off_rounded, title: 'لا توجد مستندات في نطاقك', message: ''),
            for (final cat in cats) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 6),
                child: Text(cat, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
              ),
              for (final d in docs.where((d) => d.$1 == cat))
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(d.$4, color: AppColors.gold),
                    title: Text(d.$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    subtitle: Text(d.$3, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                    trailing: d.$5 == null ? null : const Icon(Icons.chevron_left_rounded),
                    onTap: d.$5,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
