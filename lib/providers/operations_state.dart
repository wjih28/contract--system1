import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/company.dart';
import '../models/operations.dart';
import '../models/questionnaire.dart';
import '../services/rule_engine.dart';
import '../widgets/common_widgets.dart';
import 'contract_state.dart';

/// حالة التشغيل والرقابة المالية: العمليات، الاستثناءات، المخالفات، الإشعارات.
/// كل عملية تمر ببوابة الفحص (RuleEngine) مقابل قواعد العقد المعتمد قبل قبولها.
class OperationsState extends ChangeNotifier {
  static const _key = 'operations_v1';

  List<FinancialTx> transactions = [];
  List<ExceptionRequest> exceptions = [];
  List<Violation> violations = [];
  List<AppNotification> notifications = [];
  List<MessageTemplate> templates = _defaultTemplates;

  /// تفضيلات الإشعار لكل عضو: الفئات المفعّلة غير الإلزامية
  Map<String, Set<NotifCategory>> mutedByMember = {};

  AuditSink? auditSink;
  bool loaded = false;

  // ───────────── القوالب الافتراضية (A15) ─────────────
  static const _defaultTemplates = [
    MessageTemplate(
      id: 'T-FROZEN',
      event: 'تجميد عملية',
      subject: 'تنبيه حوكمة: عملية مجمّدة في {company}',
      body: 'جُمّدت عملية بقيمة {amount} لصالح {payee} لأنها تتجاوز قاعدة "{rule}" (الحد في العقد {limit}). يلزم قرار الشركاء.',
      mandatory: true,
    ),
    MessageTemplate(
      id: 'T-VIOLATION',
      event: 'تسجيل مخالفة',
      subject: 'إنذار: مخالفة مسجلة في {company}',
      body: 'سُجّلت مخالفة لقاعدة "{rule}" على عملية بقيمة {amount} لصالح {payee}.',
      mandatory: true,
    ),
    MessageTemplate(
      id: 'T-EXCEPTION',
      event: 'طلب استثناء',
      subject: 'طلب استثناء بانتظار قرارك في {company}',
      body: 'طُلب استثناء لمرة واحدة لعملية بقيمة {amount} لصالح {payee} تتجاوز قاعدة "{rule}" ({limit}). الموافقة لا تعدّل العقد.',
    ),
    MessageTemplate(
      id: 'T-DECISION',
      event: 'قرار استثناء',
      subject: 'قرار الشركاء في طلب الاستثناء',
      body: 'صدر قرار الشركاء في استثناء العملية بقيمة {amount} لصالح {payee}: {rule}.',
    ),
  ];

  // ───────────── التحميل والحفظ ─────────────

  FirebaseFirestore? _db;
  String? _watchedCompany;
  final List<StreamSubscription> _subs = [];

