import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/company.dart';
import '../../providers/company_state.dart';
import '../../services/account_service.dart';
import '../../services/phone.dart';
import '../../theme/app_theme.dart';

/// إنشاء حسابات الدخول بالبريد لأعضاء الشركة بكلمات سر مبدئية، ثم عرضها لمدير النظام مرة واحدة
/// ليسلّمها لأصحابها. لا تُحفظ كلمات السر في السجل ولا في بيانات الشركة.
Future<void> provisionAccounts(BuildContext context, Company c, List<CompanyMember> members) async {
  final cs = context.read<CompanyState>();
  final results = <(CompanyMember, String?, String?)>[]; // العضو، كلمة السر، الخطأ
  for (final m in members) {
    final email = c.emailOf(m);
    if (!isValidEmail(email)) continue;
    final pass = AccountService.generatePassword();
    final err = await AccountService.createAccount(email, pass, createdBy: cs.myUid);
    results.add((m, err == null ? pass : null, err));
    cs.log(c.id,
        action: err == null ? 'إنشاء حساب دخول بالبريد لـ${m.name}' : 'تعذر إنشاء حساب دخول لـ${m.name}',
        objectType: 'users',
        objectId: m.id,
        result: err ?? 'بكلمة سر مبدئية يغيّرها عند أول دخول',
        evidenceRef: email);
  }
  if (results.isEmpty || !context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.navySurface,
      title: const Text('كلمات السر المبدئية'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text(
            'سلّم كل شريك بريده وكلمة سره المبدئية بنفسك. تظهر الآن مرة واحدة فقط، ويُلزَم كل شريك بتغييرها عند أول دخول.',
            style: TextStyle(color: AppColors.warning, fontSize: 12.5, height: 1.6),
          ),
          const SizedBox(height: 10),
          for (final (m, pass, err) in results)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: SelectableText(
                  err ?? '${c.emailOf(m)}\nكلمة السر: $pass',
                  style: TextStyle(color: err == null ? AppColors.textSecondary : AppColors.danger, fontSize: 12.5, height: 1.6),
                ),
                trailing: pass == null
                    ? null
                    : IconButton(
                        tooltip: 'نسخ',
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        onPressed: () => Clipboard.setData(ClipboardData(text: '${c.emailOf(m)}\n$pass')),
                      ),
              ),
            ),
        ]),
      ),
      actions: [ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('سلّمتها، إغلاق'))],
    ),
  );
}
