import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/company.dart';
import '../models/dispute.dart';
import '../widgets/common_widgets.dart' show formatCurrency;
import 'contract_state.dart';

/// إشعار قانوني لأطراف الشركة (يُربط بمركز الإشعارات)
typedef DisputeNotifier = void Function(Company c, Dispute d, String subject, {String deadline});

/// حالة النزاعات (P18 / P19 / J04). التذكرة دائمة: لا تُحذف ولا تُلغى، وتنتقل بين المراحل
/// بالاتفاق أو بانقضاء المهلة، وكل انتقال يُسجَّل في الخط الزمني وسجل التدقيق.
class DisputeState extends ChangeNotifier {
  static const _key = 'disputes_v1';

  List<Dispute> disputes = [];
  bool loaded = false;
  AuditSink? auditSink;
  DisputeNotifier? notifier;

  /// تحويل الشركة إلى التصفية ثم الأرشفة (يضبطه main عبر CompanyState)
  void Function(String companyId, CompanyStatus status)? onCompanyStatus;

  DateTime Function() now = DateTime.now;

  /// الوصول إلى الشركة من معرّفها (لانتقال المهل آلياً)
  Company? Function(String id)? companyOf;

  Timer? _ticker;

  /// فحص المهل دورياً
  void startTicker() {
    _ticker ??= Timer.periodic(const Duration(minutes: 1), (_) => expireOverdue());
  }

  FirebaseFirestore? _db;
  StreamSubscription? _sub;
  String? _watched;

  // ───────────── الاستعلام ─────────────

  List<Dispute> disputesFor(String? companyId) =>
      disputes.where((d) => d.companyId == companyId).toList()..sort((a, b) => b.openedAt.compareTo(a.openedAt));

  Dispute? dispute(String id) => disputes.where((d) => d.id == id).firstOrNull;

  List<Dispute> openFor(String? companyId) => disputesFor(companyId).where((d) => d.isOpen).toList();

  /// نزاع قائم يُقفل تعديلات العقد وجدول الحصص مؤقتاً
  bool locked(String companyId) => openFor(companyId).isNotEmpty;

  /// التحكيم الجاري يمنع القرارات الاستثنائية والسحوبات خارج المعتاد
  bool arbitrationActive(String companyId) => openFor(companyId)
      .any((d) => d.stage == DisputeStage.arbitration || d.stage == DisputeStage.liquidation);

  // ───────────── الفتح ─────────────

  /// فتح تذكرة نزاع. للمحفزات الآلية يكون المعرّف ثابتاً من المرجع، فلا تتكرر التذكرة
  /// عند إعادة الحساب أو من أكثر من جهاز.
  Dispute open(
    Company c, {
    required DisputeTrigger trigger,
    required String issue,
    String? relatedType,
    String? relatedId,
    required String openedBy,
    required String openedByName,
    List<String>? parties,
  }) {
    final id = relatedId == null
        ? 'D${now().microsecondsSinceEpoch}'
        : 'D-${sha256.convert(utf8.encode('${c.id}|${trigger.name}|$relatedId')).toString().substring(0, 12)}';
    final existing = dispute(id);
    if (existing != null) return existing;
    final t = now();
    final d = Dispute(
      id: id,
      companyId: c.id,
      trigger: trigger,
      issue: issue.trim(),
      relatedType: relatedType,
      relatedId: relatedId,
      contractVersion: c.contractVersion,
      openedBy: openedBy,
      openedAt: t,
      parties: parties ?? c.partners.where((p) => p.equity > 0).map((p) => p.id).toList(),
      stageStartedAt: t,
      deadline: t.add(Duration(days: c.setting<int>('dispute.negotiationDays'))),
    );
    d.entries.add(_sys(d, 'فُتحت التذكرة (${trigger.label}) بواسطة $openedByName. بدأت مرحلة التفاوض المباشر لمدة '
        '${c.setting<int>('dispute.negotiationDays')} يوماً، وأُقفلت تعديلات العقد وجدول الحصص مؤقتاً.'));
    disputes.add(d);
    _log(c.id, 'فتح تذكرة نزاع: ${trigger.label}', d.id, issue,
        actor: openedBy == 'system' ? ActorType.system : ActorType.user, evidence: 'إصدار العقد ${c.contractVersion}');
    notifier?.call(c, d, '${trigger.label}: ${d.issue}', deadline: _fmt(d.deadline));
    _save(d);
    return d;
  }

