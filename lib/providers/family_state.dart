import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/company.dart';
import '../models/family.dart';
import '../widgets/common_widgets.dart' show formatCurrency;
import 'contract_state.dart';

/// الحوكمة العائلية (R09–R14). كل قرار مؤثر (تعديل الدستور، التوزيع، حصر الوراثة، الخلافة)
/// يمر بقرار عائلي مرجّح بالأوزان، وعدم التصويت ليس موافقة.
class FamilyState extends ChangeNotifier {
  static const _key = 'family_v1';

  List<Constitution> constitutions = [];
  List<FamilyPerson> people = [];
  List<InheritanceDeed> deeds = [];
  List<FamilyDistribution> distributions = [];
  List<SuccessionCase> successions = [];
  List<FamilyDecision> decisions = [];
  bool loaded = false;
  AuditSink? auditSink;
  void Function(Company c, String subject, String relatedId)? notifier;
  DateTime Function() now = DateTime.now;

  /// معرّف فريد لا يعتمد على الساعة القابلة للتثبيت في الاختبارات
  int _seq = 0;
  String _id(String prefix) => '$prefix${DateTime.now().microsecondsSinceEpoch}${_seq++}';

  FirebaseFirestore? _db;
  String? _watched;
  final List<StreamSubscription> _subs = [];

  // ───────────── R10 الدستور ─────────────

  List<Constitution> constitutionsFor(String? cid) =>
      constitutions.where((x) => x.companyId == cid).toList()..sort((a, b) => b.version.compareTo(a.version));

  Constitution? current(String? cid) => constitutionsFor(cid).where((x) => x.status == ConstitutionStatus.current).firstOrNull;

  Constitution? pendingDraft(String? cid) => constitutionsFor(cid)
      .where((x) => x.status == ConstitutionStatus.draft || x.status == ConstitutionStatus.pendingApproval)
      .firstOrNull;

  /// مسودة تعديل جديدة من الإصدار الساري (أو مسودة الدستور الأول)
  Constitution startDraft(Company c, {required String by}) {
    final existing = pendingDraft(c.id);
    if (existing != null) return existing;
    final cur = current(c.id);
    final d = Constitution(
      id: _id('FC'),
      companyId: c.id,
      version: (cur?.version ?? 0) + 1,
      sections: cur?.sections.toList() ?? Constitution.starterSections.toList(),
      weightMode: cur?.weightMode ?? WeightMode.equity,
      customWeights: {...?cur?.customWeights},
      distributionRule: cur?.distributionRule ?? DistributionRule.equity,
      customShares: {...?cur?.customShares},
      threshold: cur?.threshold ?? 50.01,
      amendmentThreshold: cur?.amendmentThreshold ?? 66.67,
      createdBy: by,
      createdAt: now(),
    );
    constitutions.add(d);
    _put(c.id, 'constitution', d.id, d.toJson());
    _log(c.id, 'بدء مسودة الدستور العائلي (الإصدار ${d.version})', 'family', d.id, cur == null ? 'الدستور الأول' : 'تعديل');
    _changed();
    return d;
  }

  void saveDraft(Company c, Constitution d) {
    if (d.status != ConstitutionStatus.draft) return;
    _put(c.id, 'constitution', d.id, d.toJson());
    _changed();
  }

  /// رفع المسودة للقرار العائلي بعتبة تعديل الدستور
  FamilyDecision? submitConstitution(Company c, Constitution d, {required String summary, required String by}) {
    if (d.status != ConstitutionStatus.draft || d.sections.isEmpty) return null;
    d
      ..status = ConstitutionStatus.pendingApproval
      ..changeSummary = summary.trim();
    final cur = current(c.id) ?? d;
    final dec = openDecision(c,
        type: FamilyDecisionType.constitution,
        refId: d.id,
        title: 'اعتماد الدستور العائلي (الإصدار ${d.version})',
        details: summary,
        threshold: cur.amendmentThreshold,
        by: by);
    d.decisionRef = dec.id;
    _put(c.id, 'constitution', d.id, d.toJson());
    _changed();
    return dec;
  }

