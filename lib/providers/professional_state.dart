import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/company.dart';
import '../models/professional.dart';
import '../models/questionnaire.dart';
import 'contract_state.dart';

/// إشعار للشركاء بحدث مهني (تكليف، طلب تعديل، اكتمال مراجعة)
typedef ProNotifier = void Function(Company c, String subject, String relatedId);

/// الأطراف المهنية (R01–R08): التكليفات والمراجعات والتعليقات.
class ProfessionalState extends ChangeNotifier {
  static const _key = 'professionals_v1';

  List<Engagement> engagements = [];
  List<ProComment> comments = [];
  List<ProReview> reviews = [];
  bool loaded = false;
  AuditSink? auditSink;
  ProNotifier? notifier;

  /// إيقاف وصول الطرف المهني عند انتهاء تكليفه أو اعتذاره (يضبطه main عبر CompanyState)
  void Function(String companyId, String memberId)? onAccessEnded;
  DateTime Function() now = DateTime.now;

  FirebaseFirestore? _db;
  String? _watched;
  final List<StreamSubscription> _subs = [];

  // ───────────── التكليف (R01 / R03) ─────────────

  List<Engagement> engagementsFor(String? cid) =>
      engagements.where((e) => e.companyId == cid).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Engagement? engagementOf(String? cid, String? memberId) =>
      engagements.where((e) => e.companyId == cid && e.memberId == memberId).firstOrNull;

  Engagement? engagement(String id, String cid) => engagements.where((e) => e.id == id && e.companyId == cid).firstOrNull;

  bool inScope(Engagement? e, EngagementScope s) => e != null && e.activeAt(now()) && e.scope.contains(s);

  /// تكليف طرف مهني مدعو (عضو بدور محامٍ أو محاسب). يكلّفه الشريك المدير أو مسؤول النظام.
  String? createEngagement(Company c, CompanyMember m,
      {required Set<EngagementScope> scope,
      required DateTime start,
      required DateTime end,
      String organization = '',
      String contact = '',
      required String byName,
      required String byId}) {
    final role = m.roles.contains(CompanyRole.lawyer)
        ? ProRole.lawyer
        : m.roles.contains(CompanyRole.accountant)
            ? ProRole.accountant
            : null;
    if (role == null) return 'العضو ليس محامياً ولا محاسباً';
    if (scope.isEmpty) return 'حدد نطاق التكليف';
    if (!end.isAfter(start)) return 'نهاية التكليف يجب أن تكون بعد بدايته';
    final existing = engagementOf(c.id, m.id);
    if (existing != null && (existing.status == EngagementStatus.pending || existing.activeAt(now()))) {
      return 'يوجد تكليف قائم لهذا الطرف';
    }
    final e = Engagement(
      id: m.phone.isEmpty ? m.id : m.phone,
      companyId: c.id,
      memberId: m.id,
      name: m.name,
      role: role,
      organization: organization.trim(),
      contact: contact.trim(),
      scope: scope,
      start: start,
      end: end,
      createdBy: byId,
      createdAt: now(),
    );
    engagements
      ..removeWhere((x) => x.id == e.id && x.companyId == c.id)
      ..add(e);
    _put(c.id, 'engagements', e.id, e.toJson());
    _log(c.id, 'تكليف ${role.label}: ${m.name}', 'engagement', e.id,
        '${scope.map((s) => s.label).join('، ')} · حتى ${_d(end)} · بواسطة $byName');
    notifier?.call(c, 'كُلّف ${m.name} (${role.label}) بمراجعة: ${scope.map((s) => s.label).join('، ')}', e.id);
    _changed();
    return null;
  }

