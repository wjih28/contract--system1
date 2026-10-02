import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../models/company.dart';
import '../../models/operations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

final txDate = DateFormat('yyyy/MM/dd');
final txTime = DateFormat('yyyy/MM/dd HH:mm');

/// هل يملك المستخدم صلاحية تسجيل العمليات وطلب الاستثناءات (بوابة التشغيل)
bool canOperate(Set<CompanyRole> roles) => roles.any((r) =>
    r == CompanyRole.managingPartner || r == CompanyRole.executiveManager || r == CompanyRole.financialManager);

/// شارة حالة العملية
class TxStatusPill extends StatelessWidget {
  final TxStatus status;
  const TxStatusPill(this.status, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: status.color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: status.color.withValues(alpha: 0.45)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(status.icon, size: 12, color: status.color),
          const SizedBox(width: 4),
          Text(status.label, style: TextStyle(color: status.color, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// بطاقة عملية في القوائم: المبلغ والعملة مقروءان دائماً
class TxTile extends StatelessWidget {
  final FinancialTx tx;
  final VoidCallback onTap;
  const TxTile({super.key, required this.tx, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.navySurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: tx.status.color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(12)),
              child: Icon(tx.category.icon, color: tx.status.color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tx.payee.isEmpty ? tx.category.label : tx.payee,
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${tx.category.label} · ${txDate.format(tx.date)} · ${tx.source.label}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                if (tx.triggered.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('السبب: ${tx.triggered.first.ruleName}',
                        style: TextStyle(color: tx.status.color, fontSize: 11.5)),
                  ),
              ]),
            ),
            const SizedBox(width: 8),
            // عمود المبلغ والحالة بعرض محدود حتى لا يتجاوز الشاشة على الجوال
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(formatCurrency(tx.amount, tx.currency),
                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w900, fontSize: 15)),
                ),
                const SizedBox(height: 4),
                FittedBox(fit: BoxFit.scaleDown, child: TxStatusPill(tx.status)),
              ]),
            ),
          ]),
        ),
      );
}

/// بطاقة مؤشر رقمي
class KpiCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final double width;
  final VoidCallback? onTap;
  const KpiCard({super.key, required this.label, required this.value, required this.icon, required this.color, required this.width, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: width,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.navySurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 19, fontWeight: FontWeight.w900)),
            Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
          ]),
        ),
      );
}

/// شبكة مؤشرات تتكيف مع العرض
class KpiGrid extends StatelessWidget {
  final List<KpiCard Function(double width)> items;
  const KpiGrid({super.key, required this.items});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth > 760 ? 4 : 2;
        final w = (box.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(spacing: 10, runSpacing: 10, children: [for (final f in items) f(w)]);
      });
}
