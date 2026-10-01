import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/company.dart';
import '../models/questionnaire.dart';
import '../services/phone.dart';

/// حالة الشركات: الشركات التي ينتمي إليها المستخدم، والشركة الحالية،
/// والبوابة الحالية، وسجل التدقيق. تعمل محلياً أو مع Firestore.
class CompanyState extends ChangeNotifier {
  static const _companiesKey = 'companies_v1';
  static const _auditKey = 'audit_v1';
  static const _currentKey = 'current_company_v1';

  List<Company> companies = [];
  String? currentId;
  Portal? _portal;
  bool loaded = false;

  /// هوية المستخدم: رقم الجوال في وضع الخادم، أو هوية تجريبية محلياً
  String? myPhone;
  String myUid = 'local';
  String myName = 'أنا';

  // سجل التدقيق محلياً: لكل شركة قائمة أحداث (الأحدث أولاً)
  final Map<String, List<AuditEvent>> _localAudit = {};
  List<AuditEvent> _cloudAudit = [];

  FirebaseFirestore? _db;
  StreamSubscription? _companiesSub;
  StreamSubscription? _auditSub;

  bool get isCloud => _db != null;

  Company? get current => companies.where((c) => c.id == currentId).firstOrNull ??
      (companies.isEmpty ? null : companies.first);

  CompanyMember? get me => current?.memberByPhone(myPhone) ??
      (isCloud ? null : current?.members.firstOrNull);

  Set<CompanyRole> get myRoles => me?.roles ?? {};

  List<Portal> get myPortals => Permissions.portalsFor(myRoles);

  Portal get portal {
    final ps = myPortals;
    if (_portal != null && ps.contains(_portal)) return _portal!;
    return ps.isEmpty ? Portal.partner : ps.first;
  }

  set portal(Portal p) {
    _portal = p;
    notifyListeners();
  }

  /// الوحدات الظاهرة في القائمة: حسب الدور والبوابة الحالية
  List<AppModule> get myModules {
    final allowed = Permissions.modulesFor(myRoles);
    return AppModule.values.where((m) => allowed.contains(m) && (m.portal == portal || m.shared)).toList();
  }

  bool can(AppModule m) => Permissions.can(myRoles, m);

  List<AuditEvent> get audit => isCloud ? _cloudAudit : (_localAudit[current?.id] ?? const []);