  // ───────────── مدخلات الأطراف ─────────────

  void addEntry(Company c, Dispute d, EntryKind kind, String text,
      {required String authorId, required String authorName, String? evidenceRef}) {
    if (!d.isOpen && kind != EntryKind.evidence) return;
    final t = text.trim();
    if (t.isEmpty) return;
    d.entries.add(DisputeEntry(
        kind: kind, authorId: authorId, authorName: authorName, text: t, at: now(), stage: d.stage, evidenceRef: evidenceRef));
    _log(c.id, '${kind.label} في النزاع', d.id, t.length > 60 ? '${t.substring(0, 60)}…' : t);
    _save(d);
  }

  /// محضر صلح مقترح؛ صاحب الاقتراح يوافق عليه ضمناً، ويلزم موافقة بقية الأطراف
  void proposeSettlement(Company c, Dispute d, String text,
      {required String authorId, required String authorName, bool requiresAmendment = false}) {
    if (!d.isOpen || d.stage.index > DisputeStage.mediation.index) return;
    final t = now();
    d.settlement = Settlement(
        text: text.trim(), proposedBy: authorId, at: t, requiresAmendment: requiresAmendment, approvals: {authorId: t});
    d.entries.add(DisputeEntry(
        kind: EntryKind.settlement, authorId: authorId, authorName: authorName, text: text.trim(), at: t, stage: d.stage));
    _log(c.id, 'اقتراح محضر صلح', d.id, requiresAmendment ? 'يتطلب تعديل العقد بإصدار جديد' : 'لا يغيّر شروط العقد');
    _save(d);
  }

  void approveSettlement(Company c, Dispute d, String memberId, {required String memberName, required String method}) {
    final s = d.settlement;
    if (!d.isOpen || s == null || !d.parties.contains(memberId) || s.approvals.containsKey(memberId)) return;
    d.settlement = s.approvedBy(memberId, now());
    d.entries.add(_sys(d, 'وافق $memberName على محضر الصلح (تأكيد: $method).'));
    _log(c.id, 'موافقة $memberName على محضر الصلح', d.id, '${d.settlement!.approvals.length} من ${d.parties.length}',
        evidence: 'تأكيد: $method');
    if (d.parties.every(d.settlement!.approvals.containsKey)) {
      _resolve(c, d,
          'صلح باتفاق الأطراف في مرحلة ${d.stage.label}${d.settlement!.requiresAmendment ? '، ويُنفَّذ بإصدار جديد للعقد' : ''}');
    } else {
      _save(d);
    }
  }

  /// موافقة طرف على إنهاء المرحلة دون اتفاق؛ عند موافقة الجميع تنتقل التذكرة للمرحلة التالية
  void consentEscalate(Company c, Dispute d, String memberId, {required String memberName}) {
    if (!d.isOpen || !d.parties.contains(memberId) || d.stage.index >= DisputeStage.arbitration.index) return;
    d.escalationConsents.add(memberId);
    d.entries.add(_sys(d, '$memberName يطلب إنهاء ${d.stage.label} دون اتفاق.'));
    if (d.parties.every(d.escalationConsents.contains)) {
      _advance(c, d, 'باتفاق الأطراف على تعذر التسوية');
    } else {
      _save(d);
    }
  }

  void setMediator(Company c, Dispute d, String name) {
    d.mediator = name.trim();
    d.entries.add(_sys(d, 'جهة الوساطة: ${d.mediator}'));
    _log(c.id, 'تحديد جهة الوساطة', d.id, d.mediator!);
    _save(d);
  }

