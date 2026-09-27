import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class TransactionDetailScreen extends StatelessWidget {
  final LedgerTransaction transaction;
  const TransactionDetailScreen({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final current = appState.transactions.firstWhere(
      (t) => t.id == transaction.id,
      orElse: () => transaction,
    );
    final isPending = current.status == TransactionStatus.frozen ||
        current.status == TransactionStatus.pendingApproval;

    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل المعاملة')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: current.status.color.withValues(alpha: 0.14),
                  ),
                  child: Icon(
                    current.status.icon,
                    color: current.status.color,
                    size: 40,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: StatusChip(
                  label: current.status.label,
                  color: current.status.color,
                  icon: current.status.icon,
                ),
              ),
              const SizedBox(height: 20),
              GoldBorderCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      current.description,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Divider(height: 24),
                    _row('المبلغ', formatCurrency(current.amount)),
                    _row(
                      'التاريخ',
                      intl.DateFormat('yyyy/MM/dd - hh:mm a').format(
                        current.date,
                      ),
                    ),
                    _row('رقم المعاملة', '#${current.id.toUpperCase()}'),
                  ],
                ),
              ),
              if (current.clauseReference != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.dangerBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(
                            Icons.gavel_rounded,
                            color: AppColors.danger,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'البند التعاقدي المخالف',
                            style: TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        current.clauseReference!,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          height: 1.6,
                        ),
                      ),
                      if (current.triggeredRule != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'القاعدة المُفعّلة: ${current.triggeredRule!}',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const SectionHeader(title: 'مسار الإشعار'),
              const SizedBox(height: 12),
              _NotificationTimeline(),
              const SizedBox(height: 30),
              if (isPending) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          appState.resolveTransaction(
                            current.id,
                            approve: false,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'تم تسجيل المعاملة كخرق تعاقدي وإحالتها لغرفة التقاضي',
                              ),
                            ),
                          );
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('رفض'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          appState.resolveTransaction(
                            current.id,
                            approve: true,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'تم فك التجميد واعتماد المعاملة استثنائياً',
                              ),
                            ),
                          );
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('اعتماد'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTimeline extends StatelessWidget {
  final stages = const ['أُرسلت', 'تم التسليم', 'تمت المشاهدة'];

  @override
  Widget build(BuildContext context) {
    return GoldBorderCard(
      child: Row(
        children: List.generate(stages.length * 2 - 1, (i) {
          if (i.isOdd) {
            return Expanded(
              child: Container(height: 2, color: AppColors.gold),
            );
          }
          final idx = i ~/ 2;
          return Column(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.gold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                stages[idx],
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10.5,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
