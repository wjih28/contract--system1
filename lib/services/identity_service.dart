import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../models/questionnaire.dart';
import '../theme/app_theme.dart';

/// تأكيد هوية الشريك قبل تسجيل صوته أو توقيعه.
/// يستخدم بصمة الجهاز عند توفرها، وإلا يطلب تأكيداً يدوياً صريحاً.
class IdentityService {
  IdentityService._();

  static final _auth = LocalAuthentication();

  static Future<ConfirmMethod?> confirm(
    BuildContext context, {
    required String partnerName,
    required String action,
  }) async {
    if (!kIsWeb) {
      try {
        final supported = await _auth.isDeviceSupported();
        if (supported) {
          final hasBio = await _auth.canCheckBiometrics;
          final ok = await _auth.authenticate(
            localizedReason: 'تأكيد هوية $partnerName: $action',
          );
          if (ok) {
            return hasBio ? ConfirmMethod.biometric : ConfirmMethod.deviceCredential;
          }
          return null;
        }
      } catch (e) {
        debugPrint('تعذر استخدام البصمة: $e');
      }
    }
    if (!context.mounted) return null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.fingerprint_rounded, color: AppColors.gold, size: 40),
        title: Text('تأكيد $partnerName', textAlign: TextAlign.center),
        content: Text(
          'البصمة غير متاحة على هذا الجهاز.\nبالضغط على "أؤكد" يقر $partnerName بأنه هو من يقوم بالإجراء التالي:\n$action',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('أؤكد'),
          ),
        ],
      ),
    );
    return ok == true ? ConfirmMethod.manual : null;
  }
}