  // ───────────── R14 القرارات العائلية ─────────────

  /// أوزان التصويت حسب الدستور الساري: الملكية افتراضياً، أو أوزان مخصصة
  Map<String, double> weightsFor(Company c) {
    final cur = current(c.id);
    if (cur != null && cur.weightMode == WeightMode.custom && cur.customWeights.isNotEmpty) {
      return {for (final e in cur.customWeights.entries) if (e.value > 0) e.key: e.value};
    }
    return {for (final p in c.partners) if (p.equity > 0) p.id: p.equity};
  }

  List<FamilyDecision> decisionsFor(String? cid) =>
      decisions.where((x) => x.companyId == cid).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  FamilyDecision? decision(String id) => decisions.where((x) => x.id == id).firstOrNull;

  FamilyDecision openDecision(Company c,
      {required FamilyDecisionType type,
      String? refId,
      required String title,
      String details = '',
      double? threshold,
      int days = 7,
      required String by}) {
    final d = FamilyDecision(
      id: _id('FD'),
      companyId: c.id,
      title: title,
      details: details.trim(),
      type: type,
      refId: refId,
      threshold: threshold ?? current(c.id)?.threshold ?? 50.01,
      weights: weightsFor(c),
      deadline: now().add(Duration(days: days)),
      createdBy: by,
      createdAt: now(),
    );
    decisions.add(d);
    _put(c.id, 'familyDecisions', d.id, d.toJson());
    _log(c.id, 'فتح قرار عائلي: $title', 'family', d.id, 'العتبة ${d.threshold.toStringAsFixed(2)}% · المهلة $days أيام');
    notifier?.call(c, 'قرار عائلي بانتظار تصويتك: $title', d.id);
    _changed();
    return d;
  }

  /// تصويت مرجّح بالوزن. يُحسم القرار فور بلوغ العتبة والنصاب، أو استحالة بلوغها.
  String? vote(Company c, FamilyDecision d, String memberId, {required bool approve, required String method, required String name}) {
    if (d.status != FamilyDecisionStatus.open) return 'القرار محسوم';
    if ((d.weights[memberId] ?? 0) <= 0) return 'ليس لك وزن تصويت في هذا القرار';
    d.votes = {...d.votes, memberId: FamilyVote(approve: approve, at: now(), method: method)};
    _log(c.id, 'تصويت $name ${approve ? 'بالموافقة' : 'بالرفض'} على: ${d.title}', 'family', d.id,
        'موافقة ${d.share(true).toStringAsFixed(1)}% من ${d.threshold.toStringAsFixed(2)}%',
        evidence: 'تأكيد: $method');
    final remaining = 100 - d.participation;
    if (d.share(true) + 1e-6 >= d.threshold && d.participation + 1e-6 >= d.quorum) {
      _decide(c, d, FamilyDecisionStatus.approved);
    } else if (d.share(true) + remaining + 1e-6 < d.threshold) {
      _decide(c, d, FamilyDecisionStatus.rejected);
    } else {
      _put(c.id, 'familyDecisions', d.id, d.toJson());
      _changed();
    }
    return null;
  }

  /// انتهاء المهلة دون بلوغ العتبة: لا يُعدّ موافقة
  int expireOverdue(Company c) {
    var n = 0;
    for (final d in decisionsFor(c.id).where((d) => d.status == FamilyDecisionStatus.open && now().isAfter(d.deadline))) {
      _decide(c, d, FamilyDecisionStatus.expired);
      n++;
    }
    return n;
  }

  void _decide(Company c, FamilyDecision d, FamilyDecisionStatus s) {
    d
      ..status = s
      ..decidedAt = now();
    _put(c.id, 'familyDecisions', d.id, d.toJson());
    _log(c.id, 'حسم القرار العائلي: ${d.title}', 'family', d.id,
        '${s.label} · موافقة ${d.share(true).toStringAsFixed(1)}% · مشاركة ${d.participation.toStringAsFixed(1)}%',
        actor: ActorType.system);
    _applyDecision(c, d);
    notifier?.call(c, 'القرار العائلي "${d.title}": ${s.label}', d.id);
    _changed();
  }