  /// R01: قبول الدعوة أو الاعتذار عنها، ويُسجَّل الرد
  void respond(Company c, Engagement e, {required bool accept, String? reason}) {
    if (e.status != EngagementStatus.pending) return;
    e
      ..status = accept ? EngagementStatus.active : EngagementStatus.declined
      ..respondedAt = now()
      ..declineReason = accept ? null : reason?.trim();
    _put(c.id, 'engagements', e.id, e.toJson());
    _log(c.id, '${accept ? 'قبول' : 'الاعتذار عن'} تكليف ${e.role.label}: ${e.name}', 'engagement', e.id,
        accept ? 'التكليف سارٍ حتى ${_d(e.end)}' : (reason ?? ''));
    if (!accept) onAccessEnded?.call(c.id, e.memberId);
    _changed();
  }

  void updateContact(Company c, Engagement e, String contact) {
    e.contact = contact.trim();
    _put(c.id, 'engagements', e.id, e.toJson());
    _log(c.id, 'تحديث بيانات تواصل ${e.name}', 'engagement', e.id, e.contact);
    _changed();
  }

  /// هل بدأ الطرف المهني عمله (تعليقات أو مراجعات)؟ بعدها يحتاج الإنهاء موافقة الشركاء
  bool workStarted(Engagement e) =>
      comments.any((x) => x.engagementId == e.id && x.companyId == e.companyId) ||
      reviews.any((x) => x.engagementId == e.id && x.companyId == e.companyId);

  /// طلب إنهاء التكليف. قبل بدء العمل يُنهى فوراً، وبعده يحتاج موافقة شركاء يملكون أكثر من نصف الحصص.
  void requestTermination(Company c, Engagement e, {required String reason, required String byId, required String byName}) {
    if (e.status != EngagementStatus.active && e.status != EngagementStatus.pending) return;
    if (!workStarted(e)) {
      _terminate(c, e, reason, byName);
      return;
    }
    e
      ..terminationReason = reason.trim()
      ..terminationApprovals = {};
    _put(c.id, 'engagements', e.id, e.toJson());
    _log(c.id, 'طلب إنهاء تكليف ${e.name}', 'engagement', e.id, 'بعد بدء المراجعة: يحتاج موافقة الشركاء · $reason');
    notifier?.call(c, 'طلب إنهاء تكليف ${e.name} يحتاج موافقة الشركاء', e.id);
    _changed();
  }

  double approvalShare(Company c, Engagement e) =>
      c.partners.where((p) => e.terminationApprovals.containsKey(p.id)).fold(0.0, (a, p) => a + p.equity);

  void approveTermination(Company c, Engagement e, CompanyMember partner, {required String method}) {
    if (e.terminationReason == null || !partner.isPartner || e.terminationApprovals.containsKey(partner.id)) return;
    e.terminationApprovals = {...e.terminationApprovals, partner.id: _iso(now())};
    _log(c.id, 'موافقة ${partner.name} على إنهاء تكليف ${e.name}', 'engagement', e.id,
        '${approvalShare(c, e).toStringAsFixed(1)}% من الحصص', evidence: 'تأكيد: $method');
    if (approvalShare(c, e) > 50) {
      _terminate(c, e, e.terminationReason!, 'الشركاء بنسبة ${approvalShare(c, e).toStringAsFixed(1)}%');
    } else {
      _put(c.id, 'engagements', e.id, e.toJson());
      _changed();
    }
  }

  void _terminate(Company c, Engagement e, String reason, String byName) {
    e.status = EngagementStatus.terminated;
    _put(c.id, 'engagements', e.id, e.toJson());
    _log(c.id, 'إنهاء تكليف ${e.name}', 'engagement', e.id, '$reason · $byName');
    onAccessEnded?.call(c.id, e.memberId);
    _changed();
  }

  // ───────────── التعليقات (R04 / R05 / R06) ─────────────

  List<ProComment> commentsFor(String? cid, {String? engagementId}) => comments
      .where((x) => x.companyId == cid && (engagementId == null || x.engagementId == engagementId))
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  ProComment? comment(String id) => comments.where((x) => x.id == id).firstOrNull;

