import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'transaction_detail_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final notifications = appState.notifications;

    return Scaffold(
      appBar: AppBar(title: const Text('التنبيهات وسجل التدقيق')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            GoldBorderCard(
              child: Row(
                children: [
                  const Icon(
                    Icons.shield_moon_rounded,
                    color: AppColors.gold,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'كل إشعار موثّق بطابع زمني ومعرّف رسالة معتمد لدى مزود الخدمة، ويصلح كبينة قانونية.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ...notifications.map(
              (n) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _NotificationCard(notification: n),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AuditNotification notification;
  const _NotificationCard({required this.notification});

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    return GoldBorderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  notification.channel.icon,
                  color: AppColors.gold,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.body,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            children: [
              StatusChip(
                label: notification.channel.label,
                color: AppColors.info,
                icon: notification.channel.icon,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  intl.DateFormat('yyyy/MM/dd - hh:mm a').format(
                    notification.deliveredAt ?? notification.sentAt,
                  ),
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          if (notification.actionRequired &&
              notification.relatedTransactionId != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final tx = appState.transactions.firstWhere(
                    (t) => t.id == notification.relatedTransactionId,
                  );
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          TransactionDetailScreen(transaction: tx),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('مراجعة المعاملة المرتبطة'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
