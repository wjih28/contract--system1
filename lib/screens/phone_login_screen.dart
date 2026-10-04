import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/backend.dart';
import '../services/phone.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'email_login_screen.dart';
import 'shell/app_shell.dart';

/// الدخول برقم الجوال وكود SMS: رقم الجوال هو هوية الشريك في التصويت والتوقيع
class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  // الجوال: معرّف التحقق؛ الويب: نتيجة التأكيد
  String? _verificationId;
  ConfirmationResult? _webConfirmation;

  bool get _codeSent => _verificationId != null || _webConfirmation != null;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = normalizePhone(_phone.text);
    if (phone.length < 10) {
      setState(() => _error = 'أدخل رقم جوال صحيح');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = FirebaseAuth.instance;
    try {
      if (kIsWeb) {
        _webConfirmation = await auth.signInWithPhoneNumber(phone);
        setState(() => _busy = false);
      } else {
        await auth.verifyPhoneNumber(
          phoneNumber: phone,
          verificationCompleted: (cred) async {
            // أندرويد قد يقرأ الكود تلقائياً
            final r = await auth.signInWithCredential(cred);
            if (r.user != null) await _done(r.user!);
          },
          verificationFailed: (e) => setState(() {
            _busy = false;
            _error = _message(e);
          }),
          codeSent: (id, _) => setState(() {
            _verificationId = id;
            _busy = false;
          }),
          codeAutoRetrievalTimeout: (_) {},
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _busy = false;
        _error = _message(e);
      });
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length < 6) {
      setState(() => _error = 'أدخل الكود المكون من 6 أرقام');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final UserCredential r;
      if (_webConfirmation != null) {
        r = await _webConfirmation!.confirm(code);
      } else {
        r = await FirebaseAuth.instance.signInWithCredential(
          PhoneAuthProvider.credential(verificationId: _verificationId!, smsCode: code),
        );
      }
      if (r.user != null) await _done(r.user!);
    } on FirebaseAuthException catch (e) {
      setState(() {
        _busy = false;
        _error = _message(e);
      });
    }
  }

  Future<void> _done(User user) async {
    if (!mounted) return;
    await Backend.attach(context, user);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AppShell()));
  }

  String _message(FirebaseAuthException e) => switch (e.code) {
        'invalid-phone-number' => 'رقم الجوال غير صحيح',
        'invalid-verification-code' => 'الكود غير صحيح',
        'too-many-requests' => 'محاولات كثيرة، حاول لاحقاً',
        // سياسة المناطق في Firebase تمنع إرسال SMS لهذه الدولة
        'operation-not-allowed' when (e.message ?? '').contains('region') =>
          'إرسال الرسائل لهذه الدولة غير مفعّل بعد في إعدادات Firebase',
        'session-expired' => 'انتهت صلاحية الكود، اطلب كوداً جديداً',
        _ => 'تعذر التحقق: ${e.message ?? e.code}',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          children: [
            const Center(child: MithaqLogo(size: 84)),
            const SizedBox(height: 22),
            const Text('الدخول إلى ميثاق',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(
              _codeSent
                  ? 'أرسلنا كود التحقق إلى ${normalizePhone(_phone.text)}'
                  : 'رقم جوالك هو هويتك في التصويت والتوقيع على العقد، وعليه تصلك الإشعارات الرسمية',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.7),
            ),
            const SizedBox(height: 30),
            if (!_codeSent)
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'رقم الجوال',
                  hintText: '+967 7XX XXX XXX',
                  prefixIcon: Icon(Icons.phone_iphone_rounded),
                ),
                onSubmitted: (_) => _sendCode(),
              )
            else
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                enabled: !_busy,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 22, letterSpacing: 10, fontWeight: FontWeight.w800),
                decoration: const InputDecoration(labelText: 'كود التحقق', counterText: ''),
                onSubmitted: (_) => _verify(),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
            ],
            const SizedBox(height: 22),
            ElevatedButton(
              onPressed: _busy ? null : (_codeSent ? _verify : _sendCode),
              child: _busy
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(_codeSent ? 'تأكيد الدخول' : 'إرسال كود التحقق'),
            ),
            if (_codeSent)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _verificationId = null;
                          _webConfirmation = null;
                          _code.clear();
                        }),
                child: const Text('تغيير الرقم'),
              ),
            const SizedBox(height: 16),
            // الشريك الذي أنشأ له مدير النظام حساباً بالبريد وكلمة سر مبدئية
            OutlinedButton.icon(
              onPressed: _busy ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmailLoginScreen())),
              icon: const Icon(Icons.alternate_email_rounded),
              label: const Text('الدخول بالبريد الإلكتروني'),
            ),
          ],
        ),
      ),
    );
  }
}
