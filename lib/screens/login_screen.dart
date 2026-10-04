import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../services/account_service.dart';
import 'email_login_screen.dart';
import 'shell/app_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String? _error;
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  /// الدخول بالبريد وكلمة السر التي أنشأها مدير النظام (الوضع المحلي)
  void _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final (err, mustChange) = await AccountService.signIn(_emailCtrl.text, _passCtrl.text);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _loading = false;
        _error = err;
      });
      return;
    }
    context.read<AppState>().login(context.read<AppState>().partners.first);
    if (mustChange) {
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ChangePasswordScreen(email: _emailCtrl.text.trim().toLowerCase(), current: _passCtrl.text, firstLogin: true)));
      return;
    }
    await enterApp(context, _emailCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Center(child: MithaqLogo(size: 76)),
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  'مرحباً بك في ميثاق',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  'سجّل الدخول ببريدك المؤسسي الرسمي للمتابعة',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'البريد الإلكتروني المؤسسي',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'user@company-domain.com',
                  prefixIcon: Icon(
                    Icons.mail_outline_rounded,
                    color: AppColors.gold,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'كلمة المرور',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: '••••••••',
                  prefixIcon: const Icon(
                    Icons.lock_outline_rounded,
                    color: AppColors.gold,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.textMuted,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
                ),
              const SizedBox(height: 10),
              const Text(
                'يُنشئ مدير النظام حسابك بكلمة سر مبدئية، وتغيّرها عند أول دخول.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: _loading ? null : _login,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.navyDark,
                        ),
                      )
                    : const Text('تسجيل الدخول'),
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'اختر دوراً تجريبياً لعرض لوحته المخصصة',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Consumer<AppState>(
                builder: (context, appState, _) {
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: appState.partners.map((p) {
                      return _RoleChip(
                        partner: p,
                        onTap: () {
                          appState.login(p);
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => const AppShell(),
                            ),
                          );
                        },
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final Partner partner;
  final VoidCallback onTap;
  const _RoleChip({required this.partner, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.navySurface,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 11,
              backgroundColor: AppColors.gold.withValues(alpha: 0.2),
              child: Text(
                partner.avatarInitial,
                style: const TextStyle(color: AppColors.gold, fontSize: 11),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              partner.role.label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
