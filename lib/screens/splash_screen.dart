import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../services/backend.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/account_service.dart';
import 'email_login_screen.dart';
import 'login_screen.dart';
import 'shell/app_shell.dart';
import 'phone_login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    Future.delayed(const Duration(milliseconds: 1800), () async {
      // وضع الخادم: دخول برقم الجوال، ومن سجّل سابقاً يدخل مباشرة
      Widget next = const LoginScreen();
      if (Backend.ready) {
        final user = Backend.user;
        if (user == null) {
          next = const PhoneLoginScreen();
        } else if (user.phoneNumber == null && user.email != null && await AccountService.mustChange(user.email!)) {
          // لم يغيّر كلمة السر المبدئية بعد: يعود للدخول ثم التغيير الإلزامي
          await FirebaseAuth.instance.signOut();
          next = const EmailLoginScreen();
        } else {
          if (!mounted) return;
          await Backend.attach(context, user);
          next = const AppShell();
        }
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 500),
            pageBuilder: (_, __, ___) => next,
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.navyGradient),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: GeometricCornerPainter()),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ScaleTransition(
                    scale: CurvedAnimation(
                      parent: _controller,
                      curve: Curves.easeOutBack,
                    ),
                    child: const MithaqLogo(size: 100),
                  ),
                  const SizedBox(height: 24),
                  FadeTransition(
                    opacity: _controller,
                    child: const Text(
                      'ميثاق',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FadeTransition(
                    opacity: _controller,
                    child: const Text(
                      'المحامي والمراقب المالي المؤتمت',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.gold.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
