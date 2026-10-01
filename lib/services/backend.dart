import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../firebase_options.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../providers/company_state.dart';
import '../providers/contract_state.dart';
import 'cloud_sync.dart';

/// تهيئة Firebase وربط الحالة بالمستخدم المسجل.
/// إذا لم يُهيأ Firebase بعد يعمل التطبيق في الوضع المحلي على جهاز واحد.
class Backend {
  Backend._();

  static bool ready = false;

  /// تشغيل تجريبي بدون خادم: flutter run --dart-define=LOCAL_MODE=true
  static const localMode = bool.fromEnvironment('LOCAL_MODE');

  static Future<void> init() async {
    if (localMode) return;
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      ready = true;
    } catch (e) {
      debugPrint('Firebase غير مهيأ، التشغيل في الوضع المحلي: $e');
    }
  }

  static User? get user => ready ? FirebaseAuth.instance.currentUser : null;

  /// بعد الدخول برقم الجوال: ربط الجلسات بالخادم وتسجيل المستخدم في التطبيق
  static Future<void> attach(BuildContext context, User user) async {
    final phone = user.phoneNumber ?? '';
    context.read<AppState>().login(Partner(
          id: user.uid,
          fullName: 'شريك $phone',
          officialEmail: user.email ?? '',
          phoneNumber: phone,
          equityPercentage: 0,
          role: UserRole.investorPartner,
          avatarInitial: 'ش',
        ));
    final companies = context.read<CompanyState>();
    await context
        .read<ContractState>()
        .attachCloud(CloudSync(FirebaseFirestore.instance), phone: phone, uid: user.uid);
    await companies.attachCloud(FirebaseFirestore.instance, phone: phone, uid: user.uid);
  }

  static Future<void> signOut(BuildContext context) async {
    final companies = context.read<CompanyState>();
    await context.read<ContractState>().detachCloud();
    await companies.detachCloud();
    if (ready) await FirebaseAuth.instance.signOut();
  }
}