  void setArbitrationCenter(Company c, Dispute d, String name) {
    d.arbitrationCenter = name.trim();
    d.entries.add(_sys(d, 'مركز التحكيم: ${d.arbitrationCenter}'));
    _log(c.id, 'تحديد مركز التحكيم', d.id, d.arbitrationCenter!);
    _save(d);
  }

  // ───────────── كسر الجمود (المرحلة 3) ─────────────

  /// عرض شراء مغلق وملزم لحصة الطرف الآخر كاملة، مع مهلة 72 ساعة للاختيار
  String? submitBuyOut(Company c, Dispute d,
      {required String offerorId, required String targetId, required double price, required String offerorName}) {
    if (d.stage != DisputeStage.deadlockBreak || !d.isOpen) return 'العرض متاح في مرحلة كسر الجمود فقط';
    if (d.buyOut != null && !d.buyOut!.decided) return 'يوجد عرض قائم بانتظار الرد';
    if (offerorId == targetId || !d.parties.contains(targetId)) return 'اختر طرفاً آخر في النزاع';
    if (price <= 0) return 'أدخل سعراً صحيحاً';
    final t = now();
    d.buyOut = BuyOutOffer(
        offerorId: offerorId,
        targetId: targetId,
        price: price,
        at: t,
        deadline: t.add(Duration(hours: c.setting<int>('dispute.buyOutHours'))));
    d.deadline = d.buyOut!.deadline;
    d.status = DisputeStatus.awaitingParty;
    final target = _name(c, targetId);
    d.entries.add(DisputeEntry(
        kind: EntryKind.offer,
        authorId: offerorId,
        authorName: offerorName,
        text: 'عرض ملزم لشراء حصة $target كاملة بمبلغ ${formatCurrency(price, c.currency)}. '
            'لـ$target خلال ${c.setting<int>('dispute.buyOutHours')} ساعة أن يبيع بهذا السعر، أو يشتري حصة $offerorName بنفس السعر للنسبة الواحدة.',
        at: t,
        stage: d.stage));
    _log(c.id, 'عرض شراء ملزم في النزاع', d.id, '$offerorName → $target: ${formatCurrency(price, c.currency)}');
    notifier?.call(c, d, 'عرض شراء ملزم بانتظار رد $target', deadline: _fmt(d.deadline));
    _save(d);
    return null;
  }

  /// اختيار الطرف المستهدف: يبيع حصته، أو يشتري حصة صاحب العرض بنفس السعر
  void chooseBuyOut(Company c, Dispute d, {required bool sell, required String method}) {
    final o = d.buyOut;
    if (o == null || o.decided || !d.isOpen) return;
    d.buyOut = o.decide(sell ? 'sell' : 'buy', now());
    final buyer = d.buyOut!.buyerId!, seller = d.buyOut!.sellerId!;
    final eq = {for (final p in c.partners) p.id: p.equity};
    eq[buyer] = (eq[buyer] ?? 0) + (eq[seller] ?? 0);
    eq[seller] = 0;
    d.equityAfter = eq;
    d.entries.add(DisputeEntry(
        kind: EntryKind.choice,
        authorId: o.targetId,
        authorName: _name(c, o.targetId),
        text: sell
            ? 'اختار البيع: تنتقل حصته إلى ${_name(c, buyer)} بالسعر المعروض.'
            : 'اختار الشراء: يشتري حصة ${_name(c, seller)} بنفس سعر النسبة الواحدة.',
        at: now(),
        stage: d.stage,
        evidenceRef: 'تأكيد: $method'));
    _resolve(c, d,
        'كسر الجمود بالشراء: ${_name(c, buyer)} يشتري حصة ${_name(c, seller)}. يُنفَّذ بإصدار جديد لجدول الحصص، والسداد خارج التطبيق.');
  }

  // ───────────── التحكيم (المرحلة 4) ─────────────

