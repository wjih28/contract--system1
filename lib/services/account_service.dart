import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'backend.dart';
import 'phone.dart';

/// حسابات الدخول بالبريد الإلكتروني وكلمة السر.
/// ينشئها مدير النظام بكلمة سر مبدئية يسلّمها للشريك، ويُلزَم الشريك بتغييرها عند أول دخول.
/// كلمة السر لا تُخزَّن في سجل التدقيق ولا في بيانات الشركة.
///  - وضع الخادم: Firebase Authentication (مزوّد البريد وكلمة السر) ومستند accounts/{البريد}
///  - الوضع المحلي: بصمة SHA-256 لكلمة السر على الجهاز للتجربة فقط
class AccountService {
  AccountService._();

  static const _localKey = 'local_accounts_v1';

  /// كلمة سر مبدئية عشوائية من 10 خانات (بلا أحرف ملتبسة مثل 0 وO و1 وl)
  static String generatePassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(10, (_) => chars[r.nextInt(chars.length)]).join();
  }

  static String? validatePassword(String p) {
    if (p.length < 8) return 'كلمة السر 8 خانات على الأقل';
    if (!RegExp(r'[A-Za-z]').hasMatch(p) || !RegExp(r'\d').hasMatch(p)) return 'كلمة السر تحتاج حروفاً وأرقاماً';
    return null;
  }

  static String _hash(String email, String password) =>
      sha256.convert(utf8.encode('${email.trim().toLowerCase()}|$password')).toString();

  static String _docId(String email) => email.trim().toLowerCase();

  // ───────────── الإنشاء (مدير النظام) ─────────────

  /// إنشاء حساب بكلمة سر مبدئية. في وضع الخادم يُنشأ عبر تطبيق Firebase ثانوي حتى لا تتأثر جلسة المدير.
  /// يُرجع رسالة خطأ أو null عند النجاح.
  static Future<String?> createAccount(String email, String tempPassword, {required String createdBy}) async {
    final e = email.trim().toLowerCase();
    if (!isValidEmail(e)) return 'بريد إلكتروني غير صحيح';
    if (Backend.ready) {
      FirebaseApp? app;
      try {
        app = await Firebase.initializeApp(name: 'provisioning', options: DefaultFirebaseOptions.currentPlatform);
      } catch (_) {
        app = Firebase.app('provisioning');
      }
      try {
        final auth = FirebaseAuth.instanceFor(app: app);
        await auth.createUserWithEmailAndPassword(email: e, password: tempPassword);
        await auth.signOut();
      } on FirebaseAuthException catch (x) {
        return switch (x.code) {
          'email-already-in-use' => 'يوجد حساب بهذا البريد بالفعل',
          'operation-not-allowed' => 'الدخول بالبريد غير مفعّل في Firebase: فعّلوا مزوّد Email/Password من إعدادات Authentication',
          'weak-password' => 'كلمة السر ضعيفة',
          _ => 'تعذر إنشاء الحساب: ${x.message}',
        };
      }
      await FirebaseFirestore.instance.collection('accounts').doc(_docId(e)).set({
        'email': e,
        'mustChangePassword': true,
        'createdBy': createdBy,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return null;
    }
    final accounts = await _local();
    if (accounts.containsKey(e)) return 'يوجد حساب بهذا البريد بالفعل';
    accounts[e] = {'hash': _hash(e, tempPassword), 'mustChange': true};
    await _saveLocal(accounts);
    return null;
  }

  // ───────────── الدخول وتغيير كلمة السر ─────────────

  /// الدخول بالبريد وكلمة السر. يُرجع (خطأ، يلزم تغيير كلمة السر)
  static Future<(String?, bool)> signIn(String email, String password) async {
    final e = email.trim().toLowerCase();
    if (Backend.ready) {
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: e, password: password);
      } on FirebaseAuthException catch (x) {
        return (
          switch (x.code) {
            'invalid-credential' || 'wrong-password' || 'user-not-found' => 'البريد أو كلمة السر غير صحيحة',
            'too-many-requests' => 'محاولات كثيرة. انتظر قليلاً ثم أعد المحاولة',
            'operation-not-allowed' => 'الدخول بالبريد غير مفعّل في Firebase بعد',
            _ => 'تعذر الدخول: ${x.message}',
          },
          false
        );
      }
      final doc = await FirebaseFirestore.instance.collection('accounts').doc(_docId(e)).get();
      return (null, doc.data()?['mustChangePassword'] == true);
    }
    final a = (await _local())[e];
    if (a == null || a['hash'] != _hash(e, password)) return ('البريد أو كلمة السر غير صحيحة', false);
    return (null, a['mustChange'] == true);
  }

  /// تغيير كلمة السر: المبدئية لا تُستخدم بعد ذلك
  static Future<String?> changePassword(String email, String current, String next) async {
    final e = email.trim().toLowerCase();
    final err = validatePassword(next);
    if (err != null) return err;
    if (next == current) return 'اختر كلمة سر مختلفة عن المبدئية';
    if (Backend.ready) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return 'انتهت الجلسة، سجّل الدخول من جديد';
      try {
        await user.reauthenticateWithCredential(EmailAuthProvider.credential(email: e, password: current));
        await user.updatePassword(next);
      } on FirebaseAuthException catch (x) {
        return x.code == 'invalid-credential' || x.code == 'wrong-password' ? 'كلمة السر الحالية غير صحيحة' : 'تعذر التغيير: ${x.message}';
      }
      await FirebaseFirestore.instance
          .collection('accounts')
          .doc(_docId(e))
          .set({'mustChangePassword': false, 'changedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      return null;
    }
    final accounts = await _local();
    final a = accounts[e];
    if (a == null || a['hash'] != _hash(e, current)) return 'كلمة السر الحالية غير صحيحة';
    accounts[e] = {'hash': _hash(e, next), 'mustChange': false};
    await _saveLocal(accounts);
    return null;
  }

  /// إعادة تعيين كلمة السر: رابط من Firebase إلى بريد صاحب الحساب (لا يرى المدير كلمة السر الجديدة)
  static Future<String?> sendReset(String email) async {
    if (!Backend.ready) return 'في الوضع المحلي التجريبي: أنشئ الحساب من جديد';
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim().toLowerCase());
      return null;
    } on FirebaseAuthException catch (x) {
      return 'تعذر الإرسال: ${x.message}';
    }
  }

  /// هل ما زال الحساب بكلمة السر المبدئية؟
  static Future<bool> mustChange(String email) async {
    try {
      final d = await FirebaseFirestore.instance.collection('accounts').doc(_docId(email)).get();
      return d.data()?['mustChangePassword'] == true;
    } catch (_) {
      return false;
    }
  }

  /// هل للبريد حساب دخول؟ (للعرض في شاشة المستخدمين)
  static Future<bool> hasAccount(String email) async {
    final e = email.trim().toLowerCase();
    if (e.isEmpty) return false;
    if (Backend.ready) {
      try {
        return (await FirebaseFirestore.instance.collection('accounts').doc(_docId(e)).get()).exists;
      } catch (_) {
        return false;
      }
    }
    return (await _local()).containsKey(e);
  }

  static Future<Map<String, Map<String, dynamic>>> _local() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_localKey);
      if (raw == null) return {};
      return (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
    } catch (e) {
      debugPrint('تعذر قراءة الحسابات المحلية: $e');
      return {};
    }
  }

  static Future<void> _saveLocal(Map<String, Map<String, dynamic>> a) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localKey, jsonEncode(a));
  }
}