  String? addComment(Company c, Engagement e, ProComment x) {
    if (!e.activeAt(now())) return 'التكليف غير سارٍ';
    if (x.text.trim().isEmpty) return 'اكتب نص التعليق';
    comments.add(x);
    _put(c.id, 'reviewComments', x.id, x.toJson());
    _log(c.id, '${x.kind.label} من ${e.role.label} على ${x.targetLabel}', 'proComment', x.id,
        '${x.category} · ${x.severity.label}${x.version == null ? '' : ' · الإصدار ${x.version}'}');
    if (x.kind == CommentKind.changeRequest) {
      notifier?.call(c, '${e.name} يطلب تعديل "${x.targetLabel}": ${x.text}', x.id);
    }
    _changed();
    return null;
  }

  /// رد من الشركة أو الطرف المهني. رد الشركة يجعل التعليق "بانتظار الرد" من الطرف المهني، والعكس.
  void reply(Company c, ProComment x, {required String authorId, required String authorName, required bool professional, required String text}) {
    if (text.trim().isEmpty) return;
    x.replies = [...x.replies, CommentReply(authorId: authorId, authorName: authorName, professional: professional, text: text.trim(), at: now())];
    if (x.status != CommentStatus.resolved) x.status = professional ? CommentStatus.open : CommentStatus.awaitingResponse;
    _put(c.id, 'reviewComments', x.id, x.toJson());
    _log(c.id, 'رد $authorName على تعليق ${x.targetLabel}', 'proComment', x.id,
        text.trim().length > 60 ? '${text.trim().substring(0, 60)}…' : text.trim());
    _changed();
  }

  void setCommentStatus(Company c, ProComment x, CommentStatus s, {required String byName}) {
    if (s == CommentStatus.resolved && x.status == CommentStatus.resolved) return;
    if (s == CommentStatus.reopened && x.status != CommentStatus.resolved) return;
    x
      ..status = s
      ..resolvedAt = s == CommentStatus.resolved ? now() : null;
    _put(c.id, 'reviewComments', x.id, x.toJson());
    _log(c.id, '${s == CommentStatus.resolved ? 'حل' : 'إعادة فتح'} تعليق ${x.targetLabel}', 'proComment', x.id, byName);
    _changed();
  }

  void linkAmendment(Company c, ProComment x, String sessionId) {
    x.amendmentRef = sessionId;
    _put(c.id, 'reviewComments', x.id, x.toJson());
    _log(c.id, 'فتح مقترح تعديل استجابة لطلب ${x.authorName}', 'proComment', x.id, sessionId);
    _changed();
  }

  // ───────────── المراجعات ─────────────

  ProReview? review(Engagement e, String sessionId) =>
      reviews.where((r) => r.engagementId == e.id && r.companyId == e.companyId && r.sessionId == sessionId).firstOrNull;

  List<ProReview> reviewsFor(String? cid) => reviews.where((r) => r.companyId == cid).toList()
    ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  ProReview startReview(Company c, Engagement e, ContractSession s) {
    final ex = review(e, s.id);
    if (ex != null) return ex;
    final r = ProReview(
        id: '${e.id}|${s.id}', companyId: c.id, engagementId: e.id, type: e.role, sessionId: s.id, version: s.version, startedAt: now());
    reviews.add(r);
    _put(c.id, 'reviews', _docId(r.id), r.toJson());
    _log(c.id, 'بدء ${e.role == ProRole.lawyer ? 'المراجعة القانونية' : 'المراجعة المحاسبية'} للإصدار ${s.version}', 'review', r.id, e.name);
    _changed();
    return r;
  }

  void toggleReviewed(Company c, ProReview r, String key) {
    if (r.status == ReviewStatus.completed) return;
    r.reviewedKeys.contains(key) ? r.reviewedKeys.remove(key) : r.reviewedKeys.add(key);
    _put(c.id, 'reviews', _docId(r.id), r.toJson());
    _changed();
  }

  void setChecklist(Company c, ProReview r, String item, bool v) {
    if (r.status == ReviewStatus.completed) return;
    r.checklist = {...r.checklist, item: v};
    _put(c.id, 'reviews', _docId(r.id), r.toJson());
    _changed();
  }

