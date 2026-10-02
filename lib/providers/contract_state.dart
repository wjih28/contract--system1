import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' show FieldPath, QuerySnapshot;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/question_bank.dart';
import '../models/company.dart' show ActorType;
import '../models/governance_config.dart';
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

  /// توقيع تعديل البند (الجولة + التأجيل/التحييد) لاكتشاف تعارض التحديث بين الأجهزة
  static String editSig(ClauseRecord r) => '${r.key}:${r.round}:'
      '${r.status == ClauseStatus.deferred || r.status == ClauseStatus.neutralized ? r.status.name : '-'}';

  /// آخر تعديل قام به هذا الجهاز، حتى لا يُعرض كتعارض
  String? lastLocalEdit;

  /// جلسة التأسيس للشركة (الإصدار 1، واحدة لكل شركة)
  ContractSession? establishmentFor(String? companyId) => companyId == null
      ? null
      : sessions.where((s) => s.companyId == companyId && s.version == 1).firstOrNull;

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

  // ───────────── إعدادات الحوكمة: مكتبة البنود، القواعد، الشروط، العملات ─────────────

  static const _configKey = 'governance_config_v1';

  /// كل إصدارات البنود والقواعد محفوظة؛ الحالي هو أعلى إصدار منشور
  List<LegalClause> clauseVersions = [];
  List<LogicRule> ruleVersions = [];
  Map<String, QuestionCondition> conditions = {};
  List<CurrencySetting> currencies = AppCurrency.values.map((c) => CurrencySetting(currency: c)).toList();

  /// بذر المكتبة من بنك الأسئلة عند أول تشغيل
  void _seedConfig() {
    final now = DateTime.now();
    for (final q in bank) {
      if (!clauseVersions.any((c) => c.questionId == q.id)) {
        clauseVersions.add(LegalClause(
          id: 'CL-${q.id}',
          questionId: q.id,
          title: q.title,
          text: q.clauseTemplate,
          category: q.category,
          updatedAt: now,
        ));
      }
      final r = q.rule;
      if (r != null && !ruleVersions.any((x) => x.questionId == q.id)) {
        ruleVersions.add(LogicRule(
          id: 'R-${q.id}',
          name: q.title,
          questionId: q.id,
          clauseId: 'CL-${q.id}',
          conditions: [
            RuleCondition(field: r.field, fieldLabel: r.fieldLabel, op: r.op, isEvent: q.paramKind == ParamKind.none),
          ],
          actions: [r.action],
        ));
      }
    }
  }

  T? _latest<T>(Iterable<T> items, int Function(T) version) {
    T? best;
    for (final x in items) {
      if (best == null || version(x) > version(best)) best = x;
    }
    return best;
  }

  /// البند المنشور الحالي لسؤال
  LegalClause? publishedClause(String questionId) => _latest(
      clauseVersions.where((c) => c.questionId == questionId && c.status == ConfigStatus.published), (c) => c.version);

  /// أحدث إصدار (قد يكون مسودة) للتحرير
  LegalClause? latestClause(String questionId) =>
      _latest(clauseVersions.where((c) => c.questionId == questionId), (c) => c.version);

  LogicRule? publishedRule(String questionId) => _latest(
      ruleVersions.where((r) => r.questionId == questionId && r.status == ConfigStatus.published), (r) => r.version);

  LogicRule? latestRule(String questionId) =>
      _latest(ruleVersions.where((r) => r.questionId == questionId), (r) => r.version);

  /// حفظ مسودة بند: إن كان الأحدث منشوراً يُنشأ إصدار جديد، والمنشور يبقى كما هو
  void saveClauseDraft(String questionId, {required String title, required String text}) {
    final cur = latestClause(questionId);
    if (cur == null) return;
    if (cur.status == ConfigStatus.draft) {
      clauseVersions[clauseVersions.indexOf(cur)] = cur.copyWith(title: title, text: text);
    } else {
      clauseVersions.add(cur.copyWith(title: title, text: text, version: cur.version + 1, status: ConfigStatus.draft));
    }
    _saveConfig();
  }

  /// نشر المسودة: تُستخدم في الجلسات الجديدة فقط، والجلسات القائمة تحتفظ بلقطتها
  void publishClause(String questionId) {
    final cur = latestClause(questionId);
    if (cur == null || cur.status != ConfigStatus.draft) return;
    clauseVersions[clauseVersions.indexOf(cur)] = cur.copyWith(status: ConfigStatus.published);
    _saveConfig();
  }

  void saveRuleDraft(LogicRule rule) {
    final cur = latestRule(rule.questionId);
    if (cur != null && cur.status == ConfigStatus.draft) {
      ruleVersions[ruleVersions.indexOf(cur)] = rule.copyWith(version: cur.version, status: ConfigStatus.draft);
    } else {
      ruleVersions.add(rule.copyWith(version: (cur?.version ?? 0) + 1, status: ConfigStatus.draft));
    }
    _saveConfig();
  }

  /// نشر القاعدة بعد التحقق؛ يُرجع أخطاء التحقق إن وجدت
  List<String> publishRule(String questionId) {
    final cur = latestRule(questionId);
    if (cur == null || cur.status != ConfigStatus.draft) return const [];
    final errors = cur.validate();
    if (errors.isNotEmpty) return errors;
    ruleVersions[ruleVersions.indexOf(cur)] = cur.copyWith(status: ConfigStatus.published);
    _saveConfig();
    return const [];
  }

  /// A07: تعيين شرط ظهور سؤال أو إزالته، مع منع الاعتماد الدائري
  String? setCondition(String questionId, QuestionCondition? c) {
    if (c == null) {
      conditions.remove(questionId);
      _saveConfig();
      return null;
    }
    if (c.sourceQuestionId == questionId) return 'لا يمكن أن يعتمد السؤال على نفسه';
    var cursor = conditions[c.sourceQuestionId];
    final seen = <String>{c.sourceQuestionId};
    while (cursor != null) {
      if (cursor.sourceQuestionId == questionId) return 'اعتماد دائري: السؤال المصدر يعتمد على هذا السؤال';
      if (!seen.add(cursor.sourceQuestionId)) break;
      cursor = conditions[cursor.sourceQuestionId];
    }
    conditions[questionId] = c;
    _saveConfig();
    return null;
  }

  void setCurrency(CurrencySetting c) {
    final i = currencies.indexWhere((x) => x.currency == c.currency);
    if (i >= 0) {
      // يجب أن تبقى عملة واحدة مفعّلة على الأقل
      if (!c.enabled && currencies.where((x) => x.enabled).length <= 1) return;
      currencies[i] = c;
      _saveConfig();
    }
  }

  List<AppCurrency> get enabledCurrencies =>
      currencies.where((c) => c.enabled).map((c) => c.currency).toList();

  Future<void> _loadConfig(SharedPreferences prefs) async {
    final raw = prefs.getString(_configKey);
    if (raw != null) {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      clauseVersions = (j['clauses'] as List? ?? [])
          .map((e) => LegalClause.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      ruleVersions = (j['rules'] as List? ?? [])
          .map((e) => LogicRule.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      conditions = (j['conditions'] as Map? ?? {}).map(
        (k, v) => MapEntry(k as String, QuestionCondition.fromJson(Map<String, dynamic>.from(v as Map))),
      );
      final cur = (j['currencies'] as List? ?? [])
          .map((e) => CurrencySetting.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (cur.isNotEmpty) currencies = cur;
    }
    _seedConfig();
  }

  void _saveConfig() {
    notifyListeners();
    SharedPreferences.getInstance().then((prefs) => prefs.setString(
          _configKey,
          jsonEncode({
            'clauses': clauseVersions.map((c) => c.toJson()).toList(),
            'rules': ruleVersions.map((r) => r.toJson()).toList(),
            'conditions': conditions.map((k, v) => MapEntry(k, v.toJson())),
            'currencies': currencies.map((c) => c.toJson()).toList(),
          }),
        ));
  }

  /// لقطة الإعدادات المنشورة في سجل البند عند إنشاء الجلسة
  void _snapshot(ClauseRecord r) {
    final cl = publishedClause(r.questionId);
    r.clauseText = cl?.text;
    r.clauseVersion = cl?.version;
    r.rule = publishedRule(r.questionId)?.toJson();
    r.showIf = conditions[r.questionId]?.toJson();
  }

  /// A07: هل ينطبق البند؟ null = لم يُحسم البند المصدر بعد
  bool? applicable(ContractSession s, ClauseRecord r) {
    final j = r.showIf;
    if (j == null) return true;
    final c = QuestionCondition.fromJson(j);
    final src = s.records.where((x) => x.questionId == c.sourceQuestionId).firstOrNull;
    if (src == null) return true;
    final st = src.status;
    // البند المصدر لم يُحسم بعد (معلّق أو مؤجل)؛ الرفض أو الجمود يُعامل كعدم اعتماد حتى يُعاد التصويت
    if (st == ClauseStatus.pending || st == ClauseStatus.deferred) return null;
    final agreed = st == ClauseStatus.agreed;
    return switch (c.kind) {
      ConditionKind.agreed => agreed,
      ConditionKind.notAgreed => !agreed,
      ConditionKind.valueCompare => agreed && src.value != null && (c.op ?? ComparisonOp.eq).evaluate(src.value!, c.value ?? 0),
    };
  }


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
      'records': {for (final r in s.records) r.key: _recordToRemote(r, carried: s.isAmendment && !r.amended)},
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
      'version': s.version,
      'changeType': s.changeType.name,
      'amends': s.amends,
      'changeSummary': s.changeSummary,
      'proposedBy': s.proposedBy,
      'disputeRef': s.disputeRef,
      'supersededBy': null,
      'archivedAt': null,
    };
  }

  Map<String, dynamic> _recordToRemote(ClauseRecord r, {bool carried = false}) => {
        // بند منقول كما هو من الإصدار السابق: يحتفظ بحالته وأصواته دون تصويت جديد
        if (carried) 'carriedStatus': r.status.name,
        if (carried) 'carriedVotes': r.votes.map((k, v) => MapEntry(k, v.toJson())),
        'amended': r.amended,
        'previousValue': r.previousValue,
        'questionId': r.questionId,
        'concernedPartnerId': r.concernedPartnerId,
        'value': r.value,
        'round': r.round,
        'openedAt': r.openedAt?.toUtc().toIso8601String(),
        'failures': r.failures,
        'notes': r.notes.map((n) => n.toJson()).toList(),
        'deferReason': r.deferReason,
        'clauseText': r.clauseText,
        'clauseVersion': r.clauseVersion,
        'rule': r.rule,
        'showIf': r.showIf,
        'flag': carried ? 'carried' : switch (r.status) {
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
      version: (d['version'] as num?)?.toInt() ?? 1,
      changeType: ChangeType.values.byName(d['changeType'] as String? ?? 'establishment'),
      amends: d['amends'] as String?,
      changeSummary: d['changeSummary'] as String?,
      proposedBy: d['proposedBy'] as String?,
      disputeRef: d['disputeRef'] as String?,
      supersededBy: d['supersededBy'] as String?,
      archivedAt: d['archivedAt'] == null ? null : remoteTime(d['archivedAt']),
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
        clauseText: m['clauseText'] as String?,
        clauseVersion: (m['clauseVersion'] as num?)?.toInt(),
        rule: m['rule'] == null ? null : Map<String, dynamic>.from(m['rule'] as Map),
        showIf: m['showIf'] == null ? null : Map<String, dynamic>.from(m['showIf'] as Map),
        amended: m['amended'] as bool? ?? false,
        previousValue: (m['previousValue'] as num?)?.toDouble(),
      );
      if (m['flag'] == 'carried') {
        r.status = ClauseStatus.values.byName(m['carriedStatus'] as String);
        r.votes = Map<String, dynamic>.from(m['carriedVotes'] as Map? ?? {}).map(
            (k, v) => MapEntry(k, PartnerVote.fromJson(Map<String, dynamic>.from(v as Map))));
        s.records.add(r);
        continue;
      }
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

  void _remoteRecord(ContractSession s, ClauseRecord r) {
    lastLocalEdit = editSig(r);
    _remote(s, {FieldPath(['records', r.key]): _recordToRemote(r, carried: s.isAmendment && !r.amended)});
  }

  // ───────────── التخزين المحلي ─────────────

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final custom = prefs.getString(_customBankKey);
      await _loadConfig(prefs);
      if (custom != null) {
        _customQuestions
          ..clear()
          ..addAll((jsonDecode(custom) as List)
              .map((e) => BankQuestion.fromJson(e as Map<String, dynamic>)));
        _seedConfig();
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
    _refreshConditional(s);
    s.updatedAt = DateTime.now();
    notifyListeners();
    _persist();
  }

  // ───────────── بنك الأسئلة ─────────────

  void addQuestion(BankQuestion q) {
    _customQuestions.add(q);
    _seedConfig();
    _saveConfig();
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
    records.forEach(_snapshot);
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
    // بند مشروط: لا ينطبق إذا لم يتحقق شرطه، ويبقى معلقاً حتى يُحسم البند المصدر
    final app = applicable(s, r);
    if (app == false) return ClauseStatus.notApplicable;
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
    // J04: تكرار الفشل حتى الجمود يفتح تذكرة نزاع دائمة (المكرر يُهمَل عند الفتح)
    if (st == ClauseStatus.deadlock) onDeadlock?.call(s, r);
  }

  /// يُستدعى عند وصول بند إلى الجمود؛ يضبطه مزوّد النزاعات
  void Function(ContractSession s, ClauseRecord r)? onDeadlock;

  /// إعادة احتساب البنود المشروطة بعد تغيّر نتيجة أي بند
  void _refreshConditional(ContractSession s) {
    for (final r in s.records) {
      if (r.showIf == null) continue;
      if (r.status == ClauseStatus.notApplicable) r.status = ClauseStatus.pending;
      if (r.status == ClauseStatus.pending) _applyDerived(s, r);
    }
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
        if (s.isAmendment) 'version': [s.version, s.amends, s.changeType.name, s.disputeRef],
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
    final unsigned = signersOf(s).where((p) {
      final so = s.signOffs[p.id];
      return so == null || !signOffValid(s, so);
    }).length;
    if (unsigned > 0) out.add('$unsigned شركاء لم يوقّعوا على الإصدار الحالي');
    final w = s.witnesses.where((x) => witnessValid(s, x)).length;
    if (w < minWitnesses) out.add('الشهود: $w من $minWitnesses شهدوا على الإصدار الحالي');
    return out;
  }

  /// الموقّعون المطلوبون: كل الشركاء، وفي تعديل جدول الحصص أصحاب الحصص بعد التعديل
  List<SessionPartner> signersOf(ContractSession s) => s.changeType == ChangeType.capTable
      ? s.partners.where((p) => p.equity > 0).toList()
      : s.partners;

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
    _audit(s, s.isAmendment ? 'اعتماد الإصدار ${s.version} من العقد' : 'اعتماد العقد النهائي',
        objectType: 'contract', objectId: s.id, result: 'العقد مقفل للقراءة فقط',
        evidence: 'SHA-256: ${s.contentHash}');
    // الإصدار الجديد يحل محل السابق: يُقفل السابق ويُؤرشف للقراءة فقط
    final base = s.amends == null ? null : sessions.where((x) => x.id == s.amends).firstOrNull;
    if (base != null) {
      base.supersededBy = s.id;
      base.archivedAt = DateTime.now().toUtc();
      _remote(base, {'supersededBy': s.id, 'archivedAt': base.archivedAt!.toIso8601String()});
      _audit(base, 'أرشفة الإصدار ${base.version} بعد اعتماد الإصدار ${s.version}',
          objectType: 'contract', objectId: base.id, result: 'مؤرشف للقراءة فقط', actorSystem: true);
    }
    onVersionCompleted?.call(s);
    _touch(s);
  }

  // ───────────── الإصدارات والتعديل (المرحلة 3) ─────────────

  /// يُستدعى بعد اعتماد أي إصدار: تحديث رقم إصدار الشركة وجدول الحصص
  void Function(ContractSession s)? onVersionCompleted;

  /// هل تعديلات العقد مقفلة الآن (نزاع قائم)؟ يضبطها مزوّد النزاعات
  bool Function(String companyId)? amendmentLocked;

  /// إصدارات عقد الشركة بالترتيب من الأقدم
  List<ContractSession> versionsFor(String? companyId) =>
      sessionsFor(companyId)..sort((a, b) => a.version.compareTo(b.version));

  /// الإصدار الساري: آخر إصدار معتمد غير مؤرشف. منه تُستخرج قواعد الرقابة.
  ContractSession? currentContract(String? companyId) {
    ContractSession? best;
    for (final s in sessionsFor(companyId)) {
      if (s.status != SessionStatus.completed || s.archived) continue;
      if (best == null || s.version > best.version) best = s;
    }
    return best;
  }

  /// مقترح تعديل قائم لم يُعتمد ولم يُنهَ
  ContractSession? activeAmendment(String? companyId) => sessionsFor(companyId)
      .where((s) => s.isAmendment && s.status != SessionStatus.completed && s.status != SessionStatus.withdrawn)
      .firstOrNull;

  /// ما يمنع تقديم مقترح تعديل الآن
  String? amendmentBlocker(String companyId, {String? disputeRef}) {
    if (currentContract(companyId) == null) return 'لا يوجد عقد معتمد بعد';
    if (activeAmendment(companyId) != null) return 'يوجد مقترح تعديل قائم: أكملوه أو أنهوه أولاً';
    if (disputeRef == null && (amendmentLocked?.call(companyId) ?? false)) {
      return 'تعديلات العقد وجدول الحصص مقفلة مؤقتاً بسبب نزاع قائم';
    }
    return null;
  }

  /// البنود التي يمكن تعديل قيمتها: المتفق عليها ولها قيمة
  List<ClauseRecord> amendableRecords(ContractSession base) => base.records
      .where((r) =>
          r.status == ClauseStatus.agreed && r.value != null && question(r.questionId).paramKind != ParamKind.none)
      .toList();

  /// J03: مقترح تعديل قيم بنود معتمدة. يُنشئ مسودة إصدار جديد؛ البنود المعدّلة فقط تُطرح للتصويت
  /// والباقي يُنقل كما هو. الإصدار الساري يبقى نافذاً حتى يُعتمد الجديد.
  ContractSession proposeAmendment(ContractSession base,
      {required Map<String, double> changes, required String reason, required String proposedBy, String? disputeRef}) {
    final records = base.records.map((r) {
      final c = r.clone();
      final v = changes[r.key];
      if (v != null && v != r.value) {
        c
          ..amended = true
          ..previousValue = r.value
          ..value = v
          ..status = ClauseStatus.pending
          ..votes = {}
          ..round = 1
          ..openedAt = null
          ..failures = 0
          ..resolvedAt = null
          ..notes = [];
      } else {
        c
          ..amended = false
          ..previousValue = null;
      }
      return c;
    }).toList();
    final changed = records.where((r) => r.amended).map((r) => question(r.questionId).title).join('، ');
    return _newVersion(base,
        records: records,
        partners: base.partners,
        type: ChangeType.amendment,
        summary: 'تعديل: $changed. السبب: ${reason.trim()}',
        proposedBy: proposedBy,
        disputeRef: disputeRef);
  }

  /// تعديل جدول الحصص نتيجة صلح أو حكم أو تخارج. البنود تُنقل كما هي، ويوقّع أصحاب الحصص الجديدة.
  ContractSession proposeCapTable(ContractSession base,
      {required Map<String, double> equity, required String reason, required String proposedBy, String? disputeRef}) {
    final partners = base.partners
        .map((p) => SessionPartner(
            id: p.id, name: p.name, nationalId: p.nationalId, phone: p.phone, equity: equity[p.id] ?? p.equity))
        .toList();
    final records = base.records
        .map((r) => r.clone()
          ..amended = false
          ..previousValue = null)
        .toList();
    final diff = base.partners
        .where((p) => (equity[p.id] ?? p.equity) != p.equity)
        .map((p) =>
            '${p.name} من ${p.equity.toStringAsFixed(2)}% إلى ${(equity[p.id] ?? p.equity).toStringAsFixed(2)}%')
        .join('، ');
    return _newVersion(base,
        records: records,
        partners: partners,
        type: ChangeType.capTable,
        summary: 'جدول الحصص: $diff. السبب: ${reason.trim()}',
        proposedBy: proposedBy,
        disputeRef: disputeRef);
  }

  ContractSession _newVersion(ContractSession base,
      {required List<ClauseRecord> records,
      required List<SessionPartner> partners,
      required ChangeType type,
      required String summary,
      required String proposedBy,
      String? disputeRef}) {
    final now = DateTime.now();
    final s = ContractSession(
      id: 'S${now.microsecondsSinceEpoch}',
      companyId: base.companyId,
      companyName: base.companyName,
      companyType: base.companyType,
      currency: base.currency,
      capital: base.capital,
      partners: partners,
      records: records,
      createdAt: now,
      updatedAt: now,
      settings: base.settings,
      version: base.version + 1,
      changeType: type,
      amends: base.id,
      changeSummary: summary,
      proposedBy: proposedBy,
      disputeRef: disputeRef,
    );
    sessions.insert(0, s);
    if (isCloud) {
      _cloud!
          .create(s.id, sessionToRemote(s, uid: _myUid!))
          .catchError((Object e) => debugPrint('تعذر إنشاء مقترح التعديل في الخادم: $e'));
    }
    _audit(s, 'مقترح ${type.label} (الإصدار ${s.version})', objectType: 'contract', objectId: s.id,
        result: summary, evidence: 'يعدّل الإصدار ${base.version}${disputeRef == null ? '' : '، نزاع $disputeRef'}');
    _touch(s);
    return s;
  }

  /// إنهاء مقترح تعديل لم يُعتمد. يبقى محفوظاً في سجل الإصدارات ولا يُحذف.
  void withdrawAmendment(ContractSession s, {required String reason}) {
    if (!s.isAmendment || s.status == SessionStatus.completed) return;
    s.status = SessionStatus.withdrawn;
    _remote(s, {'status': s.status.name});
    _audit(s, 'إنهاء مقترح التعديل (الإصدار ${s.version}) دون اعتماد', objectType: 'contract', objectId: s.id,
        result: reason.trim().isEmpty ? 'لم يُعتمد' : reason.trim());
    _touch(s);
  }

  /// مقارنة إصدارين: البنود التي اختلفت قيمتها أو نصها أو حالتها، والحصص
  List<VersionDiff> compare(ContractSession a, ContractSession b) {
    final out = <VersionDiff>[];
    for (final id in {...a.partners.map((x) => x.id), ...b.partners.map((x) => x.id)}) {
      final pa = a.partners.where((x) => x.id == id).firstOrNull;
      final pb = b.partners.where((x) => x.id == id).firstOrNull;
      if (pa?.equity != pb?.equity) {
        out.add(VersionDiff(
          title: 'حصة ${(pb ?? pa)!.name}',
          before: pa == null ? '—' : '${pa.equity.toStringAsFixed(2)}%',
          after: pb == null ? '—' : '${pb.equity.toStringAsFixed(2)}%',
        ));
      }
    }
    for (final rb in b.records) {
      final ra = a.records.where((x) => x.key == rb.key).firstOrNull;
      final q = question(rb.questionId);
      String show(ContractSession s, ClauseRecord? r) => r == null
          ? 'غير موجود'
          : r.status == ClauseStatus.agreed
              ? formatValue(s, q, r.value)
              : r.status.label;
      final before = show(a, ra), after = show(b, rb);
      final textA = ra == null || ra.status != ClauseStatus.agreed ? null : renderClause(a, ra);
      final textB = rb.status != ClauseStatus.agreed ? null : renderClause(b, rb);
      if (before != after || textA != textB) {
        out.add(VersionDiff(title: q.title, before: before, after: after, textBefore: textA, textAfter: textB));
      }
    }
    return out;
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
      // يدخل رقم الإصدار ومرجعه في البصمة للإصدارات المعدّلة فقط، حتى تبقى بصمات عقود التأسيس القائمة صحيحة
      if (s.isAmendment) 'version': [s.version, s.amends, s.changeType.name, s.disputeRef, s.changeSummary],
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
    return (r.clauseText ?? q.clauseTemplate)
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
      if (q.effect != EffectType.financial) continue;
      // القاعدة كما كانت منشورة عند إنشاء الجلسة، أو القالب الأصلي للجلسات القديمة
      final snap = r.rule == null ? null : LogicRule.fromJson(r.rule!);
      if (snap != null) {
        final v = r.value == null
            ? null
            : '${formatValue(s, q, r.value)}${q.paramKind == ParamKind.percent ? '%' : ''}';
        out.add(snap.describe(value: (_) => v ?? 'القيمة المتفق عليها'));
        continue;
      }
      final rule = q.rule;
      if (rule == null) continue;
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