  void _applyDecision(Company c, FamilyDecision d) {
    final ok = d.status == FamilyDecisionStatus.approved;
    switch (d.type) {
      case FamilyDecisionType.constitution:
        final draft = constitutions.where((x) => x.id == d.refId).firstOrNull;
        if (draft == null) return;
        if (ok) {
          for (final x in constitutionsFor(c.id).where((x) => x.status == ConstitutionStatus.current)) {
            x.status = ConstitutionStatus.archived;
            _put(c.id, 'constitution', x.id, x.toJson());
          }
          draft
            ..status = ConstitutionStatus.current
            ..effectiveAt = now();
        } else {
          draft.status = ConstitutionStatus.draft;
        }
        _put(c.id, 'constitution', draft.id, draft.toJson());
      case FamilyDecisionType.distribution:
        final x = distributions.where((x) => x.id == d.refId).firstOrNull;
        if (x == null) return;
        x.status = ok ? DistributionStatus.approved : DistributionStatus.rejected;
        _put(c.id, 'distributions', x.id, x.toJson());
      case FamilyDecisionType.deed:
        final x = deeds.where((x) => x.id == d.refId).firstOrNull;
        if (x == null) return;
        x.status = ok ? RecordStatus.approved : RecordStatus.rejected;
        _put(c.id, 'deeds', x.id, x.toJson());
        if (ok) {
          for (final p in people.where((p) => x.shares.containsKey(p.id) && p.role == SuccessionRole.member)) {
            p.role = SuccessionRole.heir;
            _put(c.id, 'familyPeople', p.id, p.toJson());
          }
        }
      case FamilyDecisionType.succession:
        final x = successions.where((x) => x.id == d.refId).firstOrNull;
        if (x == null) return;
        x.status = ok ? SuccessionStatus.effective : SuccessionStatus.rejected;
        if (ok) x.effectiveAt = now();
        _put(c.id, 'succession', x.id, x.toJson());
      case FamilyDecisionType.other:
        break;
    }
  }

  // ───────────── R11 الأفراد والورثة ─────────────

  List<FamilyPerson> peopleFor(String? cid) =>
      people.where((p) => p.companyId == cid).toList()..sort((a, b) => a.generation.compareTo(b.generation));

  FamilyPerson? person(String id) => people.where((p) => p.id == id).firstOrNull;

  /// تجهيز المؤسسين من الشركاء عند أول استخدام
  void seedFounders(Company c) {
    if (peopleFor(c.id).isNotEmpty) return;
    for (final p in c.partners) {
      final x = FamilyPerson(
          id: 'FP${p.id}', companyId: c.id, name: p.name, relation: 'مؤسس', memberId: p.id, role: SuccessionRole.founder);
      people.add(x);
      _put(c.id, 'familyPeople', x.id, x.toJson());
    }
    _changed();
  }

  void savePerson(Company c, FamilyPerson p) {
    final isNew = !people.any((x) => x.id == p.id);
    if (isNew) people.add(p);
    _put(c.id, 'familyPeople', p.id, p.toJson());
    _log(c.id, '${isNew ? 'إضافة' : 'تحديث'} فرد في شجرة العائلة: ${p.name}', 'family', p.id, '${p.relation} · ${p.role.label}');
    _changed();
  }

  List<InheritanceDeed> deedsFor(String? cid) => deeds.where((x) => x.companyId == cid).toList()..sort((a, b) => b.date.compareTo(a.date));