  /// ملف القضية: يُثبَّت ببصمة SHA-256 لمحتواه عند تصديره
  void recordCaseFile(Company c, Dispute d, String hash) {
    d.caseFileHash = hash;
    d.entries.add(_sys(d, 'صُدِّر ملف القضية إلى ${d.arbitrationCenter ?? 'مركز التحكيم'}. مرجع سلامة المستند: ${hash.substring(0, 16)}…'));
    _log(c.id, 'تصدير ملف القضية للتحكيم', d.id, d.arbitrationCenter ?? '', evidence: 'SHA-256: $hash');
    _save(d);
  }

  void recordAward(Company c, Dispute d,
      {required String text, required AwardOutcome outcome, required String ref, Map<String, double>? equity}) {
    if (d.stage != DisputeStage.arbitration || !d.isOpen) return;
    d.awardText = text.trim();
    d.awardOutcome = outcome;
    d.awardRef = ref.trim();
    d.entries.add(DisputeEntry(
        kind: EntryKind.award,
        authorId: 'system',
        authorName: d.arbitrationCenter ?? 'مركز التحكيم',
        text: '${outcome.label}: ${d.awardText}',
        at: now(),
        stage: d.stage,
        evidenceRef: d.awardRef));
    _log(c.id, 'تسجيل حكم التحكيم', d.id, outcome.label, evidence: 'مرجع الحكم: ${d.awardRef}');
    switch (outcome) {
      case AwardOutcome.equityChange:
        d.equityAfter = equity;
        _resolve(c, d, 'حكم تحكيم بتعديل الملكية، يُنفَّذ بإصدار جديد لجدول الحصص');
      case AwardOutcome.dismiss:
        _resolve(c, d, 'حكم تحكيم برفض الدعوى واستمرار العقد');
      case AwardOutcome.dissolve:
        _enter(c, d, DisputeStage.liquidation, 'حكم بفض الشراكة والتصفية');
        onCompanyStatus?.call(c.id, CompanyStatus.liquidation);
    }
  }

  // ───────────── التصفية (المرحلة 5) ─────────────

  void setLiquidation(Company c, Dispute d, {String? liquidator, double? assets}) {
    if (d.stage != DisputeStage.liquidation) return;
    if (liquidator != null) d.liquidator = liquidator.trim();
    if (assets != null) d.liquidationAssets = assets;
    _log(c.id, 'تحديث بيانات التصفية', d.id,
        'المصفّي: ${d.liquidator ?? '—'}، الأصول: ${d.liquidationAssets == null ? '—' : formatCurrency(d.liquidationAssets!, c.currency)}');
    _save(d);
  }

  void addDebt(Company c, Dispute d, LiquidationDebt debt) {
    if (d.stage != DisputeStage.liquidation) return;
    d.debts = [...d.debts, debt];
    _log(c.id, 'إضافة دين في التصفية', d.id,
        '${debt.creditor}: ${formatCurrency(debt.amount, c.currency)}${debt.preferred ? ' (ممتاز)' : ''}');
    _save(d);
  }

  /// الترتيب النظامي: الديون الممتازة أولاً ثم العادية (بالمحاصّة إن لم تكفِ)، ثم الصافي للشركاء بنسب حصصهم
  static LiquidationPlan plan(Company c, Dispute d) {
    var left = d.liquidationAssets ?? 0;
    final payments = <(LiquidationDebt, double)>[];
    for (final group in [d.debts.where((x) => x.preferred).toList(), d.debts.where((x) => !x.preferred).toList()]) {
      final total = group.fold<double>(0, (a, x) => a + x.amount);
      final ratio = total == 0 ? 0.0 : (left >= total ? 1.0 : left / total);
      for (final x in group) {
        payments.add((x, x.amount * ratio));
      }
      left -= total * ratio;
    }
    final net = left < 0 ? 0.0 : left;
    final eq = c.equityTotal == 0 ? 1 : c.equityTotal;
    return LiquidationPlan(
      assets: d.liquidationAssets ?? 0,
      payments: payments,
      net: net,
      distribution: {for (final p in c.partners) p.id: net * p.equity / eq},
    );
  }

