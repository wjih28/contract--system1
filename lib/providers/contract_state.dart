import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' show FieldPath, QuerySnapshot;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/question_bank.dart';
import '../models/company.dart' show ActorType;
import '../models/questionnaire.dart';
import '../services/cloud_sync.dart';
import '../services/phone.dart';
import '../widgets/common_widgets.dart';

/// حالة محرك الاستبانة: بنك الأسئلة وجلسات إعداد العقود.
/// يعمل بوضعين:
/// - محلي: جهاز واحد، والجلسات محفوظة على الجهاز.
/// - خادم (Firebase): كل شريك يصوّت ويوقّع من جواله، والأصوات تُزامَن لحظياً.
/// في وضع الخادم تُشتق حالة كل بند من الأصوات نفسها، فلا يحدث تعارض بين الأجهزة.

/// مستقبِل أحداث التدقيق (تربطه الواجهة بسجل تدقيق الشركة)
typedef AuditSink = void Function(
  String companyId, {
  required String action,
  required String objectType,
  required String objectId,
  String result,
  String? evidenceRef,
  ActorType actorType,
});

class ContractState extends ChangeNotifier {
  /// كل إجراء على الجلسة يُسجَّل في سجل تدقيق الشركة
  AuditSink? auditSink;

  void _audit(ContractSession s, String action,
      {String objectType = 'clause',
      required String objectId,
      String result = '',
      String? evidence,
      bool actorSystem = false}) {
    final cid = s.companyId;
    if (cid == null) return;
    auditSink?.call(cid,
        action: action,
        objectType: objectType,
        objectId: objectId,
        result: result,
        evidenceRef: evidence,
        actorType: actorSystem ? ActorType.system : ActorType.user);
  }

  String _title(ClauseRecord r) => question(r.questionId).title;

  String _partnerName(ContractSession s, String id) =>
      s.partners.where((p) => p.id == id).firstOrNull?.name ?? id;

  /// جلسات شركة معينة
  List<ContractSession> sessionsFor(String? companyId) =>
      sessions.where((s) => s.companyId == companyId).toList();

  /// جلسة التأسيس للشركة (واحدة لكل شركة)
  ContractSession? establishmentFor(String? companyId) =>
      companyId == null ? null : sessions.where((s) => s.companyId == companyId).firstOrNull;

  /// البنود المفتوحة التي تنتظر صوت هذا الشريك (لم يصوّت بعد)
  List<ClauseRecord> pendingFor(ContractSession s, String partnerId) => s.records
      .where((r) =>
          r.status == ClauseStatus.pending &&
          !r.votes.containsKey(partnerId) &&
          voters(s, r).any((p) => p.id == partnerId))
      .toList();

  /// البنود التي بدأ التصويت عليها ولم تُحسم بعد
  List<ClauseRecord> openDecisions(ContractSession s) =>
      s.records.where((r) => r.status == ClauseStatus.pending && r.openedAt != null).toList();

  static const _sessionsKey = 'contract_sessions_v1';
  static const _customBankKey = 'custom_bank_v1';

  final List<BankQuestion> _customQuestions = [];
  final Map<String, BankQuestion> _remoteQuestions = {};
  List<ContractSession> sessions = [];
  bool loaded = false;

  List<BankQuestion> get bank => [...seedQuestionBank, ..._customQuestions];

  BankQuestion question(String id) =>
      bank.where((q) => q.id == id).firstOrNull ?? _remoteQuestions[id]!;

  // ───────────── وضع الخادم ─────────────

  CloudSync? _cloud;
  String? myPhone;
  String? _myUid;
  final List<StreamSubscription> _querySubs = [];
  final Map<String, List<StreamSubscription>> _docSubs = {};
  final Map<String, Map<String, dynamic>> _docs = {};
  final Map<String, List<Map<String, dynamic>>> _votes = {};
  final Map<String, List<Map<String, dynamic>>> _signs = {};
  final Map<String, List<Map<String, dynamic>>> _attest = {};
  // معرّفات الجلسات حسب مصدرها: عضوية الشركة أو دعوة الشاهد
  final Map<String, Set<String>> _idsBySource = {'member': {}, 'witness': {}};

  bool get isCloud => _cloud != null;

  /// هل يستطيع مستخدم هذا الجهاز التصويت أو التوقيع باسم هذا الشريك؟
  bool canActAs(SessionPartner p) => !isCloud || normalizePhone(p.phone) == myPhone;

  /// هل يستطيع مستخدم هذا الجهاز الشهادة باسم هذا الشاهد؟
  bool canAttestAs(Witness w) => !isCloud || (w.phone.isNotEmpty && w.phone == myPhone);

  /// جلسات دُعي فيها المستخدم شاهداً (مهامه المهنية R07)
  List<ContractSession> get witnessTasks => sessions
      .where((s) => s.status != SessionStatus.completed && s.witnesses.any((w) => w.phone == myPhone && !w.attested))
      .toList();