  // ───────────── التحميل والحفظ ─────────────

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      currentId = prefs.getString(_currentKey);
      if (!isCloud) {
        final raw = prefs.getString(_companiesKey);
        if (raw != null) {
          companies = (jsonDecode(raw) as List)
              .map((e) => Company.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
        }
        final a = prefs.getString(_auditKey);
        if (a != null) {
          (jsonDecode(a) as Map<String, dynamic>).forEach((k, v) {
            _localAudit[k] = (v as List).map((e) => AuditEvent.fromJson(Map<String, dynamic>.from(e as Map))).toList();
          });
        }
      }
    } catch (e) {
      debugPrint('تعذر تحميل الشركات: $e');
    }
    if (!isCloud) loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (currentId != null) await prefs.setString(_currentKey, currentId!);
      if (isCloud) return;
      await prefs.setString(_companiesKey, jsonEncode(companies.map((c) => c.toJson()).toList()));
      await prefs.setString(
        _auditKey,
        jsonEncode(_localAudit.map((k, v) => MapEntry(k, v.map((e) => e.toJson()).toList()))),
      );
    } catch (e) {
      debugPrint('تعذر حفظ الشركات: $e');
    }
  }

  // ───────────── وضع الخادم ─────────────

  Future<void> attachCloud(FirebaseFirestore db, {required String phone, required String uid, String? name}) async {
    await detachCloud();
    _db = db;
    myPhone = phone;
    myUid = uid;
    myName = name ?? phone;
    companies = [];
    loaded = false;
    notifyListeners();
    _companiesSub = db.collection('companies').where('memberPhones', arrayContains: phone).snapshots().listen(
      (snap) {
        companies = snap.docs.map((d) => Company.fromJson({...d.data(), 'id': d.id})).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        loaded = true;
        _watchAudit();
        notifyListeners();
      },
      onError: (Object e) {
        debugPrint('تعذر قراءة الشركات: $e');
        loaded = true;
        notifyListeners();
      },
    );
  }

  Future<void> detachCloud() async {
    await _companiesSub?.cancel();
    await _auditSub?.cancel();
    _companiesSub = null;
    _auditSub = null;
    _db = null;
    _cloudAudit = [];
    _watchedAuditFor = null;
  }

  String? _watchedAuditFor;

  void _watchAudit() {
    final c = current;
    if (_db == null || c == null || _watchedAuditFor == c.id) return;
    _watchedAuditFor = c.id;
    _auditSub?.cancel();
    _auditSub = _db!
        .collection('companies')
        .doc(c.id)
        .collection('audit')
        .orderBy('at', descending: true)
        .limit(300)
        .snapshots()
        .listen((snap) {
      _cloudAudit = snap.docs.map((d) {
        final data = d.data();
        final at = data['at'];
        return AuditEvent.fromJson({
          ...data,
          'id': d.id,
          'at': at is Timestamp ? at.toDate().toIso8601String() : DateTime.now().toIso8601String(),
        });
      }).toList();
      notifyListeners();
    }, onError: (Object e) => debugPrint('تعذر قراءة سجل التدقيق: $e'));
  }

  void select(String id) {
    currentId = id;
    _portal = null;
    _watchAudit();
    notifyListeners();
    _persist();
  }

  // ───────────── الشركات ─────────────

  /// إنشاء شركة جديدة بشركائها وحصصهم (بداية رحلة التأسيس)
  Company createCompany({
    required String legalName,
    required String companyType,
    required AppCurrency currency,
    required double capital,
    required List<CompanyMember> members,
  }) {
    final now = DateTime.now();
    final c = Company(
      id: 'C${now.millisecondsSinceEpoch}',
      legalName: legalName,
      companyType: companyType,
      currency: currency,
      capital: capital,
      members: [
        for (var i = 0; i < members.length; i++)
          CompanyMember(
            id: members[i].id,
            name: members[i].name,
            phone: members[i].phone.isEmpty ? '' : normalizePhone(members[i].phone),
            nationalId: members[i].nationalId,
            // منشئ الشركة يحصل على دور مسؤول النظام لضبط الإعدادات (يُدار لاحقاً من شاشة الصلاحيات)
            roles: {
              ...members[i].roles,
              if (_isCreator(members[i], i)) CompanyRole.systemAdmin,
            },
            equity: members[i].equity,
          ),
      ],
      createdAt: now,
      createdBy: myUid,
    );
    companies.insert(0, c);
    currentId = c.id;
    _db?.collection('companies').doc(c.id).set(c.toJson()).then(
          (_) {},
          onError: (Object e) => debugPrint('تعذر إنشاء الشركة في الخادم: $e'),
        );
    log(c.id, action: 'إنشاء الشركة "${c.legalName}"', objectType: 'company', objectId: c.id,
        result: '${c.partners.length} شركاء، رأس المال ${c.capital.toStringAsFixed(0)} ${c.currency.code}');
    _watchAudit();
    notifyListeners();
    _persist();
    return c;
  }

  /// بعد اعتماد العقد: تصبح الشركة نشطة ويُسجَّل رقم إصدار العقد
  void setContractVersion(String companyId, int version) {
    final c = companies.where((x) => x.id == companyId).firstOrNull;
    if (c == null) return;
    c.contractVersion = version;
    c.status = CompanyStatus.active;
    _db?.collection('companies').doc(companyId).update({'contractVersion': version, 'status': c.status.name}).then(
          (_) {},
          onError: (Object e) => debugPrint('تعذر تحديث إصدار العقد: $e'),
        );
    notifyListeners();
    _persist();
  }

  bool _isCreator(CompanyMember m, int index) =>
      isCloud ? (m.phone.isNotEmpty && normalizePhone(m.phone) == myPhone) : index == 0;

  /// A11: تعديل إعدادات التصويت للشركة؛ تسري على الجلسات الجديدة فقط
  void updateVotingSettings(String companyId, VotingSettings v) {
    final c = companies.where((x) => x.id == companyId).firstOrNull;
    if (c == null) return;
    c.votingSettings = v;
    _db?.collection('companies').doc(companyId).update({'votingSettings': v.toJson()}).then(
          (_) {},
          onError: (Object e) => debugPrint('تعذر حفظ إعدادات التصويت: $e'),
        );
    log(companyId,
        action: 'تعديل إعدادات التصويت',
        objectType: 'settings',
        objectId: 'voting',
        result: 'النصاب ${v.quorum}%، المهلة ${v.deadlineDays} أيام، الجمود بعد ${v.deadlockAfter} جولات');
    notifyListeners();
    _persist();
  }

  // ───────────── سجل التدقيق ─────────────

  /// تسجيل حدث تدقيق. السجل للإضافة فقط: لا توجد دالة تعديل أو حذف.
  void log(
    String companyId, {
    required String action,
    required String objectType,
    required String objectId,
    String result = '',
    String? evidenceRef,
    ActorType actorType = ActorType.user,
    String? actorName,
  }) {
    final company = companies.where((c) => c.id == companyId).firstOrNull;
    final e = AuditEvent(
      id: 'E${DateTime.now().microsecondsSinceEpoch}',
      companyId: companyId,
      at: DateTime.now(),
      actorType: actorType,
      actorId: actorType == ActorType.user ? myUid : actorType.name,
      actorName: actorName ??
          (actorType == ActorType.user
              ? ((company?.memberByPhone(myPhone) ?? (isCloud ? null : company?.members.firstOrNull))?.name ?? myName)
              : ''),
      action: action,
      objectType: objectType,
      objectId: objectId,
      result: result,
      evidenceRef: evidenceRef,
    );
    if (isCloud) {
      _cloudAudit = [e, ..._cloudAudit];
      _db!.collection('companies').doc(companyId).collection('audit').add({
        ...e.toJson(),
        'actorPhone': myPhone,
        'at': FieldValue.serverTimestamp(),
      }).then((_) {}, onError: (Object err) => debugPrint('تعذر تسجيل حدث التدقيق: $err'));
    } else {
      _localAudit.putIfAbsent(companyId, () => []).insert(0, e);
      _persist();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    detachCloud();
    super.dispose();
  }
}