  /// إغلاق التصفية: وثيقة التصفية النهائية وأرشفة الكيان
  void closeLiquidation(Company c, Dispute d, {required String method}) {
    if (d.stage != DisputeStage.liquidation || !d.isOpen || d.liquidationAssets == null) return;
    final p = plan(c, d);
    d.status = DisputeStatus.closed;
    d.resolvedAt = now();
    d.outcome = 'تصفية الشركة: سُدِّدت الديون بترتيبها النظامي ووُزِّع صافٍ قدره ${formatCurrency(p.net, c.currency)} '
        'على الشركاء بنسب حصصهم. أُرشف الكيان تمهيداً لشطب السجل التجاري.';
    d.entries.add(_sys(d, d.outcome!));
    _log(c.id, 'إغلاق التصفية وأرشفة الشركة', d.id, d.outcome!, evidence: 'تأكيد: $method');
    onCompanyStatus?.call(c.id, CompanyStatus.archived);
    notifier?.call(c, d, 'أُغلقت التصفية وأُرشفت الشركة');
    _save(d);
  }

  // ───────────── الحسم والإغلاق ─────────────

  /// ربط الحسم بالإصدار الذي نفّذه
  void linkAmendment(Company c, Dispute d, String sessionId) {
    d.amendmentRef = sessionId;
    d.entries.add(_sys(d, 'أُنشئ مقترح إصدار جديد للعقد لتنفيذ الحسم.'));
    _log(c.id, 'ربط الحسم بإصدار جديد للعقد', d.id, sessionId);
    _save(d);
  }

  /// إغلاق تذكرة محسومة بعد تنفيذ نتيجتها. التذكرة تبقى محفوظة للقراءة فقط.
  void close(Company c, Dispute d, {required String byName}) {
    if (d.status != DisputeStatus.resolved || d.needsAmendment) return;
    d.status = DisputeStatus.closed;
    d.entries.add(_sys(d, 'أُغلقت التذكرة بواسطة $byName. تبقى محفوظة للقراءة فقط.'));
    _log(c.id, 'إغلاق تذكرة النزاع', d.id, d.outcome ?? '');
    _save(d);
  }

  void _resolve(Company c, Dispute d, String outcome) {
    d.status = DisputeStatus.resolved;
    d.outcome = outcome;
    d.resolvedAt = now();
    d.entries.add(_sys(d, 'حُسم النزاع: $outcome'));
    _log(c.id, 'حسم النزاع', d.id, outcome);
    notifier?.call(c, d, 'حُسم النزاع: $outcome');
    _save(d);
  }

  // ───────────── الانتقال بين المراحل ─────────────

  void _advance(Company c, Dispute d, String why) {
    final next = switch (d.stage) {
      DisputeStage.negotiation => DisputeStage.mediation,
      DisputeStage.mediation => DisputeStage.deadlockBreak,
      DisputeStage.deadlockBreak => DisputeStage.arbitration,
      DisputeStage.arbitration || DisputeStage.liquidation => null,
    };
    if (next == null) return;
    _enter(c, d, next, why);
  }

  void _enter(Company c, Dispute d, DisputeStage next, String why) {
    final from = d.stage;
    d.stage = next;
    d.stageStartedAt = now();
    d.escalationConsents = {};
    d.settlement = null;
    d.deadline = switch (next) {
      DisputeStage.mediation => now().add(Duration(days: c.setting<int>('dispute.mediationDays'))),
      DisputeStage.deadlockBreak => now().add(const Duration(days: DisputeSettings.deadlockBreakDays)),
      // التحكيم والتصفية بلا مهلة آلية: تنتهي بحكم أو بإغلاق التصفية
      _ => now().add(const Duration(days: 3650)),
    };
    d.status = next.index >= DisputeStage.arbitration.index ? DisputeStatus.escalated : DisputeStatus.adrActive;
    d.entries.add(_sys(d, 'انتقال من ${from.label} إلى ${next.label} ($why).'));
    _log(c.id, 'انتقال النزاع إلى ${next.label}', d.id, why, actor: ActorType.system);
    notifier?.call(c, d, 'انتقل النزاع إلى ${next.label}',
        deadline: next.index >= DisputeStage.arbitration.index ? 'حتى صدور الحكم' : _fmt(d.deadline));
    _save(d);
  }