  /// حصر الوراثة من وثيقته الرسمية: الأنصبة كما وردت، ومجموعها 100%، ويعتمدها قرار عائلي
  String? submitDeed(Company c, InheritanceDeed deed, {required String by}) {
    if (deed.reference.trim().isEmpty) return 'أدخل رقم وثيقة حصر الوراثة';
    if ((deed.total - 100).abs() > 0.01) return 'مجموع الأنصبة ${deed.total.toStringAsFixed(2)}% ويجب أن يساوي 100% كما في الوثيقة';
    deed.status = RecordStatus.pendingApproval;
    deeds.add(deed);
    final dec = openDecision(c,
        type: FamilyDecisionType.deed,
        refId: deed.id,
        title: 'اعتماد حصر وراثة ${person(deed.deceasedId)?.name ?? ''} (${deed.reference})',
        details: 'صادر عن ${deed.court}',
        by: by);
    deed.decisionRef = dec.id;
    _put(c.id, 'deeds', deed.id, deed.toJson());
    _changed();
    return null;
  }

  InheritanceDeed? approvedDeedFor(String cid, String deceasedId) => deedsFor(cid)
      .where((d) => d.deceasedId == deceasedId && d.status == RecordStatus.approved)
      .firstOrNull;

  // ───────────── R12 توزيع الأرباح ─────────────

  List<FamilyDistribution> distributionsFor(String? cid) =>
      distributions.where((x) => x.companyId == cid).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// احتساب التوزيع حسب القاعدة المعتمدة في الدستور الساري. المفتاح: معرّف العضو أو الفرد.
  Map<String, double> preview(Company c, double available, DistributionRule rule) {
    switch (rule) {
      case DistributionRule.equity:
        final total = c.equityTotal == 0 ? 1 : c.equityTotal;
        return {for (final p in c.partners) if (p.equity > 0) p.id: available * p.equity / total};
      case DistributionRule.heirShares:
        final d = deedsFor(c.id).where((d) => d.status == RecordStatus.approved).firstOrNull;
        if (d == null) return {};
        return {for (final e in d.shares.entries) e.key: available * e.value / 100};
      case DistributionRule.custom:
        final s = current(c.id)?.customShares ?? const {};
        final total = s.values.fold<double>(0, (a, b) => a + b);
        if (total == 0) return {};
        return {for (final e in s.entries) e.key: available * e.value / total};
    }
  }

  String? createDistribution(Company c, {required String period, required double available, required String by}) {
    final cur = current(c.id);
    if (cur == null) return 'لا يوجد دستور عائلي ساري يحدد قاعدة التوزيع';
    if (available <= 0) return 'أدخل الربح المتاح للتوزيع';
    final alloc = preview(c, available, cur.distributionRule);
    if (alloc.isEmpty) return 'قاعدة "${cur.distributionRule.label}" لا تنتج مستفيدين بعد';
    final x = FamilyDistribution(
      id: _id('DS'),
      companyId: c.id,
      period: period.trim(),
      available: available,
      currency: c.currency,
      rule: cur.distributionRule,
      constitutionVersion: cur.version,
      allocations: alloc,
      createdBy: by,
      createdAt: now(),
    );
    distributions.add(x);
    _put(c.id, 'distributions', x.id, x.toJson());
    _log(c.id, 'مسودة توزيع أرباح ${x.period}', 'family', x.id,
        '${formatCurrency(available, c.currency)} · ${cur.distributionRule.label} · الدستور ${cur.version}');
    _changed();
    return null;
  }

  void submitDistribution(Company c, FamilyDistribution x, {required String by}) {
    if (x.status != DistributionStatus.draft && x.status != DistributionStatus.rejected) return;
    x.status = DistributionStatus.pendingApproval;
    final d = openDecision(c,
        type: FamilyDecisionType.distribution,
        refId: x.id,
        title: 'اعتماد توزيع أرباح ${x.period}',
        details: '${formatCurrency(x.available, x.currency)} حسب ${x.rule.label}',
        by: by);
    x.decisionRef = d.id;
    _put(c.id, 'distributions', x.id, x.toJson());
    _changed();
  }

  /// تسجيل التنفيذ بمرجع السداد. التوزيع المعتمد لا يُعاد حسابه.
  void executeDistribution(Company c, FamilyDistribution x, {required String reference}) {
    if (x.status != DistributionStatus.approved || reference.trim().isEmpty) return;
    x
      ..status = DistributionStatus.executed
      ..executedAt = now()
      ..executionRef = reference.trim();
    _put(c.id, 'distributions', x.id, x.toJson());
    _log(c.id, 'تنفيذ توزيع أرباح ${x.period}', 'family', x.id, 'المرجع ${x.executionRef}');
    _changed();
  }

