import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/admin.dart';
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
  StreamSubscription? _consentSub;
  final Map<String, Map<String, Map<String, String>>> _consentCache = {};

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
    final allowed = Permissions.effectiveModules(myRoles, current);
    // وحدات البوابة أولاً ثم الوحدات المشتركة (الإشعارات، السجل، الحساب)
    final list = AppModule.values.where((m) => allowed.contains(m) && (m.portal == portal || m.shared)).toList();
    return [...list.where((m) => m.portal == portal && !m.shared), ...list.where((m) => !(m.portal == portal && !m.shared))];
  }

  bool can(AppModule m) => Permissions.effectiveModules(myRoles, current).contains(m);

  /// صلاحية إجراء محدد على وحدة (A04)
  bool canDo(AppModule m, PermAction a) => Permissions.actions(myRoles, m, current).contains(a);

  /// صلاحية نقطة إفصاح (A05)
  bool canSee(String pointId, [PermAction a = PermAction.view]) =>
      Permissions.pointActions(myRoles, pointId, current).contains(a);

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
        for (final c in companies) {
          final cached = _consentCache[c.id];
          if (cached != null) c.consents = cached;
        }
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
    await _consentSub?.cancel();
    _consentSub = null;
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
    // موافقات الشركاء: مستند لكل موافقة يكتبه الشريك من جواله فقط (قواعد الأمان)
    _consentSub?.cancel();
    _consentSub = _db!.collection('companies').doc(c.id).collection('consents').snapshots().listen((snap) {
      final map = <String, Map<String, String>>{};
      for (final d in snap.docs) {
        final x = d.data();
        map.putIfAbsent('${x['point']}|${x['role']}', () => {})[x['memberId'] as String] = '${x['at']}';
      }
      c.consents = map;
      _consentCache[c.id] = map;
      notifyListeners();
    }, onError: (Object e) => debugPrint('تعذر قراءة الموافقات: $e'));
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

  /// بعد اعتماد إصدار جديد: رقم الإصدار، وجدول الحصص إن تغيّر (لا يتغير إلا عبر إصدار معتمد)
  void applyVersion(String companyId, int version, {Map<String, double>? equity}) {
    final c = companies.where((x) => x.id == companyId).firstOrNull;
    if (c == null) return;
    c.contractVersion = version;
    if (c.status == CompanyStatus.establishment) c.status = CompanyStatus.active;
    final changed = equity != null && c.members.any((m) => equity.containsKey(m.id) && equity[m.id] != m.equity);
    if (changed) {
      c.members = [for (final m in c.members) m.copyWith(equity: equity[m.id] ?? m.equity)];
    }
    _db?.collection('companies').doc(companyId).update({
      'contractVersion': version,
      'status': c.status.name,
      if (changed) 'members': c.members.where((m) => !m.staff).map((m) => m.toJson()).toList(),
    }).then((_) {}, onError: (Object e) => debugPrint('تعذر تحديث إصدار العقد: $e'));
    if (changed) {
      log(companyId,
          action: 'تحديث جدول الحصص من الإصدار $version',
          objectType: 'company',
          objectId: companyId,
          result: c.partners.map((m) => '${m.name} ${m.equity.toStringAsFixed(2)}%').join('، '),
          actorType: ActorType.system);
    }
    notifyListeners();
    _persist();
  }

  /// التصفية (المرحلة 5 من مسار النزاع): تتحول الشركة إلى قيد التصفية ثم تُؤرشف
  void setStatus(String companyId, CompanyStatus status) {
    final c = companies.where((x) => x.id == companyId).firstOrNull;
    if (c == null || c.status == status) return;
    c.status = status;
    _db?.collection('companies').doc(companyId).update({'status': status.name}).then(
          (_) {},
          onError: (Object e) => debugPrint('تعذر تحديث حالة الشركة: $e'),
        );
    log(companyId, action: 'تغيير حالة الشركة', objectType: 'company', objectId: companyId, result: status.label);
    notifyListeners();
    _persist();
  }

  // ───────────── الإدارة (المرحلة 4) ─────────────

  Company? _company(String id) => companies.where((x) => x.id == id).firstOrNull;

  void _update(Company c, Map<String, Object?> fields) {
    _db?.collection('companies').doc(c.id).update(fields).then(
          (_) {},
          onError: (Object e) => debugPrint('تعذر حفظ إعدادات الشركة: $e'),
        );
    notifyListeners();
    _persist();
  }

  /// A03: دعوة موظف بلا حصص برقم جواله. الشركاء وحصصهم لا يتغيرون إلا بإصدار عقد.
  String? inviteStaff(String companyId, {required String name, required String phone, required CompanyRole role}) {
    final c = _company(companyId);
    if (c == null) return 'الشركة غير موجودة';
    if (role.isPartner) return 'الشريك يُضاف بإصدار عقد جديد، لا بالدعوة';
    final p = normalizePhone(phone);
    if (name.trim().isEmpty || p.length < 9) return 'أدخل الاسم ورقم جوال صحيحاً';
    if (c.members.any((m) => m.phone == p)) return 'هذا الرقم عضو في الشركة بالفعل';
    final m = CompanyMember(
        id: 'U${DateTime.now().microsecondsSinceEpoch}', name: name.trim(), phone: p, roles: {role}, staff: true);
    c.members = [...c.members, m];
    _update(c, _memberFields(c));
    log(companyId, action: 'دعوة مستخدم: ${m.name}', objectType: 'users', objectId: m.id, result: role.label,
        evidenceRef: 'الجوال $p');
    return null;
  }

  /// تغيير دور موظف أو إيقافه/تفعيله. الشركاء لا يُوقَفون من الإدارة.
  String? updateStaff(String companyId, String memberId, {CompanyRole? role, MemberStatus? status}) {
    final c = _company(companyId);
    final m = c?.members.where((x) => x.id == memberId).firstOrNull;
    if (c == null || m == null) return 'العضو غير موجود';
    if (!m.staff) return 'حقوق الشريك وأدواره لا تتغير من الإدارة دون موافقته وإصدار عقد';
    final next = m.copyWith(roles: role == null ? null : {role}, status: status);
    c.members = [for (final x in c.members) x.id == memberId ? next : x];
    _update(c, _memberFields(c));
    log(companyId,
        action: status != null ? '${status == MemberStatus.active ? 'تفعيل' : 'إيقاف'} المستخدم ${m.name}' : 'تغيير دور ${m.name}',
        objectType: 'users',
        objectId: m.id,
        result: status?.label ?? role!.label);
    return null;
  }

  Map<String, Object?> _memberFields(Company c) {
    final j = c.toJson();
    return {'staff': j['staff'], 'memberPhones': j['memberPhones'], 'adminPhones': j['adminPhones']};
  }

  /// A04: حفظ صلاحيات دور. الحقوق المقفلة للشريك تُضاف دائماً ولا تُنزع.
  void savePermissions(String companyId, CompanyRole role, Map<AppModule, Set<PermAction>> next) {
    final c = _company(companyId);
    if (c == null) return;
    final before = {for (final m in AppModule.values) m: Permissions.actionsFor(role, m, c)};
    final stored = <String, List<String>>{};
    final changes = <String>[];
    for (final m in AppModule.values) {
      final want = {...?next[m], ...Permissions.lockedActions(role, m)};
      if (want.length == Permissions.defaultActions(role, m).length &&
          want.containsAll(Permissions.defaultActions(role, m))) {
        // مطابق للافتراضي: لا حاجة لتخصيص
      } else {
        stored[m.name] = want.map((a) => a.name).toList();
      }
      final b = before[m]!;
      final added = want.difference(b), removed = b.difference(want);
      if (added.isNotEmpty) changes.add('${m.label}: +${added.map((a) => a.label).join('، ')}');
      if (removed.isNotEmpty) changes.add('${m.label}: −${removed.map((a) => a.label).join('، ')}');
    }
    if (changes.isEmpty) return;
    c.permissions = {...c.permissions, role.name: stored};
    _update(c, {'permissions': c.permissions});
    log(companyId, action: 'تعديل صلاحيات دور ${role.label}', objectType: 'permissions', objectId: role.name,
        result: changes.join(' · '));
  }

  /// استعادة صلاحيات الدور الافتراضية
  void resetPermissions(String companyId, CompanyRole role) {
    final c = _company(companyId);
    if (c == null || !c.permissions.containsKey(role.name)) return;
    c.permissions = {...c.permissions}..remove(role.name);
    _update(c, {'permissions': c.permissions});
    log(companyId, action: 'استعادة الصلاحيات الافتراضية لدور ${role.label}', objectType: 'permissions', objectId: role.name);
  }

  /// A05: حفظ إجراءات دور على نقطة إفصاح. إتاحة بيانات شخصية لغير الشريك تُرسل طلب موافقة للشركاء.
  void saveControlPoint(String companyId, String pointId, CompanyRole role, Set<PermAction> actions) {
    final c = _company(companyId);
    if (c == null) return;
    final p = ControlPoint.byId(pointId);
    c.controlPoints = {
      ...c.controlPoints,
      pointId: {...?c.controlPoints[pointId], role.name: actions.map((a) => a.name).toList()},
    };
    final pending = p.requiresConsent && !role.isPartner && actions.isNotEmpty && !c.consentComplete(pointId, role);
    _update(c, {'controlPoints': c.controlPoints});
    log(companyId,
        action: 'ضبط نقطة الإفصاح "${p.label}" لدور ${role.label}',
        objectType: 'permissions',
        objectId: pointId,
        result: actions.isEmpty ? 'لا إجراءات' : actions.map((a) => a.label).join('، '),
        evidenceRef: pending ? 'بانتظار موافقة الشركاء على إتاحة بياناتهم' : null);
  }

  /// طلبات الموافقة التي تنتظر هذا الشريك
  List<(String pointId, CompanyRole role)> pendingConsents(Company c, String memberId) => [
        for (final p in ControlPoint.catalog.where((p) => p.requiresConsent))
          for (final r in CompanyRole.values.where((r) => !r.isPartner))
            if ((c.controlPoints[p.id]?[r.name]?.isNotEmpty ?? false) &&
                !(c.consents['${p.id}|${r.name}']?.containsKey(memberId) ?? false))
              (p.id, r),
      ];

  /// موافقة الشريك المباشرة على إتاحة بياناته لدور غير الشركاء
  void giveConsent(String companyId, String pointId, CompanyRole role, String memberId, {required String method}) {
    final c = _company(companyId);
    if (c == null) return;
    final key = '$pointId|${role.name}';
    final at = DateTime.now().toUtc().toIso8601String();
    c.consents = {
      ...c.consents,
      key: {...?c.consents[key], memberId: at},
    };
    if (_db != null) {
      _db!.collection('companies').doc(c.id).collection('consents').doc('$key|$myPhone').set({
        'point': pointId,
        'role': role.name,
        'memberId': memberId,
        'phone': myPhone,
        'at': at,
      }).then((_) {}, onError: (Object e) => debugPrint('تعذر حفظ الموافقة: $e'));
      notifyListeners();
    } else {
      _update(c, {'consents': c.consents});
    }
    log(companyId,
        action: 'موافقة شريك على إتاحة "${ControlPoint.byId(pointId).label}" لدور ${role.label}',
        objectType: 'permissions',
        objectId: key,
        result: c.consentComplete(pointId, role) ? 'اكتملت موافقة الشركاء' : 'بانتظار بقية الشركاء',
        evidenceRef: 'تأكيد: $method');
  }

  /// A21: حفظ إعداد منصة بعد التحقق من القيمة المسموحة
  String? setSetting(String companyId, String key, Object? value) {
    final c = _company(companyId);
    if (c == null) return 'الشركة غير موجودة';
    final s = PlatformSetting.byKey(key);
    final err = s.validate(value);
    if (err != null) return err;
    final v = s.kind == SettingKind.integer ? int.parse('$value') : value;
    final before = c.setting<Object?>(key);
    if (before == v) return null;
    c.settings = {...c.settings, key: v};
    _update(c, {'settings': c.settings});
    log(companyId, action: 'تعديل إعداد: ${s.label}', objectType: 'settings', objectId: key,
        result: '${s.display(before)} ← ${s.display(v)}');
    return null;
  }

  /// A20: معالجة حدث أمني
  void triageEvent(String companyId, String eventId, TriageState state, {String? assignee, String? note}) {
    final c = _company(companyId);
    if (c == null) return;
    c.triage = {
      ...c.triage,
      eventId: Triage(state: state, assignee: assignee, note: note, at: DateTime.now()).toJson(),
    };
    _update(c, {'triage': c.triage});
    log(companyId, action: 'معالجة حدث أمني', objectType: 'security', objectId: eventId,
        result: '${state.label}${assignee == null ? '' : ' · المسؤول: $assignee'}${note == null || note.isEmpty ? '' : ' · $note'}');
  }

  /// تسجيل آخر دخول للعضو الحالي (يظهر للإدارة؛ من لم يدخل بعد فدعوته معلّقة)
  void touchLastSeen() {
    final c = current;
    final m = me;
    if (c == null || m == null) return;
    final last = DateTime.tryParse(c.lastSeen[m.id] ?? '');
    if (last != null && DateTime.now().difference(last).inMinutes < 30) return;
    // حدث دخول في السجل الأمني مرة كل 12 ساعة على الأكثر حتى لا يزدحم السجل
    if (last == null || DateTime.now().difference(last).inHours >= 12) {
      log(c.id, action: 'دخول إلى الشركة', objectType: 'security', objectId: m.id, result: m.phone.isEmpty ? '' : 'التحقق برقم الجوال');
    }
    c.lastSeen = {...c.lastSeen, m.id: DateTime.now().toUtc().toIso8601String()};
    _db?.collection('companies').doc(c.id).update({'lastSeen.${m.id}': c.lastSeen[m.id]}).then((_) {},
        onError: (Object e) => debugPrint('تعذر تسجيل آخر دخول: $e'));
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
      contractVersion: company == null || company.contractVersion == 0 ? null : company.contractVersion,
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
