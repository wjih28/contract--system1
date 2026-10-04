import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../providers/operations_state.dart';
import '../../theme/app_theme.dart';

/// A13: حدود الصرف السارية من العقد المعتمد. تغيير حد هو تعديل للعقد (إصدار جديد)،
/// وليس استثناءً لمرة واحدة، لذا يظهر هنا للقراءة ويُعدَّل عبر مسار التعديل في المرحلة 3.
class ExpenseLimitsScreen extends StatelessWidget {
  const ExpenseLimitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final st = context.watch<ContractState>();
    final ops = context.watch<OperationsState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final rules = ops.activeRules(st, c.id);
    return Scaffold(
      appBar: AppBar(title: const Text('حدود الصرف')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            StateBanner.readOnly(
                'الحدود مستمدة من العقد المعتمد (الإصدار ${c.contractVersion == 0 ? '—' : c.contractVersion}). '
                'تغييرها يتطلب تعديل العقد بإصدار جديد بقرار الشركاء، وليس استثناءً.'),
            if (rules.isEmpty)
              const StateView.empty(title: 'لا توجد حدود سارية', message: 'تظهر الحدود بعد اعتماد عقد التأسيس.'),
            ...rules.map((r) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: const Icon(Icons.speed_rounded, color: AppColors.gold),
                    title: Text(r.rule.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '${r.rule.describe(value: (_) => r.valueLabel)}\n${r.rule.id} · الإصدار ${r.rule.version} · عند: ${r.rule.trigger}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.6),
                    ),
                    isThreeLine: true,
                    trailing: r.agreedValue == null
                        ? null
                        : Text(r.valueLabel, style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w900)),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
