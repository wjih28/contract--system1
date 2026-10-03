import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// حالات الشاشة الموحدة (القسم 8 من المواصفات):
/// تحميل، فارغ، خطأ، رفض صلاحية، معلّق، تعارض تحديث، للقراءة فقط.
class StateView extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const StateView({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  /// فارغ: يشرح لماذا لا توجد بيانات، ويعرض الإجراء التالي المسموح
  const StateView.empty({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.icon = Icons.inbox_rounded,
  }) : color = AppColors.gold;

  /// رفض الصلاحية: لا يكشف أي بيانات مخفية
  const StateView.denied({
    super.key,
    this.message = 'هذا الإجراء مقيّد حسب دورك في الشركة.',
  })  : icon = Icons.lock_rounded,
        color = AppColors.textMuted,
        title = 'لا تملك صلاحية الوصول',
        actionLabel = null,
        onAction = null;

  /// خطأ تكامل أو اتصال: مع إمكانية إعادة المحاولة
  const StateView.error({
    super.key,
    required this.message,
    this.onAction,
    this.title = 'تعذر إكمال العملية',
  })  : icon = Icons.sync_problem_rounded,
        color = AppColors.danger,
        actionLabel = 'إعادة المحاولة';

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.12)),
              child: Icon(icon, color: color, size: 38),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 15.5)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.7)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// شريط حالة أعلى الشاشة: معلّق، تعارض تحديث، للقراءة فقط، تنبيه حرج
class StateBanner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  const StateBanner({
    super.key,
    required this.color,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  /// تعارض: تغيّر السجل من جهاز آخر، ولا نستبدله بصمت
  factory StateBanner.conflict({required VoidCallback onRefresh}) => StateBanner(
        color: AppColors.warning,
        icon: Icons.sync_rounded,
        text: 'تغيّر هذا السجل من جهاز آخر. راجع التحديث قبل المتابعة.',
        actionLabel: 'تحديث',
        onAction: onRefresh,
      );

  /// للقراءة فقط: سجل تاريخي بلا أدوات تعديل
  factory StateBanner.readOnly(String text) =>
      StateBanner(color: AppColors.textMuted, icon: Icons.lock_outline_rounded, text: text);

  /// بيانات توضيحية: الشاشة لم تُربط بعد ببيانات حقيقية
  factory StateBanner.demo() => const StateBanner(
        color: AppColors.info,
        icon: Icons.science_rounded,
        text: 'نموذج توضيحي: هذه الشاشة تعرض بيانات تجريبية وستُربط بالبيانات الحقيقية في مرحلة لاحقة.',
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 12.5, height: 1.6, fontWeight: FontWeight.w600)),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

/// هيكل تحميل (Skeleton) يحافظ على شكل الصفحة أثناء التحميل
class SkeletonList extends StatelessWidget {
  final int count;
  const SkeletonList({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => Container(
        height: 76,
        decoration: BoxDecoration(
          color: AppColors.navySurface,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
