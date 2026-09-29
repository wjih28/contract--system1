// ملف مؤقت: يُستبدل تلقائياً عند تشغيل
//   flutterfire configure --project=smart-contract-system
// وحتى ذلك الحين يعمل التطبيق في الوضع المحلي (جهاز واحد).
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform =>
      throw UnsupportedError('Firebase غير مهيأ بعد لهذا التطبيق');
}
