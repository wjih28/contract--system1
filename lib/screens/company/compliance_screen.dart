import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../data/yemen_law.dart';
import '../../design/components.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/company.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../theme/app_theme.dart';

final _d = DateFormat('yyyy/MM/dd');

/// الامتثال القانوني (من دليل الاستخدام والامتثال والحسم وفق القانون اليمني):
/// شروط الشكل القانوني، ومستنداته، وخطوات الشهر الرسمي مع مراجعها، والدليل المختصر، والتنبيهات.
/// التوقيع في المنصة توثيق داخلي؛ الشخصية الاعتبارية تُكتسب بالمصادقة والقيد والنشر.
class ComplianceScreen extends StatelessWidget {
  const ComplianceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final st = context.watch<ContractState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final spec = formSpecOf(c.companyType);
    final steps = spec.legalPersonality ? kComplianceSteps : const <ComplianceStepSpec>[];
    final done = steps.where((x) => c.compliance[x.id]?['done'] == true).length;
    final signed = st.currentContract(c.id) != null;
    final canEdit = cs.me?.isPartner ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('الامتثال القانوني')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            StateBanner(
              color: done == steps.length && steps.isNotEmpty ? AppColors.success : AppColors.warning,
              icon: Icons.verified_user_rounded,
              text: !spec.legalPersonality
                  ? '${spec.label} لا تتمتع بالشخصية الاعتبارية ولا تُشهر بالسجل التجاري.'
                  : '${signed ? 'العقد موقّع داخلياً في المنصة.' : 'العقد لم يُعتمد بعد.'} '
                      'خطوات الشهر الرسمي: $done من ${steps.length}. لا تكتسب الشركة الشخصية الاعتبارية ولا تنفذ بنودها أمام الغير قبل اكتمالها.',
            ),
            GovCard(
              title: '${spec.label} · ${spec.category}',
              icon: Icons.account_balance_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(spec.definition, style: const TextStyle(height: 1.7)),
                Text('المسؤولية: ${spec.liability}', style: const TextStyle(height: 1.7)),
                Text('الترخيص: ${spec.licensing}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.6)),
                Text('عند وفاة شريك: ${spec.onDeath}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.6)),
                if (c.purpose.isNotEmpty) Text('الأغراض: ${c.purpose}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                if (spec.minCapitalYer != null)
                  Text(
                    c.yerRate == null
                        ? 'الحد الأدنى لرأس المال ${spec.minCapitalYer!.toStringAsFixed(0)} ريال يمني (أُقرّ باستيفائه عند التأسيس دون سعر صرف)'
                        : 'رأس المال يعادل ${(c.capital * c.yerRate!).toStringAsFixed(0)} ريالاً يمنياً بسعر ${c.yerRate} · الحد الأدنى ${spec.minCapitalYer!.toStringAsFixed(0)}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            GovCard(
              title: 'المستندات المطلوبة',
              icon: Icons.folder_copy_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final x in spec.documents) Text('• $x', style: const TextStyle(height: 1.7)),
                for (final m in c.partners.where((m) => m.minor))
                  Text('• حكم وصاية ${m.name}: ${m.guardianshipRef} (الولي: ${m.guardianName})',
                      style: const TextStyle(color: AppColors.warning, height: 1.7)),
              ]),
            ),
            if (steps.isNotEmpty) ...[
              const SizedBox(height: 12),
              GovCard(
                title: 'خطوات الشهر والاستيفاء القانوني',
                icon: Icons.checklist_rounded,
                child: Column(children: [
                  for (final (i, x) in steps.indexed)
                    _StepTile(c: c, step: x, n: i + 1, canEdit: canEdit),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            GovCard(
              title: 'حجية التوقيع وسيادة العقد',
              icon: Icons.gavel_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                Text(kSignatureNotice, style: TextStyle(height: 1.7)),
                SizedBox(height: 6),
                Text(kContractSupremacy, style: TextStyle(height: 1.7)),
              ]),
            ),
            const SizedBox(height: 12),
            GovCard(
              title: 'دليل الاستخدام المختصر',
              icon: Icons.menu_book_rounded,
              child: Column(children: [
                for (final (title, items) in kGuideSections)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    children: [for (final t in items) Text('• $t', style: const TextStyle(color: AppColors.textSecondary, height: 1.7))],
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            GovCard(
              title: 'تنبيهات قانونية',
              icon: Icons.warning_amber_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final w in kComplianceWarnings) Text('⚠ $w', style: const TextStyle(color: AppColors.textSecondary, height: 1.7)),
              ]),
            ),
            const SizedBox(height: 8),
            const Text('مصدر هذه المعلومات وثائق "ملف الاضافات" وقانون الشركات التجارية رقم (22) لسنة 1997م وتعديلاته. المرجع النهائي هو النص النافذ ولوائح الوزارة.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.6)),
          ],
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final Company c;
  final ComplianceStepSpec step;
  final int n;
  final bool canEdit;
  const _StepTile({required this.c, required this.step, required this.n, required this.canEdit});

  @override
  Widget build(BuildContext context) {
    final rec = c.compliance[step.id];
    final done = rec?['done'] == true;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 15,
        backgroundColor: done ? AppColors.success : AppColors.navyLight,
        child: done ? const Icon(Icons.check_rounded, size: 16, color: AppColors.navyDark) : Text('$n', style: const TextStyle(fontSize: 12)),
      ),
      title: Text(step.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
      subtitle: Text(
        '${step.action}\nالجهة: ${step.authority} · الأثر: ${step.effect}'
        '${done ? '\nالمرجع: ${rec?['ref'] ?? ''} · ${rec?['at'] == null ? '' : _d.format(DateTime.parse(rec!['at'] as String).toLocal())}' : ''}',
        style: TextStyle(color: done ? AppColors.success : AppColors.textMuted, fontSize: 11.5, height: 1.5),
      ),
      isThreeLine: true,
      trailing: canEdit
          ? TextButton(onPressed: () => _edit(context, done), child: Text(done ? 'إلغاء' : 'تم'))
          : null,
    );
  }

  Future<void> _edit(BuildContext context, bool done) async {
    final cs = context.read<CompanyState>();
    if (done) {
      cs.setCompliance(c.id, step.id, done: false);
      return;
    }
    final t = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navySurface,
        title: Text(step.title),
        content: TextField(controller: t, decoration: const InputDecoration(labelText: 'رقم المستند أو القرار أو الإيصال')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تسجيل')),
        ],
      ),
    );
    if (ok == true && t.text.trim().isNotEmpty) cs.setCompliance(c.id, step.id, done: true, ref: t.text.trim());
    t.dispose();
  }
}
