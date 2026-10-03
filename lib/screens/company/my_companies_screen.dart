import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/company.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../theme/app_theme.dart';
import '../contract/new_session_screen.dart';

/// P02: شركاتي. لا تظهر إلا الشركات التي يملك المستخدم صلاحية فيها.
class MyCompaniesScreen extends StatefulWidget {
  const MyCompaniesScreen({super.key});

  @override
  State<MyCompaniesScreen> createState() => _MyCompaniesScreenState();
}

class _MyCompaniesScreenState extends State<MyCompaniesScreen> {
  String _q = '';
  CompanyStatus? _status;

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final st = context.watch<ContractState>();
    final list = cs.companies
        .where((c) => _status == null || c.status == _status)
        .where((c) => _q.isEmpty || c.legalName.contains(_q))
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text('شركاتي (${cs.companies.length})')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.navyDark,
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewSessionScreen())),
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('تأسيس شركة', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          children: [
            TextField(
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: const InputDecoration(hintText: 'بحث باسم الشركة', prefixIcon: Icon(Icons.search_rounded)),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(label: const Text('الكل'), selected: _status == null, onSelected: (_) => setState(() => _status = null)),
                for (final s in CompanyStatus.values)
                  ChoiceChip(label: Text(s.label), selected: _status == s, onSelected: (_) => setState(() => _status = s)),
              ],
            ),
            const SizedBox(height: 14),
            if (list.isEmpty)
              const StateView.empty(title: 'لا نتائج', message: 'جرّب تعديل البحث أو التصفية.')
            else
              ...list.map((c) {
                final me = c.memberByPhone(cs.myPhone) ?? (cs.isCloud ? null : c.members.firstOrNull);
                final s = st.establishmentFor(c.id);
                final pending = (s == null || me == null) ? 0 : st.pendingFor(s, me.id).length;
                final selected = c.id == cs.current?.id;
                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    cs.select(c.id);
                    Navigator.pop(context);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.navySurface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: selected ? AppColors.gold : AppColors.divider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.business_rounded, color: AppColors.gold),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(c.legalName,
                                  style: const TextStyle(
                                      color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
                            ),
                            if (pending > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                    color: AppColors.info.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20)),
                                child: Text('$pending بانتظار صوتك',
                                    style: const TextStyle(color: AppColors.info, fontSize: 11, fontWeight: FontWeight.w700)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 16,
                          runSpacing: 6,
                          children: [
                            _Fact('دوري', me?.roles.map((r) => r.label).join('، ') ?? '—'),
                            if (me != null && me.isPartner)
                              _Fact('ملكيتي', '${me.equity.toStringAsFixed(me.equity % 1 == 0 ? 0 : 2)}%'),
                            _Fact('العقد', c.contractVersion > 0 ? 'الإصدار ${c.contractVersion}' : 'لم يُعتمد بعد'),
                            _Fact('الحالة', c.status.label),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final String k, v;
  const _Fact(this.k, this.v);

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(children: [
          TextSpan(text: '$k: ', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          TextSpan(
              text: v,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]),
      );
}
