import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class ContractsScreen extends StatefulWidget {
  const ContractsScreen({super.key});

  @override
  State<ContractsScreen> createState() => _ContractsScreenState();
}

class _ContractsScreenState extends State<ContractsScreen> {
  int _currentIndex = 0;
  final Map<int, VoteChoice> _votes = {};

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final clauses = appState.clauses;
    final clause = clauses[_currentIndex];
    final totalQuestions = 200; // بنك افتراضي كامل للعرض

    return Scaffold(
      appBar: AppBar(title: const Text('جلسة التصويت على العقد')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'البند ${clause.id} من $totalQuestions',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  StatusChip(
                    label: clause.category,
                    color: AppColors.info,
                    icon: Icons.category_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: clause.id / totalQuestions,
                  minHeight: 7,
                  backgroundColor: AppColors.navyLight,
                  color: AppColors.gold,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GoldBorderCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: const [
                                Icon(
                                  Icons.article_rounded,
                                  color: AppColors.gold,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'نص البند التعاقدي',
                                  style: TextStyle(
                                    color: AppColors.gold,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              clause.text,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 15,
                                height: 1.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _QuorumIndicator(clause: clause, votes: _votes, partners: appState.partners),
                      const SizedBox(height: 18),
                      const SectionHeader(title: 'موقف الشركاء'),
                      const SizedBox(height: 10),
                      ...appState.partners
                          .where((p) => p.equityPercentage > 0)
                          .map((p) => _PartnerVoteRow(
                                partner: p,
                                vote: _votes[clause.id],
                              )),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _VoteButton(
                      label: 'موافق',
                      color: AppColors.success,
                      icon: Icons.check_circle_rounded,
                      selected: _votes[clause.id] == VoteChoice.agree,
                      onTap: () => _vote(clause.id, VoteChoice.agree),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _VoteButton(
                      label: 'غير موافق',
                      color: AppColors.danger,
                      icon: Icons.cancel_rounded,
                      selected: _votes[clause.id] == VoteChoice.disagree,
                      onTap: () => _vote(clause.id, VoteChoice.disagree),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _VoteButton(
                      label: 'محايد',
                      color: AppColors.textMuted,
                      icon: Icons.remove_circle_rounded,
                      selected: _votes[clause.id] == VoteChoice.neutral,
                      onTap: () => _vote(clause.id, VoteChoice.neutral),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _vote(clause.id, VoteChoice.defer),
                      icon: const Icon(Icons.schedule_rounded, size: 18),
                      label: const Text('تأجيل البند'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _votes[clause.id] == null
                          ? null
                          : () {
                              if (_currentIndex < clauses.length - 1) {
                                setState(() => _currentIndex++);
                              } else {
                                _showSignatureSheet(context);
                              }
                            },
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                      label: Text(
                        _currentIndex < clauses.length - 1
                            ? 'التالي'
                            : 'إنهاء الجلسة والتوقيع',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _vote(int id, VoteChoice v) => setState(() => _votes[id] = v);

  void _showSignatureSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.navySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: Icon(
                Icons.verified_rounded,
                color: AppColors.gold,
                size: 44,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'التوثيق النهائي للجلسة',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'التقط بصمتك الحيوية ووقّع لإتمام إقرارك بكافة البنود المتراضى عليها',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.fingerprint_rounded),
                    label: const Text('البصمة الحيوية'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.draw_rounded),
                    label: const Text('التوقيع'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'تم توليد العقد النهائي PDF/A مع QR كود التحقق ✅',
                    ),
                  ),
                );
              },
              child: const Text('تأكيد وتوليد العقد النهائي'),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuorumIndicator extends StatelessWidget {
  final ContractClause clause;
  final Map<int, VoteChoice> votes;
  final List<Partner> partners;

  const _QuorumIndicator({
    required this.clause,
    required this.votes,
    required this.partners,
  });

  @override
  Widget build(BuildContext context) {
    final currentVote = votes[clause.id];
    double agreedEquity = 0;
    if (currentVote == VoteChoice.agree) {
      agreedEquity = partners
          .where((p) => p.role != UserRole.lawyer)
          .fold(0, (sum, p) => sum + p.equityPercentage);
    }
    final ratio = (agreedEquity / clause.requiredQuorumValue).clamp(0, 1.0);

    return GoldBorderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'النصاب المطلوب لهذا البند',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                clause.requiredQuorumLabel,
                style: const TextStyle(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: ratio.toDouble(),
              minHeight: 10,
              backgroundColor: AppColors.navyLight,
              color: ratio >= 1 ? AppColors.success : AppColors.gold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${agreedEquity.toStringAsFixed(1)}% من الحصص وافقت حتى الآن',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _PartnerVoteRow extends StatelessWidget {
  final Partner partner;
  final VoteChoice? vote;
  const _PartnerVoteRow({required this.partner, required this.vote});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.gold.withValues(alpha: 0.15),
            child: Text(
              partner.avatarInitial,
              style: const TextStyle(color: AppColors.gold, fontSize: 12),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${partner.fullName} (${partner.equityPercentage.toStringAsFixed(0)}%)',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
              ),
            ),
          ),
          if (vote != null)
            StatusChip(
              label: vote!.label,
              color: vote == VoteChoice.agree
                  ? AppColors.success
                  : vote == VoteChoice.disagree
                      ? AppColors.danger
                      : AppColors.textMuted,
              icon: vote == VoteChoice.agree
                  ? Icons.check_rounded
                  : vote == VoteChoice.disagree
                      ? Icons.close_rounded
                      : Icons.remove_rounded,
            )
          else
            const Text(
              'بانتظار التصويت',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

class _VoteButton extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _VoteButton({
    required this.label,
    required this.color,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.18) : AppColors.navySurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : AppColors.divider,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? color : AppColors.textMuted, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : AppColors.textMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
