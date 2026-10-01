import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../design/state_view.dart';
import '../../models/questionnaire.dart';
import '../../providers/contract_state.dart';
import '../../services/contract_pdf.dart';
import '../../theme/app_theme.dart';

/// P11: معاينة المستند داخل التطبيق مع شريط الإصدار.
/// المسودة لا تبدو أبداً كعقد نهائي، والعقد النهائي لا يحمل أدوات تعديل.
class ContractPreviewScreen extends StatelessWidget {
  final String sessionId;
  const ContractPreviewScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<ContractState>();
    final s = st.sessions.where((x) => x.id == sessionId).firstOrNull;
    if (s == null) return const Scaffold(body: StateView.empty(title: 'المستند غير متاح', message: ''));
    final finalDoc = s.status == SessionStatus.completed;
    final ref = finalDoc ? s.contentHash : st.draftHash(s);

    return Scaffold(
      appBar: AppBar(title: Text(finalDoc ? 'العقد النهائي' : 'معاينة المسودة')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: finalDoc
                ? StateBanner.readOnly('عقد نهائي معتمد للقراءة فقط · مرجع السلامة ${ref?.substring(0, 16) ?? '—'}…')
                : StateBanner(
                    color: AppColors.warning,
                    icon: Icons.edit_note_rounded,
                    text: 'مسودة غير نهائية · مرجع المسودة ${ref!.substring(0, 16)}… · '
                        'أي تعديل على البنود يغيّر هذا المرجع ويُبطل التواقيع.',
                  ),
          ),
          Expanded(
            child: PdfPreview(
              build: (format) => ContractPdf.build(st, s, interim: !finalDoc, format: format),
              initialPageFormat: PdfPageFormat.a4,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              // المسودة تُطبع للمراجعة فقط، والعقد النهائي يُنزَّل ويُطبع
              allowSharing: finalDoc,
              allowPrinting: true,
              pdfFileName: finalDoc ? 'عقد_تأسيس_${s.companyName}.pdf' : 'مسودة_${s.companyName}.pdf',
              scrollViewDecoration: const BoxDecoration(color: AppColors.navyDark),
              loadingWidget: const Center(child: CircularProgressIndicator()),
              onError: (context, error) => const StateView.error(
                message: 'تعذر توليد المستند. تأكد من الاتصال بالإنترنت لتحميل الخط العربي ثم أعد المحاولة.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
