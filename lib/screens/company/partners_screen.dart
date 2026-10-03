import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/company.dart';
import '../../providers/company_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

/// P04: الشركاء والحصص. يوضّح هيكل الملكية ووزن التصويت قبل أي قرار.
class PartnersScreen extends StatelessWidget {
  const PartnersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final c = cs.current;
    if (c == null) {
      return const StateView.empty(title: 'لا توجد شركة', message: 'أنشئ شركة أولاً لعرض شركائها.');
    }
    final partners = [...c.partners]..sort((a, b) => b.equity.compareTo(a.equity));
    final others = c.members.where((m) => !m.isPartner).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('الشركاء والحصص')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            GoldBorderCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('توزيع الملكية = وزن التصويت',
                      style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('رأس المال ${formatCurrency(c.capital, c.currency)} · ${c.status.label}'
                      '${c.contractVersion > 0 ? ' · العقد الإصدار ${c.contractVersion}' : ' · لا يوجد عقد موقّع بعد'}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: 18,
                      child: Row(
                        children: [
                          for (var i = 0; i < partners.length; i++)
                            Expanded(
                              flex: (partners[i].equity * 100).round().clamp(1, 1 << 30),
                              child: Container(color: _shade(i)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < partners.length; i++)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(width: 10, height: 10, decoration: BoxDecoration(color: _shade(i), shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                          Text('${partners[i].name} ${_p(partners[i].equity)}',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        ]),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SectionHeader(title: 'الشركاء (${partners.length})'),
            const SizedBox(height: 8),
            ...partners.map((m) => _MemberTile(member: m, isMe: m.phone == cs.myPhone)),
            if (others.isNotEmpty) ...[
              const SizedBox(height: 18),
              SectionHeader(title: 'أعضاء آخرون (${others.length})'),
              const SizedBox(height: 8),
              ...others.map((m) => _MemberTile(member: m, isMe: m.phone == cs.myPhone)),
            ],
          ],
        ),
      ),
    );
  }

  static String _p(double v) => '${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}%';

  static Color _shade(int i) => const [
        Color(0xFFC9A227),
        Color(0xFF3498DB),
        Color(0xFF2ECC71),
        Color(0xFF9B8AFB),
        Color(0xFFE67E22),
        Color(0xFF1ABC9C),
      ][i % 6];
}

class _MemberTile extends StatelessWidget {
  final CompanyMember member;
  final bool isMe;
  const _MemberTile({required this.member, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final m = member;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.navySurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isMe ? AppColors.gold.withValues(alpha: 0.5) : AppColors.divider),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.gold.withValues(alpha: 0.15),
            child: Text(m.name.isEmpty ? '؟' : m.name.characters.first,
                style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${m.name}${isMe ? ' (أنت)' : ''}',
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(m.roles.map((r) => r.label).join('، '),
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
              ],
            ),
          ),
          if (m.isPartner)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(PartnersScreen._p(m.equity),
                    style: const TextStyle(color: AppColors.gold, fontSize: 18, fontWeight: FontWeight.w900)),
                const Text('وزن التصويت', style: TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
              ],
            ),
        ],
      ),
    );
  }
}
