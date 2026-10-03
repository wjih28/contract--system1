import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/governance_config.dart';
import '../../models/questionnaire.dart';
import '../../providers/contract_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

/// A12: العملات المعتمدة في العقود. تغيير الإعداد لا يغيّر القيم المالية التاريخية.
class CurrencySettingsScreen extends StatelessWidget {
  const CurrencySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<ContractState>();
    return Scaffold(
      appBar: AppBar(title: const Text('العملات')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            const StateBanner(
              color: AppColors.info,
              icon: Icons.info_outline_rounded,
              text: 'العملات المفعّلة تظهر عند تأسيس شركة جديدة. تعطيل عملة لا يغيّر عقود الشركات القائمة. '
                  'لا يُجمع رصيد بعملتين دون سعر تحويل معتمد.',
            ),
            for (final c in st.currencies)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.navySurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.enabled ? AppColors.gold.withValues(alpha: 0.4) : AppColors.divider),
                ),
                child: Row(children: [
                  CircleAvatar(
                    backgroundColor: AppColors.gold.withValues(alpha: 0.15),
                    child: Text(c.currency.symbol, style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${c.currency.label} (${c.currency.code})',
                          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                      Text('مثال التنسيق: ${formatCurrency(12500, c.currency)}',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ]),
                  ),
                  Switch(
                    value: c.enabled,
                    activeThumbColor: AppColors.gold,
                    onChanged: (v) {
                      st.setCurrency(CurrencySetting(currency: c.currency, enabled: v, decimals: c.decimals));
                      if (!v && st.enabledCurrencies.contains(c.currency)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('يجب أن تبقى عملة واحدة مفعّلة على الأقل')));
                      }
                    },
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

/// العملات المتاحة لاختيار عملة العقد
List<AppCurrency> enabledCurrencies(BuildContext context) => context.read<ContractState>().enabledCurrencies;
