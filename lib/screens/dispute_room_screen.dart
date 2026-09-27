import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class DisputeRoomScreen extends StatelessWidget {
  const DisputeRoomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final disputes = appState.disputes;

    return Scaffold(
      appBar: AppBar(title: const Text('غرفة التقاضي الرقمية')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppColors.goldGradient,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.gavel_rounded,
                    color: AppColors.navyDark,
                    size: 28,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'مساحة المستشار القانوني',
                          style: TextStyle(
                            color: AppColors.navyDark,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'توليد ملفات الإثبات القضائي بضغطة زر واحدة',
                          style: TextStyle(
                            color: AppColors.navyDark,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SectionHeader(title: 'القضايا المفتوحة'),
            const SizedBox(height: 12),
            ...disputes.map(
              (d) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DisputeCard(dispute: d),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisputeCard extends StatelessWidget {
  final DisputeCase dispute;
  const _DisputeCard({required this.dispute});

  @override
  Widget build(BuildContext context) {
    final statusColor = dispute.status == 'مغلقة'
        ? AppColors.success
        : dispute.status == 'قيد الترافع'
            ? AppColors.warning
            : AppColors.danger;

    return GoldBorderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  dispute.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              StatusChip(
                label: dispute.status,
                color: statusColor,
                icon: Icons.info_rounded,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            dispute.clauseText,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'المبلغ المتنازع عليه: ${formatCurrency(dispute.disputedAmount)}',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11.5,
                ),
              ),
              Text(
                intl.DateFormat('yyyy/MM/dd').format(dispute.openedAt),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showEvidencePack(context, dispute),
              icon: const Icon(Icons.folder_zip_rounded, size: 18),
              label: const Text('توليد ملف الإثبات القضائي'),
            ),
          ),
        ],
      ),
    );
  }

  void _showEvidencePack(BuildContext context, DisputeCase d) {
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
            const Text(
              'حزمة الإثبات القضائي الرقمي',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            _evidenceItem(Icons.description_rounded, 'نسخة العقد الأساسي الموقعة إلكترونياً وبصمياً'),
            _evidenceItem(Icons.rule_rounded, 'نص البند القانوني المخالف: ${d.clauseText}'),
            _evidenceItem(Icons.receipt_long_rounded, 'قيد اليومية وسند الصرف غير المطابق'),
            _evidenceItem(Icons.notifications_active_rounded, 'سجل التنبيهات والإشعارات وحالة الاستجابة'),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم تجهيز ملف الدعوى بصيغة PDF/A مشفرة ✅'),
                  ),
                );
              },
              icon: const Icon(Icons.download_rounded),
              label: const Text('تصدير الملف القضائي'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _evidenceItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.gold, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
