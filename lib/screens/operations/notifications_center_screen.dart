import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/operations.dart';
import '../../providers/company_state.dart';
import '../../providers/operations_state.dart';
import '../../theme/app_theme.dart';
import 'approvals_screen.dart';
import 'tx_detail_screen.dart';
import 'tx_widgets.dart';
import 'violations_screen.dart';

/// P21: مركز الإشعارات مع دليل التسليم لكل قناة (معرّف الرسالة، وقت الإرسال، الحالة).
class NotificationsCenterScreen extends StatefulWidget {
  const NotificationsCenterScreen({super.key});

  @override
  State<NotificationsCenterScreen> createState() => _NotificationsCenterScreenState();
}

class _NotificationsCenterScreenState extends State<NotificationsCenterScreen> {
  NotifCategory? _cat;

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final ops = context.watch<OperationsState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final mine = ops.notificationsFor(c.id, cs.me?.id);
    final list = mine.where((n) => _cat == null || n.category == _cat).toList();
    final unread = mine.where((n) => !n.read).length;

    return Scaffold(
      appBar: AppBar(
        title: Text('الإشعارات${unread == 0 ? '' : ' ($unread غير مقروء)'}'),
        actions: [
          IconButton(
            tooltip: 'تفضيلات الإشعار',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationPrefsScreen())),
          ),
        ],
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                ChoiceChip(label: const Text('الكل'), selected: _cat == null, onSelected: (_) => setState(() => _cat = null)),
                for (final x in NotifCategory.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: ChoiceChip(label: Text(x.label), selected: _cat == x, onSelected: (_) => setState(() => _cat = x)),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const StateView.empty(
                icon: Icons.notifications_none_rounded,
                title: 'لا توجد إشعارات',
                message: 'تصلك هنا تنبيهات الحوكمة: العمليات المجمّدة، طلبات الاستثناء، المخالفات.',
              ),
            ...list.map((n) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  // Material بدل Container لتظهر لمسة الضغط فوق خلفية البطاقة
                  child: Material(
                    color: AppColors.navySurface,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: n.read ? AppColors.divider : AppColors.gold.withValues(alpha: 0.5)),
                    ),
                    child: ListTile(
                    onTap: () {
                      ops.markRead(c, n);
                      _open(context, n);
                    },
                    leading: Icon(
                      n.category == NotifCategory.violation ? Icons.gpp_bad_rounded : Icons.notifications_active_rounded,
                      color: n.read ? AppColors.textMuted : AppColors.gold,
                    ),
                    title: Text(n.subject,
                        style: TextStyle(color: AppColors.textPrimary, fontWeight: n.read ? FontWeight.w500 : FontWeight.w800, fontSize: 13.5)),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SizedBox(height: 3),
                      Text(n.body, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5)),
                      const SizedBox(height: 4),
                      Text('${txTime.format(n.sentAt.toLocal())} · ${n.category.label}${n.category.mandatory ? ' · إلزامي' : ''}',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ]),
                    trailing: IconButton(
                      tooltip: 'تفاصيل التسليم',
                      icon: const Icon(Icons.local_shipping_outlined, size: 20),
                      onPressed: () => _delivery(context, n),
                    ),
                  ),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, AppNotification n) {
    final Widget? page = switch (n.relatedType) {
      'transaction' => TxDetailScreen(txId: n.relatedId!),
      'exception' => const ApprovalsScreen(),
      'violation' => const ViolationsScreen(),
      _ => null,
    };
    if (page != null) Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  /// دليل التسليم: يوضح بصدق أي القنوات لم تُهيأ بعد
  void _delivery(BuildContext context, AppNotification n) => showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.navySurface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('دليل التسليم', style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              ...n.deliveries.map((d) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(d.channel.icon, color: d.status.color),
                    title: Text(d.channel.label),
                    subtitle: Text(
                      '${d.status.label} · ${txTime.format(d.at.toLocal())}${d.messageRef == null ? '' : ' · المرجع ${d.messageRef}'}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                    ),
                  )),
              const Text(
                'الرسائل النصية والبريد تُرسل بعد ربط مزوّد الرسائل من إعدادات القنوات، ويُحفظ حينها معرّف الرسالة وحالة التسليم كدليل.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.6),
              ),
            ]),
          ),
        ),
      );
}

/// P22: تفضيلات الإشعار. الإشعارات القانونية والمخالفات إلزامية ولا يمكن إيقافها.
class NotificationPrefsScreen extends StatelessWidget {
  const NotificationPrefsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final ops = context.watch<OperationsState>();
    final c = cs.current;
    final me = cs.me;
    if (c == null || me == null) return const Scaffold(body: StateView.denied());
    final muted = ops.mutedByMember[me.id] ?? const <NotifCategory>{};
    return Scaffold(
      appBar: AppBar(title: const Text('تفضيلات الإشعار')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const StateBanner(
              color: AppColors.info,
              icon: Icons.info_outline_rounded,
              text: 'الإشعارات القانونية والمخالفات إلزامية حسب سياسة النظام. يُسجَّل أي تغيير في التفضيلات في سجل التدقيق.',
            ),
            for (final cat in NotifCategory.values)
              SwitchListTile(
                value: !muted.contains(cat),
                onChanged: cat.mandatory ? null : (v) => ops.setMuted(c.id, me.id, cat, !v),
                activeThumbColor: AppColors.gold,
                title: Text(cat.label),
                subtitle: Text(cat.mandatory ? 'إلزامي ولا يمكن إيقافه' : 'يمكنك إيقافه',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
            const Divider(height: 30),
            const Text('القنوات', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final ch in NotifChannel.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(ch.icon, color: ch == NotifChannel.app ? AppColors.success : AppColors.textMuted),
                title: Text(ch.label),
                subtitle: Text(
                  ch == NotifChannel.app
                      ? 'مفعّلة'
                      : ch == NotifChannel.sms
                          ? 'رقمك المؤكد: ${me.phone} · تُفعَّل بعد ربط مزوّد الرسائل'
                          : 'تُفعَّل بعد ربط المزوّد',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