  // ───────────── R13 الخلافة ─────────────

  List<SuccessionCase> successionsFor(String? cid) =>
      successions.where((x) => x.companyId == cid).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// لا تبدأ الخلافة دون حدث مسجّل؛ والقرار لا يُفتح قبل إرفاق دليل
  String? startSuccession(Company c,
      {required SuccessionEvent event, required String subjectId, required DateTime eventDate, required String successorId, required String by}) {
    final s = person(subjectId);
    if (s == null) return 'الفرد غير موجود في شجرة العائلة';
    if (successorId == subjectId) return 'الخلف يجب أن يكون شخصاً آخر';
    if (successionsFor(c.id).any((x) => x.subjectId == subjectId && x.status != SuccessionStatus.rejected)) {
      return 'توجد إجراءات خلافة قائمة لهذا الفرد';
    }
    final x = SuccessionCase(
      id: _id('SC'),
      companyId: c.id,
      event: event,
      subjectId: subjectId,
      eventDate: eventDate,
      currentAuthority: s.name,
      successorId: successorId,
      createdBy: by,
      createdAt: now(),
    );
    successions.add(x);
    if (event == SuccessionEvent.death) {
      s.alive = false;
      _put(c.id, 'familyPeople', s.id, s.toJson());
    }
    _put(c.id, 'succession', x.id, x.toJson());
    _log(c.id, 'تسجيل حدث خلافة: ${event.label} (${s.name})', 'family', x.id, 'الخلف المقترح ${person(successorId)?.name ?? ''}');
    _changed();
    return null;
  }

  void addEvidence(Company c, SuccessionCase x, String evidence) {
    if (evidence.trim().isEmpty || x.status == SuccessionStatus.effective) return;
    x.evidence = [...x.evidence, evidence.trim()];
    _put(c.id, 'succession', x.id, x.toJson());
    _log(c.id, 'دليل لحدث الخلافة', 'family', x.id, evidence.trim());
    _changed();
  }

  String? submitSuccession(Company c, SuccessionCase x, {required String by}) {
    if (x.evidence.isEmpty) return 'أرفق دليلاً رسمياً على الحدث أولاً (شهادة وفاة، حكم، تنازل موثق)';
    if (x.status != SuccessionStatus.pendingEvidence && x.status != SuccessionStatus.rejected) return null;
    x.status = SuccessionStatus.pendingApproval;
    final d = openDecision(c,
        type: FamilyDecisionType.succession,
        refId: x.id,
        title: 'اعتماد خلافة ${x.currentAuthority} (${x.event.label})',
        details: 'الخلف: ${person(x.successorId)?.name ?? ''}',
        by: by);
    x.decisionRef = d.id;
    _put(c.id, 'succession', x.id, x.toJson());
    _changed();
    return null;
  }

  /// الحصص بعد الخلافة: حصة المتوفى تُقسم على الورثة وفق حصر الوراثة المعتمد، وفي غير الوفاة تنتقل للخلف.
  /// الورثة يجب أن يكونوا أعضاء في التطبيق (شركاء أو أفراد مدعوين) ليوقّعوا الإصدار الجديد.
  (Map<String, double>, List<String>)? equityAfterSuccession(Company c, SuccessionCase x) {
    final subject = person(x.subjectId);
    final subjectMember = subject?.memberId == null ? null : c.members.where((m) => m.id == subject!.memberId).firstOrNull;
    if (subject == null || subjectMember == null || subjectMember.equity <= 0) return null;
    final eq = {for (final p in c.partners) p.id: p.equity};
    final missing = <String>[];
    final shares = x.event == SuccessionEvent.death
        ? (approvedDeedFor(c.id, subject.id)?.shares ?? const <String, double>{})
        : {x.successorId: 100.0};
    if (shares.isEmpty) return null;
    eq[subjectMember.id] = 0;
    for (final e in shares.entries) {
      final p = person(e.key);
      final mid = p?.memberId;
      if (mid == null || !c.members.any((m) => m.id == mid)) {
        missing.add(p?.name ?? e.key);
        continue;
      }
      eq[mid] = (eq[mid] ?? 0) + subjectMember.equity * e.value / 100;
    }
    return (eq, missing);
  }

