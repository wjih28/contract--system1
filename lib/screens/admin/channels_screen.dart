import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../models/operations.dart';
import '../../providers/operations_state.dart';
import '../../theme/app_theme.dart';

/// A14 + A15: قنوات الإشعار وقوالب الرسائل.
class ChannelsScreen extends StatelessWidget {
  const ChannelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ops = context.watch<OperationsState>();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('القنوات والقوالب'),
          bottom: const TabBar(tabs: [Tab(text: 'قنوات الإشعار'), Tab(text: 'قوالب الرسائل')]),
        ),
        body: ContentWidth(
          child: TabBarView(children: [
            ListView(padding: const EdgeInsets.all(20), children: [
              for (final ch in NotifChannel.values)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: Icon(ch.icon, color: ch == NotifChannel.app ? AppColors.success : AppColors.textMuted),
                    title: Text(ch.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      switch (ch) {
                        NotifChannel.app => 'متصلة · تُسلَّم فوراً داخل التطبيق ويُحفظ مرجع القالب',
                        NotifChannel.sms => 'غير مهيأة · تحتاج مزوّد رسائل يدعم اليمن، وهي أعلى حجية للتبليغ',
                        NotifChannel.email => 'غير مهيأة · تحتاج مزوّد بريد',
                        NotifChannel.whatsapp => 'غير مهيأة · تحتاج WhatsApp Business API',
                      },
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                    trailing: Text(ch == NotifChannel.app ? 'متصلة' : 'غير مهيأة',
                        style: TextStyle(color: ch == NotifChannel.app ? AppColors.success : AppColors.textMuted)),
                  ),
                ),
            ]),
            ListView(padding: const EdgeInsets.all(20), children: [
              for (final t in ops.templates)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    onTap: () => _edit(context, t),
                    leading: const Icon(Icons.article_rounded, color: AppColors.gold),
                    title: Text(t.event, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${t.subject}\nالإصدار ${t.version}${t.mandatory ? ' · إلزامي' : ''}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.6)),
                    isThreeLine: true,
                  ),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, MessageTemplate t) async {
    final ops = context.read<OperationsState>();
    final subject = TextEditingController(text: t.subject);
    final body = TextEditingController(text: t.body);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.navySurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final sample = {
            'company': 'شركة سبأ للتجارة',
            'amount': '\$3,500',
            'rule': 'سقف الصرف اللحظي للمدير',
            'limit': '> \$2,000',
            'payee': 'مورد الأجهزة',
          };
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('قالب: ${t.event}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                TextField(controller: subject, onChanged: (_) => set(() {}), decoration: const InputDecoration(labelText: 'العنوان')),
                const SizedBox(height: 10),
                TextField(controller: body, onChanged: (_) => set(() {}), maxLines: 4, decoration: const InputDecoration(labelText: 'النص')),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final e in MessageTemplate.variables.entries)
                    ActionChip(
                      label: Text(e.value),
                      onPressed: () => set(() => body.text = '${body.text} {${e.key}}'),
                    ),
                ]),
                const SizedBox(height: 12),
                const Text('معاينة بقيم نموذجية:', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700)),
                Text(
                  MessageTemplate(id: t.id, event: t.event, subject: subject.text, body: body.text).render(sample),
                  style: const TextStyle(color: AppColors.textSecondary, height: 1.7),
                ),
                const SizedBox(height: 6),
                const Text('تعديل القالب لا يغيّر نصوص الإشعارات المرسلة سابقاً.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    ops.updateTemplate(t, subject: subject.text.trim(), body: body.text.trim());
                    Navigator.pop(ctx);
                  },
                  child: const Text('حفظ إصدار جديد من القالب'),
                ),
              ]),
            ),
          );
        },
      ),
    );
    subject.dispose();
    body.dispose();
  }
}