  void setMapping(Company c, ProReview r, String category, String account) {
    if (r.status == ReviewStatus.completed) return;
    r.accountMapping = {...r.accountMapping, category: account.trim()};
    _put(c.id, 'reviews', _docId(r.id), r.toJson());
    _log(c.id, 'ربط فئة "$category" بالحساب ${account.trim()}', 'review', r.id, '');
    _changed();
  }

  /// موانع إكمال المراجعة: البنود غير المراجعة، وقائمة التحقق المحاسبية، والتعليقات المرتفعة المفتوحة
  List<String> completionBlockers(ProReview r, List<String> requiredKeys) {
    final out = <String>[];
    final missing = requiredKeys.where((k) => !r.reviewedKeys.contains(k)).length;
    if (missing > 0) out.add('$missing بنود لم تُوسم كمراجعة');
    if (r.type == ProRole.accountant) {
      final open = kAccountingChecklist.where((i) => r.checklist[i] != true).length;
      if (open > 0) out.add('$open بنود في قائمة التحقق لم تُستوفَ');
    }
    return out;
  }

  String? completeReview(Company c, ProReview r, List<String> requiredKeys, {required String summary, required String byName}) {
    final b = completionBlockers(r, requiredKeys);
    if (b.isNotEmpty) return b.join('، ');
    final open = comments.where((x) => x.engagementId == r.engagementId && x.sessionId == r.sessionId && x.status.isOpen).toList();
    r
      ..status = ReviewStatus.completed
      ..completedAt = now()
      ..summary = '${summary.trim()}${open.isEmpty ? '' : ' · ${open.length} تعليقات ما زالت مفتوحة'}';
    _put(c.id, 'reviews', _docId(r.id), r.toJson());
    _log(c.id, 'اكتمال ${r.type == ProRole.lawyer ? 'المراجعة القانونية' : 'المراجعة المحاسبية'} للإصدار ${r.version}', 'review', r.id,
        r.summary!);
    notifier?.call(c, 'أكمل $byName ${r.type == ProRole.lawyer ? 'المراجعة القانونية' : 'المراجعة المحاسبية'} للإصدار ${r.version}', r.id);
    _changed();
    return null;
  }

  // ───────────── أدوات ─────────────

  static String _d(DateTime d) => '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  static String _iso(DateTime d) => d.toUtc().toIso8601String();

  /// معرّف المستند في Firestore لا يقبل "/"؛ "|" مقبول
  static String _docId(String id) => id.replaceAll('/', '_');

  void _log(String cid, String action, String type, String id, String result, {String? evidence}) =>
      auditSink?.call(cid, action: action, objectType: type, objectId: id, result: result, evidenceRef: evidence);

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
        engagements = l('engagements', Engagement.fromJson);
        comments = l('comments', ProComment.fromJson);
        reviews = l('reviews', ProReview.fromJson);
      }
    } catch (e) {
      debugPrint('تعذر تحميل بيانات الأطراف المهنية: $e');
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
            'engagements': engagements.map((e) => e.toJson()).toList(),
            'comments': comments.map((e) => e.toJson()).toList(),
            'reviews': reviews.map((e) => e.toJson()).toList(),
          }));
    } catch (e) {
      debugPrint('تعذر حفظ بيانات الأطراف المهنية: $e');
    }
  }

  Future<void> attachCloud(FirebaseFirestore db) async {
    await detachCloud();
    _db = db;
    engagements = [];
    comments = [];
    reviews = [];
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
        set(snap.docs.map((d) => {...d.data(), 'id': d.data()['id'] ?? d.id}).toList());
        notifyListeners();
      }, onError: (Object e) => debugPrint('تعذر قراءة $col: $e')));
    }

    listen('engagements', (l) => engagements = l.map(Engagement.fromJson).toList());
    listen('reviewComments', (l) => comments = l.map(ProComment.fromJson).toList());
    listen('reviews', (l) => reviews = l.map(ProReview.fromJson).toList());
  }

  @override
  void dispose() {
    detachCloud();
    super.dispose();
  }
}
