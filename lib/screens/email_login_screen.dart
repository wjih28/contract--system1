import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/company_state.dart';
import '../services/account_service.dart';
import '../services/backend.dart';
import '../services/phone.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'shell/app_shell.dart';

/// الدخول بالبريد الإلكتروني وكلمة السر التي سلّمها مدير النظام.
/// عند أول دخول يُلزَم الشريك بتغيير كلمة السر المبدئية قبل أي وصول.
class EmailLoginScreen extends StatefulWidget {
  const EmailLoginScreen({super.key});

  @override
  State<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends State<EmailLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!isValidEmail(_email.text) || _password.text.isEmpty) {
      setState(() => _error = 'أدخل البريد الإلكتروني وكلمة السر');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final (err, mustChange) = await AccountService.signIn(_email.text, _password.text);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    if (mustChange) {
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ChangePasswordScreen(email: _email.text.trim().toLowerCase(), current: _password.text, firstLogin: true)));
      return;
    }
    await enterApp(context, _email.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الدخول بالبريد الإلكتروني')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                const Center(child: MithaqLogo(size: 64)),
                const SizedBox(height: 16),
                const Text('ادخل بالبريد وكلمة السر التي سلّمها لك مدير النظام.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, height: 1.6)),
                const SizedBox(height: 20),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'البريد الإلكتروني', prefixIcon: Icon(Icons.alternate_email_rounded)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  textDirection: TextDirection.ltr,
                  onSubmitted: (_) => _signIn(),
                  decoration: InputDecoration(
                    labelText: 'كلمة السر',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
                  ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: _busy ? null : _signIn,
                  child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('دخول'),
                ),
                const SizedBox(height: 10),
                const Text('نسيت كلمة السر؟ اطلب من مدير النظام إعادة إصدار كلمة سر مبدئية.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// دخول التطبيق بعد التحقق: ربط الخادم بهوية البريد، أو تعيين الهوية محلياً
Future<void> enterApp(BuildContext context, String email) async {
  final user = Backend.user;
  if (user != null) {
    await Backend.attach(context, user);
  } else {
    context.read<CompanyState>().myPhone = emailKey(email);
  }
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AppShell()), (_) => false);
}

/// تغيير كلمة السر: إلزامي عند أول دخول بكلمة السر المبدئية، ومتاح لاحقاً من الملف الشخصي
class ChangePasswordScreen extends StatefulWidget {
  final String email;
  final String? current;
  final bool firstLogin;
  const ChangePasswordScreen({super.key, required this.email, this.current, this.firstLogin = false});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  late final _current = TextEditingController(text: widget.current ?? '');
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_next.text != _confirm.text) {
      setState(() => _error = 'كلمتا السر غير متطابقتين');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await AccountService.changePassword(widget.email, _current.text, _next.text);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    if (widget.firstLogin) {
      await enterApp(context, widget.email);
    } else {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تغيير كلمة السر.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تغيير كلمة السر'),
        automaticallyImplyLeading: !widget.firstLogin,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                if (widget.firstLogin)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                    ),
                    child: const Text(
                      'هذا أول دخول لك بكلمة سر مبدئية سلّمها مدير النظام. اختر كلمة سر جديدة خاصة بك؛ لن يعرفها أحد غيرك، ولن تعمل المبدئية بعدها.',
                      style: TextStyle(height: 1.6),
                    ),
                  ),
                Text(widget.email, textDirection: TextDirection.ltr, textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 16),
                if (!widget.firstLogin)
                  TextField(
                    controller: _current,
                    obscureText: true,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(labelText: 'كلمة السر الحالية', prefixIcon: Icon(Icons.lock_clock_rounded)),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _next,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                      labelText: 'كلمة السر الجديدة', helperText: '8 خانات على الأقل، حروف وأرقام', prefixIcon: Icon(Icons.lock_reset_rounded)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirm,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  onSubmitted: (_) => _save(),
                  decoration: const InputDecoration(labelText: 'تأكيد كلمة السر الجديدة', prefixIcon: Icon(Icons.lock_rounded)),
                ),
                if (_error != null)
                  Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: AppColors.danger))),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('حفظ كلمة السر الجديدة'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