  bool get isCloud => _db != null;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        if (!isCloud) {
          transactions = _list(j['tx'], FinancialTx.fromJson);
          exceptions = _list(j['ex'], ExceptionRequest.fromJson);
          violations = _list(j['vi'], Violation.fromJson);
          notifications = _list(j['no'], AppNotification.fromJson);
        }
        final t = _list(j['templates'], MessageTemplate.fromJson);
        if (t.isNotEmpty) templates = t;
        mutedByMember = (j['muted'] as Map? ?? {}).map((k, v) => MapEntry(
            k as String, (v as List).map((c) => NotifCategory.values.byName(c as String)).toSet()));
      }
    } catch (e) {
      debugPrint('تعذر تحميل بيانات التشغيل: $e');
    }
    loaded = true;
    notifyListeners();
  }

  static List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) f) =>
      (raw as List? ?? []).map((e) => f(Map<String, dynamic>.from(e as Map))).toList();

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          if (!isCloud) 'tx': transactions.map((e) => e.toJson()).toList(),
          if (!isCloud) 'ex': exceptions.map((e) => e.toJson()).toList(),
          if (!isCloud) 'vi': violations.map((e) => e.toJson()).toList(),
          if (!isCloud) 'no': notifications.map((e) => e.toJson()).toList(),
          'templates': templates.map((e) => e.toJson()).toList(),
          'muted': mutedByMember.map((k, v) => MapEntry(k, v.map((c) => c.name).toList())),
        }),
      );
    } catch (e) {
      debugPrint('تعذر حفظ بيانات التشغيل: $e');
    }
  }

  void _changed() {
    notifyListeners();
    _persist();
  }

  // ───────────── وضع الخادم ─────────────

  Future<void> attachCloud(FirebaseFirestore db) async {
    await detachCloud();
    _db = db;
    transactions = [];
    exceptions = [];
    violations = [];
    notifications = [];
    notifyListeners();
  }

  Future<void> detachCloud() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _db = null;
    _watchedCompany = null;
  }

  /// متابعة بيانات الشركة الحالية لحظياً
  void watchCompany(String? companyId) {
    if (_db == null || companyId == null || companyId == _watchedCompany) return;
    _watchedCompany = companyId;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    final base = _db!.collection('companies').doc(companyId);
    void listen<T>(String col, T Function(Map<String, dynamic>) f, void Function(List<T>) set) {
      _subs.add(base.collection(col).snapshots().listen((snap) {
        set(snap.docs.map((d) => f({...d.data(), 'id': d.id})).toList());
        notifyListeners();
      }, onError: (Object e) => debugPrint('تعذر قراءة $col: $e')));
    }

    listen('transactions', FinancialTx.fromJson, (l) => transactions = l);
    listen('exceptions', ExceptionRequest.fromJson, (l) => exceptions = l);
    listen('violations', Violation.fromJson, (l) => violations = l);
    listen('notifications', AppNotification.fromJson, (l) => notifications = l);
  }

  void _put(String companyId, String col, String id, Map<String, dynamic> data) {
    _db?.collection('companies').doc(companyId).collection(col).doc(id).set(data).then(
          (_) {},
          onError: (Object e) => debugPrint('تعذر حفظ $col: $e'),
        );
  }

  // ───────────── الاستعلامات ─────────────

  List<FinancialTx> txFor(String? cid) =>
      transactions.where((t) => t.companyId == cid).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<ExceptionRequest> exceptionsFor(String? cid) =>
      exceptions.where((e) => e.companyId == cid).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<Violation> violationsFor(String? cid) =>
      violations.where((v) => v.companyId == cid).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<AppNotification> notificationsFor(String? cid, String? memberId) => notifications
      .where((n) => n.companyId == cid && (memberId == null || n.recipientId == memberId))
      .toList()
    ..sort((a, b) => b.sentAt.compareTo(a.sentAt));

  FinancialTx? tx(String id) => transactions.where((t) => t.id == id).firstOrNull;

  ExceptionRequest? exceptionForTx(String txId) =>
      exceptions.where((e) => e.txId == txId).toList().lastOrNull;

  /// إجمالي المصروفات المقبولة في شهر العملية (للسقف الشهري)
  double monthOutflow(String companyId, DateTime month, AppCurrency currency, {String? excludeId}) => transactions
      .where((t) =>
          t.companyId == companyId &&
          t.id != excludeId &&
          t.currency == currency &&
          t.category.isOutflow &&
          t.date.year == month.year &&
          t.date.month == month.month &&
          (t.status == TxStatus.allowed || t.status == TxStatus.releasedException))
      .fold(0, (a, t) => a + t.amount);

  /// القواعد السارية للشركة من عقدها المعتمد
  List<ActiveRule> activeRules(ContractState cs, String companyId) {
    final s = cs.establishmentFor(companyId);
    if (s == null) return const [];
    return RuleEngine.activeRules(
      s,
      (q, v) => v == null ? '' : '${cs.formatValue(s, q, v)}${q.paramKind == ParamKind.percent ? '%' : ''}',
      cs.question,
    );
  }

  // ───────────── العمليات وبوابة الفحص ─────────────

  /// معاينة نتيجة الفحص قبل الإرسال (O03) دون حفظ
  List<RuleCheck> preview(ContractState cs, Company c, FinancialTx draft) => RuleEngine.evaluate(
        draft,
        activeRules(cs, c.id),
        monthOutflow: monthOutflow(c.id, draft.date, draft.currency),
      );

  /// تسجيل عملية وتمريرها ببوابة الفحص. الإرسال لا يعني الموافقة؛ النتيجة تظهر بعد التقييم.
  FinancialTx submit(ContractState cs, Company c, FinancialTx tx, {required String actorName}) {
    final session = cs.establishmentFor(c.id);
    tx.checks = preview(cs, c, tx);
    tx.status = RuleEngine.outcome(tx.checks);
    tx.evaluatedAt = DateTime.now();
    tx.contractRef = session?.id;
    transactions.add(tx);
    _put(c.id, 'transactions', tx.id, tx.toJson());

    _log(c.id, 'تسجيل عملية ${tx.category.label} بقيمة ${formatCurrency(tx.amount, tx.currency)} لصالح ${tx.payee}',
        'transaction', tx.id, 'بانتظار الفحص');
    final hits = tx.triggered;
    _log(
      c.id,
      'فحص العملية مقابل ${tx.checks.length} قواعد من العقد',
      'transaction',
      tx.id,
      tx.status.label,
      actor: ActorType.ruleEngine,
      evidence: hits.isEmpty ? null : hits.map((h) => '${h.ruleId} ج${h.ruleVersion}').join('، '),
    );

    final vars = _vars(c, tx, hits.firstOrNull);
    if (tx.status == TxStatus.frozen) {
      _notifyPartners(c, NotifCategory.legal, 'T-FROZEN', vars, 'transaction', tx.id);
    } else if (tx.status == TxStatus.violation) {
      _createViolation(c, tx, hits.firstWhere((h) => h.autoViolation), origin: 'تلقائية من قاعدة العقد');
    }
    _changed();
    return tx;
  }

  Map<String, String> _vars(Company c, FinancialTx tx, RuleCheck? h) => {
        'company': c.legalName,
        'amount': formatCurrency(tx.amount, tx.currency),
        'payee': tx.payee,
        'rule': h?.ruleName ?? '',
        'limit': h?.expected ?? '',
      };

  void addTxNote(Company c, FinancialTx tx, String note) {
    if (note.trim().isEmpty) return;
    tx.notes = [...tx.notes, note.trim()];
    _put(c.id, 'transactions', tx.id, tx.toJson());
    _log(c.id, 'ملاحظة على العملية ${tx.id}', 'transaction', tx.id, note.trim());
    _changed();
  }

  // ───────────── الاستثناءات (P16 / O06) ─────────────

  /// طلب استثناء لمرة واحدة لعملية مجمّدة. لا يعدّل القاعدة ولا العقد.
  ExceptionRequest requestException(Company c, FinancialTx tx, RuleCheck check,
      {required String reason, required String requestedBy, int days = 3}) {
    final now = DateTime.now();
    final ex = ExceptionRequest(
      id: 'X${now.millisecondsSinceEpoch}',
      companyId: c.id,
      txId: tx.id,
      ruleId: check.ruleId,
      ruleName: check.ruleName,
      originalLimit: check.expected,
      requestedAmount: tx.amount,
      reason: reason.trim(),
      requestedBy: requestedBy,
      createdAt: now,
      deadline: now.add(Duration(days: days)),
    );
    exceptions.add(ex);
    tx.status = TxStatus.exceptionPending;
    _put(c.id, 'exceptions', ex.id, ex.toJson());
    _put(c.id, 'transactions', tx.id, tx.toJson());
    _log(c.id, 'طلب استثناء لمرة واحدة للعملية ${tx.id}', 'exception', ex.id, 'السبب: ${ex.reason}');
    _notifyPartners(c, NotifCategory.approval, 'T-EXCEPTION', _vars(c, tx, check), 'exception', ex.id,
        except: {requestedBy});
    _changed();
    return ex;
  }

  /// الشركاء المخوّلون بالتصويت على الاستثناء: كل الشركاء عدا مقدّم الطلب
  List<CompanyMember> eligibleVoters(Company c, ExceptionRequest ex) =>
      c.partners.where((p) => p.id != ex.requestedBy && p.equity > 0).toList();

  /// نسب الموافقة والرفض مرجّحة بالملكية بين المخوّلين
  (double approve, double reject) shares(Company c, ExceptionRequest ex) {
    final voters = eligibleVoters(c, ex);
    final total = voters.fold<double>(0, (a, p) => a + p.equity);
    if (total == 0) return (0, 0);
    double s(bool v) =>
        voters.where((p) => ex.votes[p.id]?.approve == v).fold<double>(0, (a, p) => a + p.equity) / total * 100;
    return (s(true), s(false));
  }

  void voteException(Company c, ExceptionRequest ex, CompanyMember voter,
      {required bool approve, required String method, String? reason}) {
    if (ex.status != ExceptionStatus.pending) return;
    ex.votes = {
      ...ex.votes,
      voter.id: ExceptionVote(partnerId: voter.id, approve: approve, at: DateTime.now(), method: method, reason: reason),
    };
    _log(c.id, '${voter.name} ${approve ? 'وافق على' : 'رفض'} الاستثناء', 'exception', ex.id,
        reason == null || reason.isEmpty ? '' : 'السبب: $reason',
        evidence: 'تأكيد: $method');
    _decide(c, ex);
    _put(c.id, 'exceptions', ex.id, ex.toJson());
    _changed();
  }

  void _decide(Company c, ExceptionRequest ex) {
    final (a, r) = shares(c, ex);
    final tx = this.tx(ex.txId);
    if (tx == null) return;
    if (a + 1e-6 >= ex.threshold) {
      ex.status = ExceptionStatus.approved;
      ex.decidedAt = DateTime.now();
      tx.status = TxStatus.releasedException;
      _log(c.id, 'اعتماد الاستثناء لمرة واحدة والإفراج عن العملية ${tx.id}', 'exception', ex.id,
          'الحد في العقد لم يتغير: ${ex.originalLimit}');
    } else if (r > 100 - ex.threshold + 1e-6) {
      ex.status = ExceptionStatus.rejected;
      ex.decidedAt = DateTime.now();
      tx.status = TxStatus.violation;
      final check = tx.triggered.where((h) => h.ruleId == ex.ruleId).firstOrNull ?? tx.triggered.firstOrNull;
      if (check != null) _createViolation(c, tx, check, origin: 'بعد رفض الشركاء للاستثناء');
    } else {
      return;
    }
    _put(c.id, 'transactions', tx.id, tx.toJson());
    _notifyPartners(c, NotifCategory.approval, 'T-DECISION',
        {..._vars(c, tx, null), 'rule': ex.status.label}, 'exception', ex.id);
  }

  /// انتهاء المهلة دون قرار: الطلب منتهٍ والعملية تبقى مجمّدة
  bool expireOverdue(Company c, {DateTime? now}) {
    final t = now ?? DateTime.now();
    var changed = false;
    for (final ex in exceptionsFor(c.id).where((e) => e.status == ExceptionStatus.pending && t.isAfter(e.deadline))) {
      ex.status = ExceptionStatus.expired;
      ex.decidedAt = t;
      final tx = this.tx(ex.txId);
      if (tx != null) {
        tx.status = TxStatus.frozen;
        _put(c.id, 'transactions', tx.id, tx.toJson());
      }
      _put(c.id, 'exceptions', ex.id, ex.toJson());
      _log(c.id, 'انتهت مهلة طلب الاستثناء دون قرار', 'exception', ex.id, 'العملية تبقى مجمّدة', actor: ActorType.system);
      changed = true;
    }
    if (changed) _changed();
    return changed;
  }

  // ───────────── المخالفات (O12) ─────────────

  void _createViolation(Company c, FinancialTx tx, RuleCheck check, {required String origin}) {
    final v = Violation(
      id: 'V${DateTime.now().microsecondsSinceEpoch}',
      companyId: c.id,
      txId: tx.id,
      ruleId: check.ruleId,
      ruleName: check.ruleName,
      description: '${tx.category.label} بقيمة ${formatCurrency(tx.amount, tx.currency)} لصالح ${tx.payee}: ${check.observed}',
      origin: origin,
      createdAt: DateTime.now(),
    );
    violations.add(v);
    _put(c.id, 'violations', v.id, v.toJson());
    _log(c.id, 'تسجيل مخالفة لقاعدة "${check.ruleName}"', 'violation', v.id, origin,
        actor: ActorType.ruleEngine, evidence: '${check.ruleId} ج${check.ruleVersion}');
    _notifyPartners(c, NotifCategory.violation, 'T-VIOLATION', _vars(c, tx, check), 'violation', v.id);
  }

  void updateViolation(Company c, Violation v,
      {ViolationStatus? status, String? owner, String? corrective, String? evidence}) {
    final before = v.status;
    if (status != null) v.status = status;
    if (owner != null) v.owner = owner;
    if (corrective != null) v.correctiveAction = corrective;
    if (evidence != null && evidence.trim().isNotEmpty) v.evidence = [...v.evidence, evidence.trim()];
    _put(c.id, 'violations', v.id, v.toJson());
    _log(c.id, 'تحديث المخالفة ${v.id}', 'violation', v.id,
        before == v.status ? 'إضافة معلومات' : '${before.label} ← ${v.status.label}');
    _changed();
  }

  // ───────────── الإشعارات (P21 / P22 / A14 / A15) ─────────────

  MessageTemplate template(String id) => templates.firstWhere((t) => t.id == id);

  void updateTemplate(MessageTemplate t, {required String subject, required String body}) {
    final i = templates.indexWhere((x) => x.id == t.id);
    templates = [...templates]..[i] = t.copyWith(subject: subject, body: body);
    _changed();
  }

  /// إرسال إشعار لكل الشركاء. داخل التطبيق يصل فوراً؛ القنوات الخارجية تُسجَّل
  /// كغير مهيأة حتى يُربط مزوّد الرسائل، فلا يُدّعى تسليم لم يحدث.
  void _notifyPartners(Company c, NotifCategory cat, String templateId, Map<String, String> vars,
      String relatedType, String relatedId, {Set<String> except = const {}}) {
    final t = template(templateId);
    final now = DateTime.now();
    for (final p in c.partners.where((p) => !except.contains(p.id))) {
      if (!cat.mandatory && (mutedByMember[p.id]?.contains(cat) ?? false)) continue;
      final n = AppNotification(
        id: 'N${now.microsecondsSinceEpoch}${p.id}',
        companyId: c.id,
        recipientId: p.id,
        category: cat,
        subject: t.renderSubject(vars),
        body: t.render(vars),
        relatedType: relatedType,
        relatedId: relatedId,
        sentAt: now,
        deliveries: [
          DeliveryRecord(channel: NotifChannel.app, status: DeliveryStatus.delivered, messageRef: '${t.id}-v${t.version}', at: now),
          DeliveryRecord(channel: NotifChannel.sms, status: DeliveryStatus.notConfigured, at: now),
          DeliveryRecord(channel: NotifChannel.email, status: DeliveryStatus.notConfigured, at: now),
        ],
      );
      notifications.add(n);
      _put(c.id, 'notifications', n.id, n.toJson());
    }
  }

  void markRead(Company c, AppNotification n) {
    if (n.read) return;
    n.read = true;
    _put(c.id, 'notifications', n.id, n.toJson());
    _changed();
  }

  /// تفضيلات الإشعار: لا يمكن إيقاف الفئات الإلزامية (قانونية، مخالفات)
  void setMuted(String companyId, String memberId, NotifCategory cat, bool muted) {
    if (cat.mandatory) return;
    final s = {...?mutedByMember[memberId]};
    muted ? s.add(cat) : s.remove(cat);
    mutedByMember[memberId] = s;
    _log(companyId, 'تعديل تفضيلات الإشعار', 'preferences', memberId, '${cat.label}: ${muted ? 'موقوفة' : 'مفعّلة'}');
    _changed();
  }

  void _log(String cid, String action, String type, String id, String result,
      {ActorType actor = ActorType.user, String? evidence}) {
    auditSink?.call(cid,
        action: action, objectType: type, objectId: id, result: result, evidenceRef: evidence, actorType: actor);
  }

  @override
  void dispose() {
    detachCloud();
    super.dispose();
  }
}