  /// انقضاء المهل: المرحلة التي تنتهي مهلتها دون اتفاق تنتقل تلقائياً للتالية.
  /// انقضاء مهلة عرض الشراء دون رد لا يُعدّ قبولاً، ويُحال النزاع للتحكيم.
  int expireOverdue() {
    var n = 0;
    final t = now();
    for (final d in disputes.where((x) => x.isOpen).toList()) {
      if (d.stage.index >= DisputeStage.arbitration.index || t.isBefore(d.deadline)) continue;
      final c = companyOf?.call(d.companyId);
      if (c == null) continue;
      if (d.stage == DisputeStage.deadlockBreak && d.buyOut != null && !d.buyOut!.decided) {
        _enter(c, d, DisputeStage.arbitration, 'انقضت مهلة الرد على عرض الشراء دون اختيار');
      } else {
        _advance(c, d, 'انقضت مهلة ${d.stage.label} دون اتفاق');
      }
      n++;
    }
    return n;
  }

  // ───────────── أدوات داخلية ─────────────

  DisputeEntry _sys(Dispute d, String text) =>
      DisputeEntry(kind: EntryKind.system, authorId: 'system', authorName: 'النظام', text: text, at: now(), stage: d.stage);

  static String _name(Company c, String id) => c.members.where((m) => m.id == id).firstOrNull?.name ?? id;

  static String _fmt(DateTime t) =>
      '${t.year}/${t.month.toString().padLeft(2, '0')}/${t.day.toString().padLeft(2, '0')}';

  void _log(String cid, String action, String id, String result, {ActorType actor = ActorType.user, String? evidence}) {
    auditSink?.call(cid, action: action, objectType: 'dispute', objectId: id, result: result, evidenceRef: evidence, actorType: actor);
  }

  void _save(Dispute d) {
    _db?.collection('companies').doc(d.companyId).collection('disputes').doc(d.id).set(d.toJson()).then(
          (_) {},
          onError: (Object e) => debugPrint('تعذر حفظ النزاع في الخادم: $e'),
        );
    notifyListeners();
    _persist();
  }

  // ───────────── التحميل والخادم ─────────────

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && _db == null) {
        disputes = (jsonDecode(raw) as List).map((e) => Dispute.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      }
    } catch (e) {
      debugPrint('تعذر تحميل النزاعات: $e');
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    if (_db != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(disputes.map((d) => d.toJson()).toList()));
    } catch (e) {
      debugPrint('تعذر حفظ النزاعات: $e');
    }
  }

  Future<void> attachCloud(FirebaseFirestore db) async {
    await detachCloud();
    _db = db;
    disputes = [];
    notifyListeners();
  }

  Future<void> detachCloud() async {
    await _sub?.cancel();
    _sub = null;
    _db = null;
    _watched = null;
  }

  void watchCompany(String? companyId) {
    if (_db == null || companyId == null || companyId == _watched) return;
    _watched = companyId;
    _sub?.cancel();
    _sub = _db!.collection('companies').doc(companyId).collection('disputes').snapshots().listen((snap) {
      disputes = snap.docs.map((d) => Dispute.fromJson({...d.data(), 'id': d.id})).toList();
      notifyListeners();
    }, onError: (Object e) => debugPrint('تعذر قراءة النزاعات: $e'));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    detachCloud();
    super.dispose();
  }
}
