import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/questionnaire.dart';
import '../../providers/contract_state.dart';
import '../../theme/app_theme.dart';
import '../company/audit_log_screen.dart';
import 'contract_preview_screen.dart';

/// P13: العقد النهائي. تمثيل غير قابل للتعديل مع حالة التواقيع والأدلة ومرجع السلامة.
/// أي تعديل لاحق يتم بإصدار جديد (المرحلة 3)، ولا تظهر هنا أي أداة تعديل.
class FinalContractScreen extends StatelessWidget {
  final String sessionId;
  const FinalContractScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<ContractState>();
    final s = st.sessions.where((x) => x.id == sessionId).firstOrNull;
    if (s == null) return const Scaffold(body: StateView.empty(title: 'المستند غير متاح', message: ''));
    final finalized = s.status == SessionStatus.completed;
    final intact = finalized && st.verifyHash(s);
    final fmt = DateFormat('yyyy/MM/dd HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('العقد النهائي')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            if (!finalized)
              StateBanner(
                color: AppColors.warning,
                icon: Icons.hourglass_top_rounded,
                text: 'بانتظار التواقيع: ${st.finalizeBlockers(s).join('، ')}',
              )
            else
              StateBanner(
                color: intact ? AppColors.success : AppColors.danger,
                icon: intact ? Icons.verified_rounded : Icons.gpp_bad_rounded,
                text: intact
                    ? 'عقد نهائي معتمد · الإصدار 1 · مقفل للقراءة فقط · المحتوى مطابق لمرجع السلامة'
                    : 'تحذير: محتوى العقد الحالي لا يطابق مرجع السلامة المسجل عند الاعتماد',
              ),
            Text('عقد تأسيس ${s.companyName}',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w900)),
            if (s.completedAt != null)
              Text('تاريخ النفاذ ${fmt.format(s.completedAt!.toLocal())}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            const SizedBox(height: 14),
            EvidencePanel(items: [
              for (final p in s.partners)
                EvidenceItem(
                  EvidenceKind.signature,
                  'توقيع ${p.name}',
                  s.signOffs[p.id] == null
                      ? 'لم يوقّع'
                      : '${fmt.format(s.signOffs[p.id]!.at.toLocal())} · ${s.signOffs[p.id]!.method.label}',
                  ok: s.signOffs[p.id] != null && st.signOffValid(s, s.signOffs[p.id]!) || finalized,
                ),
              for (final w in s.witnesses)
                EvidenceItem(
                  EvidenceKind.witness,
                  'الشاهد ${w.name}',
                  w.attestedAt == null ? 'لم يشهد' : '${fmt.format(w.attestedAt!.toLocal())} · ${w.method?.label ?? ''}',
                  ok: w.attested,
                ),
              if (s.contentHash != null)
                EvidenceItem(EvidenceKind.hash, 'مرجع سلامة المستند (SHA-256)', s.contentHash!, copyable: true),
              if (s.completedAt != null)
                EvidenceItem(EvidenceKind.timestamp, 'الطابع الزمني للاعتماد', s.completedAt!.toUtc().toIso8601String()),
            ]),
            const SizedBox(height: 12),
            const Text(
              'مرجع السلامة بصمة رياضية لمحتوى العقد تكشف أي تعديل لاحق، وتُحفظ في الخادم عند الاعتماد.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.6),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => ContractPreviewScreen(sessionId: s.id))),
              icon: const Icon(Icons.picture_as_pdf_rounded),
              label: const Text('عرض العقد وطباعته وتنزيله'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditLogScreen())),
              icon: const Icon(Icons.manage_search_rounded),
              label: const Text('سجل التدقيق والأدلة'),
            ),
          ],
        ),
      ),
    );
  }
}
