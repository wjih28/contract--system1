import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/admin.dart';
import '../../models/company.dart';
import '../../models/questionnaire.dart';
import '../../providers/company_state.dart';
import '../../services/identity_service.dart';
import '../../theme/app_theme.dart';

/// موافقة الشريك المباشرة (A05): طلبات إتاحة بياناته الشخصية لأدوار من غير الشركاء.
/// لا تسري الإتاحة قبل موافقة كل الشركاء، وعدم الرد ليس موافقة.
class ConsentRequestsScreen extends StatelessWidget {
  const ConsentRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final c = cs.current;
    final me = cs.me;
    if (c == null || me == null || !me.isPartner) {
      return const Scaffold(body: StateView.denied(message: 'هذه الطلبات للشركاء فقط.'));
    }
    final pending = cs.pendingConsents(c, me.id);
    return Scaffold(
      appBar: AppBar(title: const Text('طلبات إتاحة بياناتي')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            const StateBanner(
              color: AppColors.info,
              icon: Icons.privacy_tip_rounded,
              text: 'طلبت الإدارة إتاحة نوع من بياناتك الشخصية لدور من غير الشركاء. لا تسري الإتاحة إلا بموافقتك وموافقة بقية الشركاء.',
            ),
            if (pending.isEmpty)
              const StateView.empty(
                  icon: Icons.verified_user_rounded, title: 'لا توجد طلبات', message: 'لم تُطلب إتاحة أي من بياناتك الشخصية.'),
            for (final (pointId, role) in pending)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(ControlPoint.byId(pointId).label,
                        style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      'الإتاحة لدور: ${role.label} · الإجراءات: '
                      '${(c.controlPoints[pointId]?[role.name] ?? const []).map((a) => PermAction.values.byName(a).label).join('، ')}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final m = await IdentityService.confirm(context,
                            partnerName: me.name, action: 'الموافقة على إتاحة ${ControlPoint.byId(pointId).label} لدور ${role.label}');
                        if (m != null) cs.giveConsent(c.id, pointId, role, me.id, method: m.label);
                      },
                      icon: const Icon(Icons.how_to_reg_rounded),
                      label: const Text('أوافق'),
                    ),
                    const Text('إن لم توافق فلا حاجة لأي إجراء: تبقى بياناتك محجوبة عن هذا الدور.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// شارة على لوحة الشريك عند وجود طلبات موافقة
class ConsentBanner extends StatelessWidget {
  const ConsentBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final c = cs.current;
    final me = cs.me;
    if (c == null || me == null || !me.isPartner) return const SizedBox.shrink();
    final n = cs.pendingConsents(c, me.id).length;
    if (n == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          leading: const Icon(Icons.privacy_tip_rounded, color: AppColors.warning),
          title: Text('$n طلبات لإتاحة بياناتك الشخصية تنتظر قرارك'),
          trailing: const Icon(Icons.chevron_left_rounded),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConsentRequestsScreen())),
        ),
      ),
    );
  }
}