  Timer? _ticker;

  /// مؤقت دوري يحسم البنود التي انتهت مهلتها
  void startTicker() {
    _ticker ??= Timer.periodic(const Duration(minutes: 1), (_) => refreshDeadlines());
  }

  Future<void> attachCloud(CloudSync cloud, {required String phone, required String uid}) async {
    await detachCloud();
    _cloud = cloud;
    myPhone = phone;
    _myUid = uid;
    sessions = [];
    loaded = false;
    notifyListeners();
    void onError(Object e) {
      debugPrint('تعذر قراءة الجلسات من الخادم: $e');
      loaded = true;
      notifyListeners();
    }

    _querySubs.add(cloud.mySessions(phone).listen((q) => _onSessions('member', q), onError: onError));
    _querySubs.add(cloud.witnessSessions(phone).listen((q) => _onSessions('witness', q), onError: onError));
  }

  Future<void> detachCloud() async {
    for (final s in _querySubs) {
      await s.cancel();
    }
    _querySubs.clear();
    for (final list in _docSubs.values) {
      for (final s in list) {
        await s.cancel();
      }
    }
    _docSubs.clear();
    _docs.clear();
    _votes.clear();
    _signs.clear();
    _attest.clear();
    for (final ids in _idsBySource.values) {
      ids.clear();
    }
    _cloud = null;
    myPhone = null;
    _myUid = null;
  }

  void _onSessions(String source, QuerySnapshot<Map<String, dynamic>> snap) {
    _idsBySource[source] = snap.docs.map((d) => d.id).toSet();
    final all = _idsBySource.values.expand((x) => x).toSet();
    for (final gone in _docs.keys.where((k) => !all.contains(k)).toList()) {
      _docs.remove(gone);
      for (final s in _docSubs.remove(gone) ?? const <StreamSubscription>[]) {
        s.cancel();
      }
    }
    for (final d in snap.docs) {
      _docs[d.id] = d.data();
      _docSubs.putIfAbsent(d.id, () {
        final id = d.id;
        return [
          _cloud!.votes(id).listen((v) {
            _votes[id] = v.docs.map((e) => e.data()).toList();
            _rebuildAll();
          }),
          _cloud!.signoffs(id).listen((v) {
            _signs[id] = v.docs.map((e) => {...e.data(), 'partnerId': e.id}).toList();
            _rebuildAll();
          }),
          _cloud!.attestations(id).listen((v) {
            _attest[id] = v.docs.map((e) => {...e.data(), 'phone': e.id}).toList();
            _rebuildAll();
          }),
        ];
      });
    }
    loaded = true;
    _rebuildAll();
  }