  void linkAmendment(Company c, SuccessionCase x, String sessionId) {
    x.amendmentRef = sessionId;
    _put(c.id, 'succession', x.id, x.toJson());
    _log(c.id, 'إنشاء إصدار جدول الحصص لتنفيذ الخلافة', 'family', x.id, sessionId);
    _changed();
  }

  // ───────────── أدوات ─────────────

  void _log(String cid, String action, String type, String id, String result, {ActorType actor = ActorType.user, String? evidence}) =>
      auditSink?.call(cid, action: action, objectType: type, objectId: id, result: result, evidenceRef: evidence, actorType: actor);

  void _put(String cid, String col, String id, Map<String, dynamic> data) {
    _db?.collection('companies').doc(cid).collection(col).doc(id).set(data).then(
          (_) {},
          onError: (Object e) => debugPrint('تعذر حفظ $col: $e'),
        );
  }

  void _changed() {
    notifyListeners();
    _persist();
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && _db == null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        List<T> l<T>(String k, T Function(Map<String, dynamic>) f) =>
            (j[k] as List? ?? []).map((e) => f(Map<String, dynamic>.from(e as Map))).toList();
        constitutions = l('constitutions', Constitution.fromJson);
        people = l('people', FamilyPerson.fromJson);
        deeds = l('deeds', InheritanceDeed.fromJson);
        distributions = l('distributions', FamilyDistribution.fromJson);
        successions = l('successions', SuccessionCase.fromJson);
        decisions = l('decisions', FamilyDecision.fromJson);
      }
    } catch (e) {
      debugPrint('تعذر تحميل الحوكمة العائلية: $e');
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    if (_db != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _key,
          jsonEncode({
            'constitutions': constitutions.map((e) => e.toJson()).toList(),
            'people': people.map((e) => e.toJson()).toList(),
            'deeds': deeds.map((e) => e.toJson()).toList(),
            'distributions': distributions.map((e) => e.toJson()).toList(),
            'successions': successions.map((e) => e.toJson()).toList(),
            'decisions': decisions.map((e) => e.toJson()).toList(),
          }));
    } catch (e) {
      debugPrint('تعذر حفظ الحوكمة العائلية: $e');
    }
  }

  Future<void> attachCloud(FirebaseFirestore db) async {
    await detachCloud();
    _db = db;
    constitutions = [];
    people = [];
    deeds = [];
    distributions = [];
    successions = [];
    decisions = [];
    notifyListeners();
  }

  Future<void> detachCloud() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _db = null;
    _watched = null;
  }

  void watchCompany(String? cid) {
    if (_db == null || cid == null || cid == _watched) return;
    _watched = cid;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    final base = _db!.collection('companies').doc(cid);
    void listen(String col, void Function(List<Map<String, dynamic>>) set) {
      _subs.add(base.collection(col).snapshots().listen((snap) {
        set(snap.docs.map((d) => {...d.data(), 'id': d.id}).toList());
        notifyListeners();
      }, onError: (Object e) => debugPrint('تعذر قراءة $col: $e')));
    }

    listen('constitution', (l) => constitutions = l.map(Constitution.fromJson).toList());
    listen('familyPeople', (l) => people = l.map(FamilyPerson.fromJson).toList());
    listen('deeds', (l) => deeds = l.map(InheritanceDeed.fromJson).toList());
    listen('distributions', (l) => distributions = l.map(FamilyDistribution.fromJson).toList());
    listen('succession', (l) => successions = l.map(SuccessionCase.fromJson).toList());
    listen('familyDecisions', (l) => decisions = l.map(FamilyDecision.fromJson).toList());
  }

  @override
  void dispose() {
    detachCloud();
    super.dispose();
  }
}
