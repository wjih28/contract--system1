import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../services/backend.dart';
import 'login_screen.dart';
import 'phone_login_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final user = appState.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('حسابي')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: AppColors.gold.withValues(alpha: 0.15),
                    child: Text(
                      user?.avatarInitial ?? '؟',
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user?.fullName ?? 'مستخدم',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  StatusChip(
                    label: user?.role.label ?? '',
                    color: AppColors.gold,
                    icon: Icons.badge_rounded,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            GoldBorderCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _infoRow(Icons.mail_outline_rounded, 'البريد الرسمي', user?.officialEmail ?? '-'),
                  const Divider(height: 24),
                  _infoRow(Icons.phone_outlined, 'رقم الهاتف', user?.phoneNumber ?? '-'),
                  const Divider(height: 24),
                  _infoRow(
                    Icons.pie_chart_outline_rounded,
                    'نسبة الحصة',
                    '${(user?.equityPercentage ?? 0).toStringAsFixed(0)}%',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SectionHeader(title: 'قنوات الإشعار المفضلة'),
            const SizedBox(height: 12),
            GoldBorderCard(
              child: Column(
                children: [
                  _channelSwitch('البريد الإلكتروني المؤسسي', Icons.mark_email_read_rounded, true),
                  const Divider(height: 20),
                  _channelSwitch('واتساب التفاعلي', Icons.chat_rounded, true),
                  const Divider(height: 20),
                  _channelSwitch('الرسائل النصية SMS', Icons.sms_rounded, false),
                ],
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () async {
                appState.logout();
                await Backend.signOut(context);
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => Backend.ready ? const PhoneLoginScreen() : const LoginScreen(),
                  ),
                  (route) => false,
                );
              },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('تسجيل الخروج'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'ميثاق • الإصدار 1.0.0',
                style: TextStyle(
                  color: AppColors.textMuted.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppColors.gold, size: 18),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _channelSwitch(String label, IconData icon, bool value) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool v = value;
        return Row(
          children: [
            Icon(icon, color: AppColors.gold, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              ),
            ),
            Switch(
              value: v,
              activeThumbColor: AppColors.gold,
              onChanged: (nv) => setState(() => v = nv),
            ),
          ],
        );
      },
    );
  }
}