  void _rebuildAll() {
    sessions = _docs.entries
        .map((e) => sessionFromRemote(
              e.key,
              e.value,
              _votes[e.key] ?? const [],
              _signs[e.key] ?? const [],
              _attest[e.key] ?? const [],
            ))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  /// تحويل الجلسة إلى مستند Firestore
  Map<String, dynamic> sessionToRemote(ContractSession s, {required String uid}) {
    final phones = {for (final p in s.partners) p.id: normalizePhone(p.phone)};
    final used = s.records.map((r) => r.questionId).toSet();
    return {
      'companyId': s.companyId,
      'companyName': s.companyName,
      'companyType': s.companyType,
      'currency': s.currency.name,
      'capital': s.capital,
      'partners': s.partners.map((p) => {...p.toJson(), 'phone': phones[p.id]}).toList(),
      'partnerPhones': phones,
      'memberPhones': phones.values.toSet().toList(),
      'records': {for (final r in s.records) r.key: _recordToRemote(r)},
      // البنود المضافة يدوياً تُرفق بالجلسة حتى تظهر على أجهزة بقية الشركاء
      'customQuestions': _customQuestions.where((q) => used.contains(q.id)).map((q) => q.toJson()).toList(),
      'status': s.status.name,
      'sittings': s.sittings,
      'settings': s.settings.toJson(),
      // الشهود المدعوون يقرؤون الجلسة ويشهدون من جوالاتهم
      'witnessPhones': s.witnesses.map((w) => w.phone).where((p) => p.isNotEmpty).toList(),
      'witnesses': s.witnesses.map((w) => w.toJson()).toList(),
      'createdAt': s.createdAt.toUtc().toIso8601String(),
      'updatedAt': s.updatedAt.toUtc().toIso8601String(),
      'completedAt': null,
      'contentHash': null,
      'createdBy': uid,
    };
  }

  Map<String, dynamic> _recordToRemote(ClauseRecord r) => {
        'questionId': r.questionId,
        'concernedPartnerId': r.concernedPartnerId,
        'value': r.value,
        'round': r.round,
        'openedAt': r.openedAt?.toUtc().toIso8601String(),
        'failures': r.failures,
        'notes': r.notes.map((n) => n.toJson()).toList(),
        'deferReason': r.deferReason,
        'flag': switch (r.status) {
          ClauseStatus.deferred => 'deferred',
          ClauseStatus.neutralized => 'neutralized',
          _ => 'none',
        },
        'flagAt': r.status == ClauseStatus.neutralized ? r.resolvedAt?.toUtc().toIso8601String() : null,
      };

  /// بناء الجلسة من مستند الخادم وأصواته وتواقيعه.
  /// حالة البند = المؤجل/المحيّد إن وُجد، وإلا تُحسب من أصوات الجولة الحالية.
  ContractSession sessionFromRemote(
    String id,
    Map<String, dynamic> d,
    List<Map<String, dynamic>> votes,
    List<Map<String, dynamic>> signs, [
    List<Map<String, dynamic>> attestations = const [],
  ]) {
    for (final q in (d['customQuestions'] as List? ?? [])) {
      final bq = BankQuestion.fromJson(Map<String, dynamic>.from(q as Map));
      _remoteQuestions[bq.id] = bq;
    }
    final partners = (d['partners'] as List)
        .map((p) => SessionPartner.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList();
    final recs = Map<String, dynamic>.from(d['records'] as Map);
    final s = ContractSession(
      id: id,
      companyId: d['companyId'] as String?,
      companyName: d['companyName'] as String,
      companyType: d['companyType'] as String,
      currency: AppCurrency.values.byName(d['currency'] as String),
      capital: (d['capital'] as num).toDouble(),
      partners: partners,
      records: [],
      status: SessionStatus.values.byName(d['status'] as String),
      createdAt: remoteTime(d['createdAt']),
      updatedAt: remoteTime(d['updatedAt']),
      sittings: (d['sittings'] as num?)?.toInt() ?? 1,
      settings: VotingSettings.fromJson(
          d['settings'] == null ? null : Map<String, dynamic>.from(d['settings'] as Map)),
      witnesses: (d['witnesses'] as List? ?? [])
          .map((w) => Witness.fromJson(Map<String, dynamic>.from(w as Map)))
          .toList(),
      completedAt: d['completedAt'] == null ? null : remoteTime(d['completedAt']),
      contentHash: d['contentHash'] as String?,
    );

    // ترتيب البنود كما في بنك الأسئلة، ثم البنود الخاصة بترتيب الشركاء
    final order = <String>[];
    for (final q in [...bank, ..._remoteQuestions.values]) {
      if (q.scope == ClauseScope.private) {
        order.addAll(partners.map((p) => '${q.id}:${p.id}'));
      } else {
        order.add(q.id);
      }
    }
    final keys = recs.keys.toList()
      ..sort((a, b) {
        final ia = order.indexOf(a), ib = order.indexOf(b);
        return (ia < 0 ? 1 << 20 : ia).compareTo(ib < 0 ? 1 << 20 : ib);
      });

    for (final key in keys) {
      final m = Map<String, dynamic>.from(recs[key] as Map);
      final r = ClauseRecord(
        key: key,
        questionId: m['questionId'] as String,
        concernedPartnerId: m['concernedPartnerId'] as String?,
        value: (m['value'] as num?)?.toDouble(),
        round: (m['round'] as num?)?.toInt() ?? 1,
        openedAt: m['openedAt'] == null ? null : remoteTime(m['openedAt']),
        failures: (m['failures'] as num?)?.toInt() ?? 0,
        notes: (m['notes'] as List? ?? [])
            .map((n) => ClauseNote.fromJson(Map<String, dynamic>.from(n as Map)))
            .toList(),
        deferReason: m['deferReason'] as String?,
      );
      for (final v in votes) {
        if ((v['round'] as num?)?.toInt() != r.round) continue;
        final pid = v['partnerId'] as String;
        if (v['recordKey'] == key) {
          r.votes[pid] = PartnerVote(
            partnerId: pid,
            ballot: Ballot.values.byName(v['ballot'] as String),
            at: remoteTime(v['at']),
            method: ConfirmMethod.values.byName(v['method'] as String),
          );
        } else if (v['recordKey'] == neutralKey(key)) {
          r.neutralConsents.add(pid);
        }
      }
      switch (m['flag']) {
        case 'deferred':
          r.status = ClauseStatus.deferred;
        case 'neutralized':
          r.status = ClauseStatus.neutralized;
          r.resolvedAt = m['flagAt'] == null ? null : remoteTime(m['flagAt']);
        default:
          _applyDerived(s, r);
      }
      s.records.add(r);
    }

    for (final so in signs) {
      final pid = so['partnerId'] as String;
      s.signOffs[pid] = PartnerSignOff(
        partnerId: pid,
        signaturePng: so['signaturePng'] as String,
        at: remoteTime(so['at']),
        method: ConfirmMethod.values.byName(so['method'] as String),
        draftHash: so['draftHash'] as String? ?? '',
      );
    }
    // شهادات الشهود المسجلة من جوالاتهم
    for (final a in attestations) {
      final i = s.witnesses.indexWhere((w) => w.phone == a['phone']);
      if (i < 0) continue;
      final w = s.witnesses[i];
      s.witnesses[i] = Witness(
        name: w.name,
        nationalId: w.nationalId,
        internal: w.internal,
        phone: w.phone,
        signaturePng: a['signaturePng'] as String?,
        draftHash: a['draftHash'] as String?,
        attestedAt: remoteTime(a['at']),
        method: ConfirmMethod.values.byName(a['method'] as String),
      );
    }
    return s;
  }

  static String neutralKey(String key) => 'N~$key';

  void _remote(ContractSession s, Map<Object, Object?> fields) {
    _cloud?.update(s.id, fields).catchError((Object e) => debugPrint('تعذر حفظ التعديل في الخادم: $e'));
  }

  void _remoteRecord(ContractSession s, ClauseRecord r) =>
      _remote(s, {FieldPath(['records', r.key]): _recordToRemote(r)});

  // ───────────── التخزين المحلي ─────────────

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final custom = prefs.getString(_customBankKey);
      if (custom != null) {
        _customQuestions
          ..clear()
          ..addAll((jsonDecode(custom) as List)
              .map((e) => BankQuestion.fromJson(e as Map<String, dynamic>)));
      }
      final raw = prefs.getString(_sessionsKey);
      if (raw != null && !isCloud) {
        sessions = (jsonDecode(raw) as List)
            .map((e) => ContractSession.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('تعذر تحميل الجلسات المحفوظة: $e');
    }
    if (!isCloud) loaded = true;
    refreshDeadlines();
    startTicker();
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!isCloud) {
        await prefs.setString(
          _sessionsKey,
          jsonEncode(sessions.map((s) => s.toJson()).toList()),
        );
      }
      await prefs.setString(
        _customBankKey,
        jsonEncode(_customQuestions.map((q) => q.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('تعذر حفظ الجلسات: $e');
    }
  }

  void _touch(ContractSession s) {
    s.updatedAt = DateTime.now();
    notifyListeners();
    _persist();
  }

  // ───────────── بنك الأسئلة ─────────────

  void addQuestion(BankQuestion q) {
    _customQuestions.add(q);
    notifyListeners();
    _persist();
  }

  void removeQuestion(String id) {
    _customQuestions.removeWhere((q) => q.id == id);
    notifyListeners();
    _persist();
  }

  String nextCustomId() => 'C${(_customQuestions.length + 1).toString().padLeft(2, '0')}'
      '-${DateTime.now().millisecondsSinceEpoch % 100000}';

  // ───────────── الجلسات ─────────────

  ContractSession createSession({
    String? companyId,
    required String companyName,
    required String companyType,
    required AppCurrency currency,
    required double capital,
    required List<SessionPartner> partners,
    VotingSettings settings = VotingSettings.defaults,
  }) {
    final records = <ClauseRecord>[];
    for (final q in bank) {
      if (q.scope == ClauseScope.private) {
        // البند الخاص يتكرر لكل شريك ويُحسم بتراضيه الفردي
        for (final p in partners) {
          records.add(ClauseRecord(
            key: '${q.id}:${p.id}',
            questionId: q.id,
            concernedPartnerId: p.id,
            value: q.defaultValue,
          ));
        }
      } else {
        records.add(ClauseRecord(
          key: q.id,
          questionId: q.id,
          value: q.defaultValue,
        ));
      }
    }
    final now = DateTime.now();
    final s = ContractSession(
      id: 'S${now.millisecondsSinceEpoch}',
      companyId: companyId,
      companyName: companyName,
      companyType: companyType,
      currency: currency,
      capital: capital,
      partners: partners,
      records: records,
      createdAt: now,
      updatedAt: now,
      settings: settings,
    );
    sessions.insert(0, s);
    if (isCloud) {
      _cloud!
          .create(s.id, sessionToRemote(s, uid: _myUid!))
          .catchError((Object e) => debugPrint('تعذر إنشاء الجلسة في الخادم: $e'));
    }
    _touch(s);
    return s;
  }

  void deleteSession(ContractSession s) {
    sessions.remove(s);
    _cloud?.delete(s.id).catchError((Object e) => debugPrint('تعذر حذف الجلسة: $e'));
    notifyListeners();
    _persist();
  }

  /// الشركاء الذين يحق لهم التصويت على البند
  List<SessionPartner> voters(ContractSession s, ClauseRecord r) =>
      r.concernedPartnerId != null
          ? s.partners.where((p) => p.id == r.concernedPartnerId).toList()
          : s.partners.where((p) => p.equity > 0).toList();

  /// احتساب النصاب مرجحاً بالحصص في رأس المال.
  /// المحايد لا يُحتسب موافقاً، والبند الخاص يتطلب موافقة صاحبه فقط.
  QuorumResult quorum(ContractSession s, ClauseRecord r) {
    final q = question(r.questionId);
    final list = voters(s, r);
    final private = r.concernedPartnerId != null;
    final total = private ? 1.0 : list.fold<double>(0, (a, p) => a + p.equity);
    double share(Ballot b) => list
        .where((p) => r.votes[p.id]?.ballot == b)
        .fold<double>(0, (a, p) => a + (private ? 1.0 : p.equity));
    final agree = total == 0 ? 0.0 : share(Ballot.agree) / total * 100;
    final disagree = total == 0 ? 0.0 : share(Ballot.disagree) / total * 100;
    final neutral = total == 0 ? 0.0 : share(Ballot.neutral) / total * 100;
    final required = private ? 100.0 : q.quorum.percent;
    final complete = list.every((p) => r.votes.containsKey(p.id));
    final deadline = r.openedAt?.add(Duration(days: s.settings.deadlineDays));
    return QuorumResult(
      agreeShare: agree,
      disagreeShare: disagree,
      neutralShare: neutral,
      required: required,
      // البند الخاص يحتاج مشاركة صاحبه، والعام يحتاج الحد الأدنى من الحصص
      quorum: private ? 100.0 : s.settings.quorum,
      complete: complete,
      passed: agree + 1e-6 >= required,
      deadline: deadline,
      deadlinePassed: deadline != null && now().isAfter(deadline),
    );
  }

  /// الساعة المستخدمة في احتساب المهل (قابلة للتبديل في الاختبارات)
  DateTime Function() now = DateTime.now;

  /// حالة البند المشتقة من الأصوات والمهلة:
  /// - صوّت الجميع: معتمد إن بلغت الموافقة العتبة، وإلا مرفوض.
  /// - انتهت المهلة: تعذّر النصاب إن لم تبلغ المشاركة الحد الأدنى، وإلا يُحسم بالأصوات المسجلة
  ///   (عدم التصويت لا يُحتسب موافقة لأن العتبة من إجمالي الحصص).
  /// - تكرار الفشل حتى حد الجمود: جمود.
  ClauseStatus deriveStatus(ContractSession s, ClauseRecord r) {
    if (r.status == ClauseStatus.deferred || r.status == ClauseStatus.neutralized) return r.status;
    final q = quorum(s, r);
    if (!q.decidable) return ClauseStatus.pending;
    if (q.passed && q.quorumMet) return ClauseStatus.agreed;
    final failed = q.quorumMet ? ClauseStatus.rejected : ClauseStatus.quorumFailed;
    return r.failures + 1 >= s.settings.deadlockAfter ? ClauseStatus.deadlock : failed;
  }

  void _applyDerived(ContractSession s, ClauseRecord r) {
    final st = deriveStatus(s, r);
    if (st == r.status) return;
    r.status = st;
    r.resolvedAt = st == ClauseStatus.pending
        ? null
        : (r.votes.isEmpty ? now() : r.votes.values.map((v) => v.at).reduce((a, b) => a.isAfter(b) ? a : b));
  }

  /// إعادة احتساب البنود التي انتهت مهلتها (يُستدعى دورياً وعند فتح الشاشات)
  bool refreshDeadlines() {
    var changed = false;
    for (final s in sessions) {
      if (s.status == SessionStatus.completed) continue;
      for (final r in s.records) {
        if (r.status != ClauseStatus.pending) continue;
        final before = r.status;
        _applyDerived(s, r);
        if (r.status != before) {
          changed = true;
          _audit(s, 'انتهت مهلة التصويت على: ${_title(r)}', objectId: r.key, result: r.status.label,
              actorSystem: true);
        }
      }
    }
    if (changed) {
      notifyListeners();
      _persist();
    }
    return changed;
  }

  void castVote(
    ContractSession s,
    ClauseRecord r,
    String partnerId,
    Ballot ballot,
    ConfirmMethod method,
  ) {
    r.votes[partnerId] = PartnerVote(
      partnerId: partnerId,
      ballot: ballot,
      at: DateTime.now(),
      method: method,
    );
    // أول صوت في الجولة يبدأ مهلة التصويت
    final opened = r.openedAt == null;
    r.openedAt ??= now();
    r.status = ClauseStatus.pending;
    _applyDerived(s, r);
    if (opened) _remoteRecord(s, r);
    _cloud
        ?.vote(
          sid: s.id,
          recordKey: r.key,
          partnerId: partnerId,
          round: r.round,
          ballot: ballot.name,
          method: method.name,
          phone: myPhone!,
        )
        .catchError((Object e) => debugPrint('تعذر تسجيل الصوت في الخادم: $e'));
    _audit(s, 'تصويت ${_partnerName(s, partnerId)} بـ "${ballot.label}" على: ${_title(r)}',
        objectId: r.key, result: r.status.label, evidence: 'تأكيد: ${method.label}، الجولة ${r.round}');
    _touch(s);
  }

  /// موافقة شريك على تحييد البند (وضع الخادم: يوافق كل شريك من جواله)
  void consentNeutralize(ContractSession s, ClauseRecord r, String partnerId, ConfirmMethod method) {
    r.neutralConsents.add(partnerId);
    _audit(s, 'موافقة ${_partnerName(s, partnerId)} على تحييد: ${_title(r)}', objectId: r.key, evidence: 'تأكيد: ${method.label}');
    _cloud
        ?.vote(
          sid: s.id,
          recordKey: neutralKey(r.key),
          partnerId: partnerId,
          round: r.round,
          ballot: Ballot.agree.name,
          method: method.name,
          phone: myPhone!,
        )
        .catchError((Object e) => debugPrint('تعذر تسجيل الموافقة في الخادم: $e'));
    notifyListeners();
  }

  /// تعديل القيمة المقترحة يلغي الأصوات السابقة لأنها كانت على قيمة مختلفة
  void setValue(ContractSession s, ClauseRecord r, double? value) {
    if (r.value == value) return;
    r.value = value;
    if (r.votes.isNotEmpty) {
      r.votes.clear();
      r.round++;
      r.openedAt = null;
    }
    r.status = ClauseStatus.pending;
    r.resolvedAt = null;
    _remoteRecord(s, r);
    _audit(s, 'تعديل قيمة البند: ${_title(r)}', objectId: r.key, result: 'القيمة الجديدة $value، الجولة ${r.round}');
    _touch(s);
  }

  void revote(ContractSession s, ClauseRecord r) {
    // جولة فاشلة جديدة تقرّب البند من الجمود
    if (r.status == ClauseStatus.rejected || r.status == ClauseStatus.quorumFailed) r.failures++;
    r.votes.clear();
    r.round++;
    r.openedAt = null;
    r.status = ClauseStatus.pending;
    r.resolvedAt = null;
    _remoteRecord(s, r);
    _audit(s, 'إعادة التصويت على: ${_title(r)}', objectId: r.key, result: 'الجولة ${r.round}');
    _touch(s);
  }

  void defer(ContractSession s, ClauseRecord r, {String? reason}) {
    r.status = ClauseStatus.deferred;
    r.resolvedAt = null;
    r.deferReason = (reason == null || reason.trim().isEmpty) ? null : reason.trim();
    _remoteRecord(s, r);
    _audit(s, 'تأجيل البند: ${_title(r)}', objectId: r.key,
        result: r.deferReason == null ? ClauseStatus.deferred.label : 'السبب: ${r.deferReason}');
    _touch(s);
  }

  /// إعادة فتح بند مؤجل أو محيّد للنقاش والتصويت
  void reopen(ContractSession s, ClauseRecord r) {
    r.votes.clear();
    r.round++;
    r.openedAt = null;
    r.failures = 0;
    r.status = ClauseStatus.pending;
    r.resolvedAt = null;
    _remoteRecord(s, r);
    _audit(s, 'إعادة فتح البند: ${_title(r)}', objectId: r.key, result: 'الجولة ${r.round}');
    _touch(s);
  }

  /// التحييد يتم باتفاق جميع الشركاء ويُسقط البند من العقد
  void neutralize(ContractSession s, ClauseRecord r) {
    r.status = ClauseStatus.neutralized;
    r.resolvedAt = DateTime.now();
    _remoteRecord(s, r);
    _audit(s, 'تحييد البند باتفاق الشركاء: ${_title(r)}', objectId: r.key, result: ClauseStatus.neutralized.label);
    _touch(s);
  }

  void suspend(ContractSession s) {
    s.status = SessionStatus.suspended;
    _remote(s, {'status': s.status.name});
    _audit(s, 'تعليق جلسة التأسيس', objectType: 'session', objectId: s.id, result: 'محفوظ ما تم التراضي عليه');
    _touch(s);
  }

  void resume(ContractSession s) {
    if (s.status == SessionStatus.suspended) {
      s.status = SessionStatus.active;
      s.sittings++;
      _remote(s, {'status': s.status.name, 'sittings': s.sittings});
      _audit(s, 'استئناف جلسة التأسيس', objectType: 'session', objectId: s.id, result: 'الجلسة رقم ${s.sittings}');
      _touch(s);
    }
  }

  void markAwaitingSignature(ContractSession s) {
    if (s.allResolved && s.status != SessionStatus.completed) {
      s.status = SessionStatus.awaitingSignature;
      _remote(s, {'status': s.status.name});
      _touch(s);
    }
  }

  // ───────────── المسودة والتوقيع والشهود ─────────────

  /// بصمة مسودة العقد: نصوص البنود وحالاتها وقيمها والشركاء.
  /// التوقيع يُربط بهذه البصمة، فأي تعديل لاحق على البنود يُبطل التواقيع السابقة.
  String draftHash(ContractSession s) => sha256
      .convert(utf8.encode(jsonEncode({
        'id': s.id,
        'company': [s.companyName, s.companyType, s.currency.code, s.capital],
        'partners': s.partners.map((p) => [p.id, p.name, p.equity]).toList(),
        'clauses': s.records
            .map((r) => [r.key, r.status.name, r.value, r.status == ClauseStatus.agreed ? renderClause(s, r) : null])
            .toList(),
      })))
      .toString();

  bool signOffValid(ContractSession s, PartnerSignOff so) => so.draftHash == draftHash(s);

  bool witnessValid(ContractSession s, Witness w) => w.attested && w.draftHash == draftHash(s);

  /// موانع التوقيع النهائي (P10): قائمة دقيقة بما يجب إنجازه
  List<String> signingBlockers(ContractSession s, {int minWitnesses = 2}) {
    final out = <String>[];
    final open = s.records.where((r) => r.status.needsDecision).length;
    final deferred = s.count(ClauseStatus.deferred);
    if (open > 0) out.add('$open بنود لم تُحسم بعد');
    if (deferred > 0) out.add('$deferred بنود مؤجلة يجب حسمها أو تحييدها');
    return out;
  }

  /// ما يمنع الاعتماد النهائي بعد حسم البنود: التواقيع والشهود
  List<String> finalizeBlockers(ContractSession s, {int minWitnesses = 2}) {
    final out = signingBlockers(s);
    final unsigned = s.partners.where((p) {
      final so = s.signOffs[p.id];
      return so == null || !signOffValid(s, so);
    }).length;
    if (unsigned > 0) out.add('$unsigned شركاء لم يوقّعوا على الإصدار الحالي');
    final w = s.witnesses.where((x) => witnessValid(s, x)).length;
    if (w < minWitnesses) out.add('الشهود: $w من $minWitnesses شهدوا على الإصدار الحالي');
    return out;
  }

  void signOff(ContractSession s, PartnerSignOff so) {
    final hash = draftHash(s);
    final bound = PartnerSignOff(
      partnerId: so.partnerId,
      signaturePng: so.signaturePng,
      at: so.at,
      method: so.method,
      draftHash: hash,
    );
    s.signOffs[so.partnerId] = bound;
    _cloud
        ?.signOff(
          sid: s.id,
          partnerId: so.partnerId,
          signaturePng: so.signaturePng,
          method: so.method.name,
          phone: myPhone!,
          draftHash: hash,
        )
        .catchError((Object e) => debugPrint('تعذر حفظ التوقيع في الخادم: $e'));
    _audit(s, 'توقيع ${_partnerName(s, so.partnerId)} النهائي وإقرار الأهلية', objectType: 'contract', objectId: s.id,
        result: 'تم التوقيع على المسودة', evidence: 'تأكيد: ${so.method.label}، بصمة المسودة ${hash.substring(0, 16)}');
    _touch(s);
  }

  void setWitnesses(ContractSession s, List<Witness> w) {
    s.witnesses = w;
    _remote(s, {
      'witnesses': w.map((x) => x.toJson()).toList(),
      'witnessPhones': w.map((x) => x.phone).where((p) => p.isNotEmpty).toList(),
    });
    _audit(s, 'تحديث الشهود', objectType: 'contract', objectId: s.id, result: '${w.length} شهود');
    _touch(s);
  }

  /// شهادة الشاهد (R07) على الإصدار الحالي: من جهاز الجلسة محلياً، أو من جوال الشاهد في وضع الخادم
  void attestWitness(ContractSession s, int index, {required String signature, required ConfirmMethod method}) {
    final hash = draftHash(s);
    final w = s.witnesses[index].attest(signature: signature, hash: hash, by: method);
    s.witnesses = [...s.witnesses]..[index] = w;
    if (isCloud && w.phone.isNotEmpty && w.phone == myPhone) {
      _cloud!
          .attest(sid: s.id, phone: w.phone, signaturePng: signature, method: method.name, draftHash: hash)
          .catchError((Object e) => debugPrint('تعذر حفظ شهادة الشاهد: $e'));
    } else {
      _remote(s, {'witnesses': s.witnesses.map((x) => x.toJson()).toList()});
    }
    _audit(s, 'شهادة ${w.name} على العقد', objectType: 'contract', objectId: s.id,
        result: w.internal ? 'شاهد من داخل الشركة' : 'شاهد من خارج الشركة',
        evidence: 'تأكيد: ${method.label}، بصمة المسودة ${hash.substring(0, 16)}');
    _touch(s);
  }

  /// ملاحظة نقاش على بند (P05/P06): لا تغيّر نص البند ولا الأصوات
  void addNote(ContractSession s, ClauseRecord r, String text, {required String author}) {
    final t = text.trim();
    if (t.isEmpty) return;
    r.notes = [...r.notes, ClauseNote(author: author, text: t, at: now())];
    _remoteRecord(s, r);
    _audit(s, 'ملاحظة على: ${_title(r)}', objectId: r.key, result: t.length > 60 ? '${t.substring(0, 60)}…' : t);
    _touch(s);
  }

  /// الاعتماد النهائي: تُحسب البصمة وتُحفظ في الخادم، وبعدها يُقفل العقد بقواعد الأمان
  void complete(ContractSession s) {
    s.status = SessionStatus.completed;
    s.completedAt = DateTime.now().toUtc();
    s.contentHash = computeHash(s);
    _remote(s, {
      'status': s.status.name,
      'completedAt': s.completedAt!.toIso8601String(),
      'contentHash': s.contentHash,
    });
    _audit(s, 'اعتماد العقد النهائي', objectType: 'contract', objectId: s.id, result: 'العقد مقفل للقراءة فقط',
        evidence: 'SHA-256: ${s.contentHash}');
    _touch(s);
  }

  /// المحتوى القانوني للعقد بترتيب ثابت: البنود بنصها النهائي، الأصوات، التواقيع، الشهود.
  /// التواقيع تدخل ببصمتها لا بصورتها حتى يبقى المحتوى خفيفاً.
  /// الأوقات بتوقيت UTC حتى تتطابق البصمة على أجهزة في مناطق زمنية مختلفة.
  String canonicalContent(ContractSession s) {
    String digest(String? v) => v == null ? '' : sha256.convert(utf8.encode(v)).toString();
    String t(DateTime d) => d.toUtc().toIso8601String();
    final sortedSign = s.signOffs.keys.toList()..sort();
    return jsonEncode({
      'id': s.id,
      'company': [s.companyName, s.companyType, s.currency.code, s.capital],
      'partners': s.partners
          .map((p) => [p.id, p.name, p.nationalId, normalizePhone(p.phone), p.equity])
          .toList(),
      'clauses': s.records.map((r) {
        final voteIds = r.votes.keys.toList()..sort();
        return [
          r.key,
          r.status.name,
          r.value,
          r.status == ClauseStatus.agreed ? renderClause(s, r) : null,
          voteIds.map((id) {
            final v = r.votes[id]!;
            return [id, v.ballot.name, t(v.at), v.method.name];
          }).toList(),
        ];
      }).toList(),
      'signOffs': sortedSign.map((id) {
        final so = s.signOffs[id]!;
        return [id, digest(so.signaturePng), t(so.at), so.method.name, so.draftHash];
      }).toList(),
      'witnesses': s.witnesses
          .map((w) => [w.name, w.nationalId, w.internal, w.phone, digest(w.signaturePng), w.draftHash])
          .toList(),
      'completedAt': s.completedAt == null ? null : t(s.completedAt!),
    });
  }

  String computeHash(ContractSession s) =>
      sha256.convert(utf8.encode(canonicalContent(s))).toString();

  /// يتحقق من أن محتوى العقد المعتمد لم يتغير منذ اعتماده
  bool verifyHash(ContractSession s) =>
      s.contentHash != null && s.contentHash == computeHash(s);

  /// أول بند لم يُحسم بعد (يتخطى المؤجل)
  int nextPendingIndex(ContractSession s, {int from = 0}) {
    for (var i = from; i < s.records.length; i++) {
      final st = s.records[i].status;
      if (st == ClauseStatus.pending || st == ClauseStatus.rejected) return i;
    }
    for (var i = 0; i < from && i < s.records.length; i++) {
      final st = s.records[i].status;
      if (st == ClauseStatus.pending || st == ClauseStatus.rejected) return i;
    }
    return -1;
  }

  // ───────────── صياغة البنود ─────────────

  String formatValue(ContractSession s, BankQuestion q, double? v) {
    if (v == null) return '—';
    return switch (q.paramKind) {
      ParamKind.money => formatCurrency(v, s.currency),
      ParamKind.percent => v.toStringAsFixed(v % 1 == 0 ? 0 : 2),
      _ => v.toStringAsFixed(v % 1 == 0 ? 0 : 1),
    };
  }

  String renderClause(ContractSession s, ClauseRecord r) {
    final q = question(r.questionId);
    final partner = r.concernedPartnerId == null
        ? null
        : s.partners.firstWhere((p) => p.id == r.concernedPartnerId,
            orElse: () => s.partners.first);
    return q.clauseTemplate
        .replaceAll('{value}', formatValue(s, q, r.value))
        .replaceAll('{capital}', formatCurrency(s.capital, s.currency))
        .replaceAll('{currency}', s.currency.label)
        .replaceAll('{partner}', partner?.name ?? '');
  }

  /// القواعد الرقابية المولدة من البنود المالية المعتمدة (تُغذي محرك الرقابة لاحقاً)
  List<String> generatedRules(ContractSession s) {
    final out = <String>[];
    for (final r in s.records) {
      if (r.status != ClauseStatus.agreed) continue;
      final q = question(r.questionId);
      final rule = q.rule;
      if (q.effect != EffectType.financial || rule == null) continue;
      final threshold = r.value == null ? '' : ' ${rule.op.symbol} ${formatValue(s, q, r.value)}'
          '${q.paramKind == ParamKind.percent ? '%' : ''}';
      out.add('إذا كان ${rule.fieldLabel}$threshold: ${rule.action}');
    }
    return out;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    detachCloud();
    super.dispose();
  }
}
