import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/questionnaire.dart';
import '../providers/company_state.dart';
import '../providers/contract_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'contract/session_overview_screen.dart';

/// تبويب العقود: جلسات إعداد عقود التأسيس عبر الاستبانة الذكية
class ContractsScreen extends StatelessWidget {
  const ContractsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ContractState>();
    final company = context.watch<CompanyState>().current;
    // جلسات الشركة الحالية فقط، والجلسات القديمة غير المرتبطة بشركة تظهر عند عدم وجود شركة
    final sessions = state.sessionsFor(company?.id);

    return Scaffold(
      appBar: AppBar(title: const Text('التأسيس والعقد')),
      // الشركة الواحدة لها جلسة تأسيس واحدة؛ تعديل العقد بعد اعتماده يكون بإصدار جديد (المرحلة 3)
      floatingActionButton: company == null || sessions.isNotEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.navyDark,
              onPressed: () {
                final s = state.createSession(
                  companyId: company.id,
                  companyName: company.legalName,
                  companyType: company.companyType,
                  currency: company.currency,
                  capital: company.capital,
                  partners: company.partners.map((m) => m.toSessionPartner()).toList(),
                );
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SessionOverviewScreen(sessionId: s.id)),
                );
              },
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('بدء جلسة التأسيس', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
      body: !state.loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              children: [
                _IntroCard(bankSize: state.bank.length),
                const SizedBox(height: 22),
                SectionHeader(title: 'الجلسات (${sessions.length})'),
                const SizedBox(height: 10),
                if (sessions.isEmpty) const _EmptyState(),
                ...sessions.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SessionCard(session: s),
                    )),
              ],
            ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  final int bankSize;
  const _IntroCard({required this.bankSize});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [AppColors.navySurface, AppColors.navyLight],
        ),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: GeometricCornerPainter()),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: AppColors.gold, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'المحامي الذكي لعقد التأسيس',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'يعرض عليكم النظام البنود واحداً تلو الآخر مع سؤال توعوي لكل بند. يصوت كل شريك ويؤكد هويته، ولا يصدر العقد إلا بعد التراضي على كل البنود.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusChip(
                    label: '$bankSize بنداً في البنك',
                    color: AppColors.gold,
                    icon: Icons.library_books_rounded,
                  ),
                  const StatusChip(
                    label: 'نصاب مرجّح بالحصص',
                    color: AppColors.info,
                    icon: Icons.pie_chart_rounded,
                  ),
                  const StatusChip(
                    label: 'حفظ تلقائي واستئناف',
                    color: AppColors.success,
                    icon: Icons.cloud_done_rounded,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return GoldBorderCard(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.gold.withValues(alpha: 0.1),
            ),
            child: const Icon(Icons.history_edu_rounded,
                color: AppColors.gold, size: 40),
          ),
          const SizedBox(height: 16),
          const Text(
            'لا توجد جلسات بعد',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'ابدأ جلسة تأسيس جديدة لصياغة عقد شركتكم بالتصويت على البنود',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final ContractSession session;
  const _SessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final s = session;
    final pct = (s.progress * 100).round();
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SessionOverviewScreen(sessionId: s.id)),
      ),
      child: GoldBorderCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: s.status.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.business_rounded, color: s.status.color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.companyName,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${s.companyType} · ${s.partners.length} شركاء · ${formatCurrency(s.capital, s.currency)}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                StatusChip(
                  label: s.status.label,
                  color: s.status.color,
                  icon: Icons.circle,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: s.progress,
                      minHeight: 7,
                      backgroundColor: AppColors.navyLight,
                      color: pct == 100 ? AppColors.success : AppColors.gold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('$pct%',
                    style: const TextStyle(
                        color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 12.5)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Mini(ClauseStatus.agreed, s.count(ClauseStatus.agreed)),
                _Mini(ClauseStatus.deferred, s.count(ClauseStatus.deferred)),
                _Mini(ClauseStatus.rejected, s.count(ClauseStatus.rejected)),
                const Spacer(),
                Text(
                  DateFormat('d/M/yyyy – HH:mm').format(s.updatedAt),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  final ClauseStatus status;
  final int n;
  const _Mini(this.status, this.n);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 12),
      child: Row(
        children: [
          Icon(status.icon, size: 13, color: status.color),
          const SizedBox(width: 3),
          Text('$n ${status.label}',
              style: TextStyle(color: status.color, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
