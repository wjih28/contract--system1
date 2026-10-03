import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// مفردات الحالة الموحدة في المنصة كلها (القسم 2.2 من المواصفات).
/// كل حالة لها تسمية ولون وأيقونة ثابتة، ولا تعتمد على اللون وحده.
enum GovStatus {
  draft,
  pending,
  approved,
  rejected,
  deferred,
  neutralized,
  frozen,
  violation,
  dispute,
  archived,
  integrationError,
  signatureFailed,
}

extension GovStatusX on GovStatus {
  String get label => switch (this) {
        GovStatus.draft => 'مسودة',
        GovStatus.pending => 'معلّق',
        GovStatus.approved => 'معتمد',
        GovStatus.rejected => 'مرفوض',
        GovStatus.deferred => 'مؤجل',
        GovStatus.neutralized => 'محيّد',
        GovStatus.frozen => 'مجمّد / قيد المراجعة',
        GovStatus.violation => 'مخالفة',
        GovStatus.dispute => 'نزاع',
        GovStatus.archived => 'مؤرشف / للقراءة فقط',
        GovStatus.integrationError => 'خطأ تكامل',
        GovStatus.signatureFailed => 'فشل التوقيع',
      };

  /// شرح الحالة كما ورد في المواصفات، يظهر عند الضغط على الشارة
  String get meaning => switch (this) {
        GovStatus.draft => 'سجل قابل للتعديل وغير نهائي قانونياً.',
        GovStatus.pending => 'بانتظار شخص أو نصاب أو تكامل أو إجراء مجدول.',
        GovStatus.approved => 'اكتملت الموافقة المطلوبة.',
        GovStatus.rejected => 'رُفض صراحة، ويظهر السبب والإجراء التالي المسموح.',
        GovStatus.deferred => 'أُجّل القرار إلى جلسة لاحقة.',
        GovStatus.neutralized => 'استُبعد البند بإجراء مسموح، وهذا ليس موافقة.',
        GovStatus.frozen => 'الإجراء محجوز بانتظار المراجعة أو قرار استثناء.',
        GovStatus.violation => 'سُجّل خرق لقاعدة وفق سياسة النظام.',
        GovStatus.dispute => 'خلاف جوهري غير محسوم له تذكرة نزاع دائمة.',
        GovStatus.archived => 'سجل تاريخي لا يمكن تعديله.',
        GovStatus.integrationError => 'فشلت المزامنة مع خدمة خارجية وتحتاج متابعة.',
        GovStatus.signatureFailed => 'لم تكتمل خطوة التوقيع أو البصمة.',
      };

  Color get color => switch (this) {
        GovStatus.draft => AppColors.textSecondary,
        GovStatus.pending => AppColors.info,
        GovStatus.approved => AppColors.success,
        GovStatus.rejected => AppColors.danger,
        GovStatus.deferred => AppColors.warning,
        GovStatus.neutralized => const Color(0xFF9B8AFB),
        GovStatus.frozen => const Color(0xFF5DADE2),
        GovStatus.violation => AppColors.danger,
        GovStatus.dispute => const Color(0xFFE67E22),
        GovStatus.archived => AppColors.textMuted,
        GovStatus.integrationError => const Color(0xFFE74C3C),
        GovStatus.signatureFailed => const Color(0xFFE74C3C),
      };

  IconData get icon => switch (this) {
        GovStatus.draft => Icons.edit_note_rounded,
        GovStatus.pending => Icons.hourglass_top_rounded,
        GovStatus.approved => Icons.verified_rounded,
        GovStatus.rejected => Icons.cancel_rounded,
        GovStatus.deferred => Icons.schedule_rounded,
        GovStatus.neutralized => Icons.block_rounded,
        GovStatus.frozen => Icons.ac_unit_rounded,
        GovStatus.violation => Icons.gpp_bad_rounded,
        GovStatus.dispute => Icons.gavel_rounded,
        GovStatus.archived => Icons.inventory_2_rounded,
        GovStatus.integrationError => Icons.sync_problem_rounded,
        GovStatus.signatureFailed => Icons.draw_rounded,
      };
}

/// شارة الحالة الموحدة: أيقونة + نص + لون، وتشرح معناها عند الضغط
class StatusBadge extends StatelessWidget {
  final GovStatus status;
  final String? overrideLabel;
  final bool dense;

  const StatusBadge(this.status, {super.key, this.overrideLabel, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final c = status.color;
    return Tooltip(
      message: status.meaning,
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(status.icon, size: dense ? 12 : 14, color: c),
            const SizedBox(width: 5),
            Text(
              overrideLabel ?? status.label,
              style: TextStyle(color: c, fontSize: dense ? 10.5 : 11.5, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
