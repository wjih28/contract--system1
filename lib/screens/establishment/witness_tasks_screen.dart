import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../providers/contract_state.dart';
import '../../theme/app_theme.dart';
import 'witness_attestation_screen.dart';

/// مهام الشاهد (بداية بوابة الأطراف المهنية): العقود التي دُعي للشهادة عليها.
/// صلاحية الشاهد محصورة في الشهادة، ولا تمنحه حق التصويت أو الملكية.
class WitnessTasksScreen extends StatelessWidget {
  const WitnessTasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<ContractState>();
    final tasks = st.witnessTasks;
    return Scaffold(
      appBar: AppBar(title: const Text('مهامي المهنية')),
      body: tasks.isEmpty
          ? const StateView.empty(
              icon: Icons.assignment_turned_in_rounded,
              title: 'لا توجد مهام بانتظارك',
              message: 'عندما يدعوك شركاء للشهادة على عقد برقم جوالك، تظهر الدعوة هنا.',
            )
          : ContentWidth(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  for (final s in tasks)
                    for (final e in s.witnesses.asMap().entries.where((e) => e.value.phone == st.myPhone && !e.value.attested))
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: AppColors.navySurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.person_pin_rounded, color: AppColors.gold),
                          title: Text('الشهادة على عقد تأسيس ${s.companyName}',
                              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            st.signingBlockers(s).isEmpty ? 'العقد جاهز للشهادة' : 'بانتظار حسم البنود قبل الشهادة',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                          ),
                          trailing: const Icon(Icons.chevron_left_rounded),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => WitnessAttestationScreen(sessionId: s.id, witnessIndex: e.key),
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}
