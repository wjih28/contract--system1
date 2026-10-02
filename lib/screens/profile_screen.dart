import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../design/components.dart';
import '../design/responsive.dart';
import '../design/state_view.dart';
import '../models/company.dart';
import '../providers/app_state.dart';
import '../providers/company_state.dart';
import '../services/backend.dart';
import '../theme/app_theme.dart';
import 'company/consent_requests_screen.dart';
import 'login_screen.dart';
import 'operations/notifications_center_screen.dart';
import 'phone_login_screen.dart';

final _dt = DateFormat('yyyy/MM/dd HH:mm');

/// P23: الملف الشخصي والأمان. البيانات المسموح بعرضها، والقنوات المؤكدة، وطرق التحقق،
/// والجهاز الحالي، وآخر الأحداث الأمنية. حقوق الشريك وتفضيلاته لا يغيّرها المسؤول دون موافقته.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final c = cs.current;
    final me = cs.me;
    final events = me == null
        ? const <AuditEvent>[]
        : cs.audit
            .where((e) => e.actorName == me.name && (e.objectType == 'security' || e.action.contains('توقيع') || e.objectType == 'permissions'))
            .take(8)
            .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('حسابي والأمان')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            GovCard(
              title: 'الملف الشخصي',
              icon: Icons.person_rounded,
              child: me == null
                  ? const Text('لا توجد عضوية في شركة بعد.', style: TextStyle(color: AppColors.textMuted))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(me.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text('${c?.legalName ?? ''} · ${me.roles.map((r) => r.label).join('، ')}'
                          '${me.isPartner ? ' · الحصة ${me.equity.toStringAsFixed(2)}%' : ''}',
                          style: const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      Text(
                        me.isPartner
                            ? 'اسمك وحصتك جزء من عقد الشركة: يتغيران بإصدار عقد جديد يقرّه الشركاء، لا من هنا.'
                            : 'بياناتك ودورك يضبطها مسؤول النظام وتُسجَّل تغييراتها في سجل التدقيق.',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.5),
                      ),
                    ]),
            ),
            const SizedBox(height: 12),
            GovCard(
              title: 'القنوات المؤكدة وطرق التحقق',
              icon: Icons.verified_user_rounded,
              child: Column(children: [
                _row(Icons.phone_iphone_rounded, 'الجوال', me?.phone.isNotEmpty == true ? me!.phone : '—',
                    Backend.user != null ? 'مؤكد برمز SMS' : 'وضع تجريبي محلي'),
                _row(Icons.alternate_email_rounded, 'البريد الإلكتروني', 'غير مضاف', 'يُضاف عند ربط مزوّد البريد'),
                FutureBuilder<bool>(
                  future: _biometric(),
                  builder: (_, s) => _row(Icons.fingerprint_rounded, 'تأكيد الإجراءات الحساسة',
                      s.data == true ? 'البصمة أو رمز الجهاز' : 'تأكيد يدوي', 'يُطلب عند التصويت والتوقيع والموافقات'),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            GovCard(
              title: 'الجلسة الحالية',
              icon: Icons.devices_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _row(Icons.computer_rounded, 'هذا الجهاز', kIsWeb ? 'متصفح الويب' : defaultTargetPlatform.name,
                    c?.lastSeen[me?.id] == null ? '' : 'آخر دخول ${_dt.format(DateTime.parse(c!.lastSeen[me!.id]!).toLocal())}'),
                const Text('عرض أجهزتك الأخرى وإنهاء جلساتها غير متاح من التطبيق حالياً. تسجيل الخروج ينهي هذه الجلسة.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.5)),
              ]),
            ),
            const SizedBox(height: 12),
            GovCard(
              title: 'آخر الأحداث الأمنية',
              icon: Icons.shield_rounded,
              child: AuditTimeline(events: events),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.tune_rounded, color: AppColors.gold),
              title: const Text('تفضيلات الإشعار'),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: c == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationPrefsScreen())),
            ),
            if (me?.isPartner ?? false)
              ListTile(
                leading: const Icon(Icons.privacy_tip_rounded, color: AppColors.gold),
                title: const Text('طلبات إتاحة بياناتي الشخصية'),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConsentRequestsScreen())),
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                context.read<AppState>().logout();
                await Backend.signOut(context);
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => Backend.ready ? const PhoneLoginScreen() : const LoginScreen()),
                  (route) => false,
                );
              },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('تسجيل الخروج'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger)),
            ),
            if (me == null && c != null) const StateView.denied(message: 'لا يوجد لك دور مفعّل في هذه الشركة.'),
          ],
        ),
      ),
    );
  }

  static Future<bool> _biometric() async {
    if (kIsWeb) return false;
    try {
      return await LocalAuthentication().isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Widget _row(IconData icon, String label, String value, String hint) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: AppColors.gold, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              Text(value, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
              if (hint.isNotEmpty) Text(hint, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
            ]),
          ),
        ]),
      );
}
