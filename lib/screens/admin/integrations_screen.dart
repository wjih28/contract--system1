import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/company.dart';
import '../../models/operations.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../providers/operations_state.dart';
import '../../theme/app_theme.dart';

/// A16 + A17: التكامل المحاسبي وسجل المزامنة. كل عملية مستوردة تمر ببوابة الفحص
/// مثل الإدخال اليدوي، ويُمنع تكرار نفس المرجع.
class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});

  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  final _csv = TextEditingController(
      text: 'التاريخ,المبلغ,الفئة,المستفيد,الغرض,المرجع\n2026-10-03,1200,purchase,مكتبة الأمل,قرطاسية,INV-101\n2026-10-04,2600,purchase,شركة الحاسوب,طابعة,INV-102');

  @override
  void dispose() {
    _csv.dispose();
    super.dispose();
  }

  void _import(BuildContext context) {
    final cs = context.read<CompanyState>();
    final st = context.read<ContractState>();
    final ops = context.read<OperationsState>();
    final c = cs.current!;
    final lines = _csv.text.trim().split('\n').skip(1).where((l) => l.trim().isNotEmpty).toList();
    var ok = 0, dup = 0, bad = 0;
    final existing = ops.txFor(c.id).map((t) => t.reference).where((r) => r.isNotEmpty).toSet();
    for (final l in lines) {
      final f = l.split(',').map((x) => x.trim()).toList();
      if (f.length < 6) {
        bad++;
        continue;
      }
      final date = DateTime.tryParse(f[0]);
      final amount = double.tryParse(f[1]);
      final cat = TxCategory.values.where((x) => x.name == f[2]).firstOrNull;
      if (date == null || amount == null || cat == null) {
        bad++;
        continue;
      }
      if (existing.contains(f[5])) {
        dup++; // منع تكرار نفس القيد المالي (Idempotency)
        continue;
      }
      existing.add(f[5]);
      ops.submit(
        st,
        c,
        FinancialTx(
          id: 'T${DateTime.now().microsecondsSinceEpoch}',
          companyId: c.id,
          date: date,
          amount: amount,
          currency: c.currency,
          category: cat,
          payee: f[3],
          purpose: f[4],
          reference: f[5],
          source: TxSource.import,
          createdBy: cs.me?.id ?? '',
          createdAt: DateTime.now(),
        ),
        actorName: cs.me?.name ?? '',
      );
      ok++;
    }
    cs.log(c.id,
        action: 'استيراد عمليات من ملف',
        objectType: 'integration',
        objectId: 'csv',
        result: '$ok مستوردة، $dup مكررة مُنعت، $bad غير صالحة',
        actorType: ActorType.integration);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('استُوردت $ok عمليات ومرّت بالفحص. مُنع $dup مكرر، و$bad سطر غير صالح.')));
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    if (cs.current == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final log = cs.audit.where((e) => e.objectType == 'integration').toList();

    return Scaffold(
      appBar: AppBar(title: const Text('التكامل المحاسبي')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            for (final p in const ['Xero', 'QuickBooks'])
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const Icon(Icons.cloud_off_rounded, color: AppColors.textMuted),
                  title: Text(p, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('غير مربوط · يحتاج تسجيل تطبيق لدى المزوّد ومفاتيح ربط من حساب الشركة',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  trailing: const Text('غير مهيأ', style: TextStyle(color: AppColors.textMuted)),
                ),
              ),
            const SizedBox(height: 10),
            GovCard(
              title: 'استيراد عمليات من ملف (المسار الداخلي)',
              icon: Icons.upload_file_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text(
                  'الصق أسطر CSV: التاريخ، المبلغ، الفئة (purchase / expense / hospitality / contract / personalAdvance / salaryChange / revenue)، المستفيد، الغرض، المرجع.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.6),
                ),
                const SizedBox(height: 8),
                TextField(controller: _csv, maxLines: 6, textDirection: TextDirection.ltr,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () => _import(context),
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('استيراد وتمرير بالفحص'),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            GovCard(title: 'سجل المزامنة', icon: Icons.history_rounded, child: AuditTimeline(events: log)),
          ],
        ),
      ),
    );
  }
}
