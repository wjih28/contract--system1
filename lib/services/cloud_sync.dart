import 'package:cloud_firestore/cloud_firestore.dart';

/// طبقة الاتصال بـ Firestore. البنية:
///   sessions/{sid}                     بيانات الجلسة والبنود وأرقام الأعضاء
///   sessions/{sid}/votes/{key__pid}    صوت كل شريك، يكتبه الشريك من جواله فقط
///   sessions/{sid}/signoffs/{pid}      التوقيع النهائي لكل شريك
/// قواعد الأمان في firestore.rules.
class CloudSync {
  CloudSync(this.db);

  final FirebaseFirestore db;

  CollectionReference<Map<String, dynamic>> get _sessions => db.collection('sessions');

  Stream<QuerySnapshot<Map<String, dynamic>>> mySessions(String phone) =>
      _sessions.where('memberPhones', arrayContains: phone).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> votes(String sid) =>
      _sessions.doc(sid).collection('votes').snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> signoffs(String sid) =>
      _sessions.doc(sid).collection('signoffs').snapshots();

  Future<void> create(String sid, Map<String, dynamic> data) =>
      _sessions.doc(sid).set(data);

  Future<void> update(String sid, Map<Object, Object?> fields) =>
      _sessions.doc(sid).update({...fields, 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> delete(String sid) => _sessions.doc(sid).delete();

  Future<void> vote({
    required String sid,
    required String recordKey,
    required String partnerId,
    required int round,
    required String ballot,
    required String method,
    required String phone,
  }) =>
      _sessions.doc(sid).collection('votes').doc('${recordKey}__$partnerId').set({
        'recordKey': recordKey,
        'partnerId': partnerId,
        'round': round,
        'ballot': ballot,
        'method': method,
        'phone': phone,
        'at': FieldValue.serverTimestamp(),
      });

  Future<void> signOff({
    required String sid,
    required String partnerId,
    required String signaturePng,
    required String method,
    required String phone,
  }) =>
      _sessions.doc(sid).collection('signoffs').doc(partnerId).set({
        'signaturePng': signaturePng,
        'method': method,
        'phone': phone,
        'at': FieldValue.serverTimestamp(),
      });
}

/// تحويل الطابع الزمني القادم من الخادم (أو المقدّر قبل وصوله) إلى DateTime
DateTime remoteTime(Object? v) {
  if (v is Timestamp) return v.toDate();
  if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
  return DateTime.now();
}
