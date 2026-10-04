import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/company.dart';
import '../models/dispute.dart';
import '../models/operations.dart';
import '../models/ops_extra.dart';
import '../models/questionnaire.dart';
import '../widgets/common_widgets.dart' show formatCurrency;
import 'contract_state.dart';
import 'dispute_state.dart';
import 'operations_state.dart';

/// التشغيل اليومي (O07–O11، O14–O17): الحساب الجاري، الرواتب، الخطط، المراسلات،
/// تنفيذ القرارات، والتنبيهات. كل ما يمس قاعدة في العقد يمر ببوابة الفحص في الرقابة المالية.
class DailyOpsState extends ChangeNotifier {
  static const _key = 'daily_ops_v1';

  List<LedgerEntry> ledger = [];
  List<PayrollBatch> payroll = [];
  List<OpsPlan> plans = [];
  List<Letter> letters = [];
  Map<String, Execution> executions = {};
  Map<String, AlertState> alertStates = {};
  bool loaded = false;
  AuditSink? auditSink;
  DateTime Function() now = DateTime.now;

  FirebaseFirestore? _db;
  String? _watched;
  final List<StreamSubscription> _subs = [];

  // ───────────── O08 الحساب الجاري ─────────────

  /// القيود اليدوية مع السلف المرحَّلة آلياً من العمليات المقبولة
  List<LedgerEntry> ledgerFor(Company c, OperationsState ops) {
    final auto = [
      for (final t in ops.txFor(c.id))
        if (t.category == TxCategory.personalAdvance &&
            (t.status == TxStatus.allowed || t.status == TxStatus.releasedException || t.status == TxStatus.exceptionPending))
          LedgerEntry(
            id: 'AUTO-${t.id}',
            companyId: c.id,
            partnerId: c.partners.where((p) => p.roles.contains(CompanyRole.managingPartner)).firstOrNull?.id ?? '',
            kind: LedgerKind.advance,
            amount: t.amount,
            currency: t.currency,
            date: t.date,
            reference: t.reference.isEmpty ? t.id : t.reference,
            note: 'مرحّلة آلياً من عملية سلفة: ${t.purpose}',
            createdBy: t.createdBy,
            txId: t.id,
            pending: t.status == TxStatus.exceptionPending,
          ),
    ];
    return [...ledger.where((e) => e.companyId == c.id), ...auto]..sort((a, b) => b.date.compareTo(a.date));
  }

  /// الرصيد لكل شريك ولكل عملة على حدة (لا تُجمع عملات مختلفة)
  Map<String, Map<AppCurrency, double>> balances(Company c, OperationsState ops) {
    final out = <String, Map<AppCurrency, double>>{};
    for (final e in ledgerFor(c, ops).where((e) => !e.pending)) {
      final m = out.putIfAbsent(e.partnerId, () => {});
      m[e.currency] = (m[e.currency] ?? 0) + e.signed;
    }
    return out;
  }

  void addLedger(Company c, LedgerEntry e) {
    ledger.add(e);
    _put(c.id, 'ledger', e.id, e.toJson());
    _log(c.id, 'قيد على الحساب الجاري: ${e.kind.label}', 'ledger', e.id,
        '${formatCurrency(e.amount, e.currency)}${e.reference.isEmpty ? '' : ' · المرجع ${e.reference}'}');
    _changed();
  }

  // ───────────── O09 الرواتب ─────────────

  List<PayrollBatch> payrollFor(String cid) =>
      payroll.where((b) => b.companyId == cid).toList()..sort((a, b) => b.period.compareTo(a.period));

  PayrollBatch? batch(String id) => payroll.where((b) => b.id == id).firstOrNull;

  /// آخر راتب معتمد للشريك المدير (مرجع اكتشاف التغيير)
  double? approvedManagerSalary(String cid, {String? before}) {
    for (final b in payrollFor(cid)) {
      if (b.status != PayrollStatus.approved || (before != null && b.period.compareTo(before) >= 0)) continue;
      final l = b.lines.where((l) => l.managingPartner).firstOrNull;
      if (l != null) return l.total;
    }
    return null;
  }

  /// دفعة جديدة: تُنسخ أسطر آخر دفعة، أو تُبنى من الموظفين والشريك المدير
  String? createBatch(Company c, String period, {required String by}) {
    if (payrollFor(c.id).any((b) => b.period == period)) return 'توجد دفعة لهذه الفترة بالفعل';
    final last = payrollFor(c.id).firstOrNull;
    final mp = c.partners.where((p) => p.roles.contains(CompanyRole.managingPartner)).firstOrNull;
    final lines = last?.lines.map((l) => PayrollLine(
                employee: l.employee, role: l.role, salary: l.total, managingPartner: l.managingPartner))
            .toList() ??
        [
          if (mp != null) PayrollLine(employee: mp.name, role: 'الشريك المدير', salary: 0, managingPartner: true),
          for (final s in c.staffMembers.where((m) => m.active))
            PayrollLine(employee: s.name, role: s.roles.map((r) => r.label).join('، '), salary: 0),
        ];
    final b = PayrollBatch(
        id: 'PR${now().microsecondsSinceEpoch}',
        companyId: c.id,
        period: period,
        currency: c.currency,
        lines: lines,
        createdBy: by,
        createdAt: now());
    payroll.add(b);
    _put(c.id, 'payroll', b.id, b.toJson());
    _log(c.id, 'إنشاء دفعة رواتب $period', 'payroll', b.id, '${lines.length} موظفين');
    _changed();
    return null;
  }

  void updateLines(Company c, PayrollBatch b, List<PayrollLine> lines) {
    if (b.status != PayrollStatus.draft && b.status != PayrollStatus.rejected) return;
    b
      ..lines = lines
      ..status = PayrollStatus.draft;
    _put(c.id, 'payroll', b.id, b.toJson());
    _changed();
  }

  /// رفع الدفعة للاعتماد. تغيّر راتب الشريك المدير يمر ببوابة الفحص كعملية "تعديل راتب"،
  /// فإن نص العقد على قرار الشركاء تُجمَّد حتى يُعتمد استثناء أو تعديل.
  void submitBatch(Company c, PayrollBatch b, OperationsState ops, ContractState cs, {required String by, required String byName}) {
    if (b.status != PayrollStatus.draft && b.status != PayrollStatus.rejected) return;
    final mp = b.lines.where((l) => l.managingPartner).firstOrNull;
    final prev = approvedManagerSalary(c.id, before: b.period);
    if (mp != null && prev != null && mp.total != prev) {
      final tx = ops.submit(
          cs,
          c,
          FinancialTx(
            id: 'T${now().microsecondsSinceEpoch}',
            companyId: c.id,
            date: now(),
            amount: mp.total,
            currency: b.currency,
            category: TxCategory.salaryChange,
            payee: mp.employee,
            purpose: 'تعديل راتب الشريك المدير في دفعة ${b.period} من ${formatCurrency(prev, b.currency)} إلى ${formatCurrency(mp.total, b.currency)}',
            reference: b.id,
            createdBy: by,
            createdAt: now(),
          ),
          actorName: byName);
      b.ruleTxId = tx.id;
      b.status = tx.status == TxStatus.allowed ? PayrollStatus.pendingApproval : PayrollStatus.awaitingPartners;
    } else {
      b.status = PayrollStatus.pendingApproval;
    }
    _put(c.id, 'payroll', b.id, b.toJson());
    _log(c.id, 'رفع دفعة الرواتب ${b.period} للاعتماد', 'payroll', b.id,
        '${formatCurrency(b.total, b.currency)} · ${b.status.label}');
    _changed();
  }

  /// متابعة الدفعات المعلّقة على قرار الشركاء بعد البت في الاستثناء
  void refreshPayroll(Company c, OperationsState ops) {
    var changed = false;
    for (final b in payrollFor(c.id).where((b) => b.status == PayrollStatus.awaitingPartners)) {
      final t = b.ruleTxId == null ? null : ops.tx(b.ruleTxId!);
      if (t == null) continue;
      if (t.status == TxStatus.releasedException || t.status == TxStatus.allowed) {
        b.status = PayrollStatus.pendingApproval;
        b.reason = 'وافق الشركاء على تعديل راتب الشريك المدير';
      } else if (t.status == TxStatus.violation) {
        b.status = PayrollStatus.rejected;
        b.reason = 'رفض الشركاء تعديل راتب الشريك المدير: أعيدوا الراتب إلى المعتمد أو عدّلوا العقد';
      } else {
        continue;
      }
      changed = true;
      _put(c.id, 'payroll', b.id, b.toJson());
      _log(c.id, 'تحديث دفعة الرواتب ${b.period} بعد قرار الشركاء', 'payroll', b.id, b.status.label, actor: ActorType.system);
    }
    if (changed) _changed();
  }

  void decideBatch(Company c, PayrollBatch b, {required bool approve, required String byName, String? reason}) {
    if (b.status != PayrollStatus.pendingApproval) return;
    b
      ..status = approve ? PayrollStatus.approved : PayrollStatus.rejected
      ..decidedBy = byName
      ..decidedAt = now()
      ..reason = reason;
    _put(c.id, 'payroll', b.id, b.toJson());
    _log(c.id, '${approve ? 'اعتماد' : 'رفض'} دفعة الرواتب ${b.period}', 'payroll', b.id,
        '${formatCurrency(b.total, b.currency)}${reason == null || reason.isEmpty ? '' : ' · $reason'}');
    _changed();
  }

  // ───────────── O14 / O15 الخطط ─────────────

  List<OpsPlan> plansFor(String cid) => plans.where((p) => p.companyId == cid).toList()
    ..sort((a, b) => b.year != a.year ? b.year.compareTo(a.year) : a.category.index.compareTo(b.category.index));

  OpsPlan? plan(String id) => plans.where((p) => p.id == id).firstOrNull;

  void savePlan(Company c, OpsPlan p) {
    final i = plans.indexWhere((x) => x.id == p.id);
    if (i < 0) {
      plans.add(p);
      _log(c.id, 'إنشاء خطة ${p.category.label}: ${p.title}', 'plan', p.id, '${p.year} · ${p.segment.label}');
    }
    _put(c.id, 'plans', p.id, p.toJson());
    _changed();
  }

  void setPlanStatus(Company c, OpsPlan p, PlanStatus s, {required String byName, String? reason}) {
    final allowed = switch (s) {
      PlanStatus.pending => p.status == PlanStatus.draft || p.status == PlanStatus.rejected,
      PlanStatus.approved || PlanStatus.rejected => p.status == PlanStatus.pending,
      PlanStatus.archived => p.status == PlanStatus.approved,
      PlanStatus.draft => false,
    };
    if (!allowed) return;
    p
      ..status = s
      ..decidedBy = s == PlanStatus.pending ? null : byName
      ..reason = reason;
    _put(c.id, 'plans', p.id, p.toJson());
    _log(c.id, 'الخطة "${p.title}": ${s.label}', 'plan', p.id, reason ?? '');
    _changed();
  }

  /// نسخ خطة لسنة لاحقة كمسودة جديدة بنفس المراحل دون الفعلي
  OpsPlan clonePlan(Company c, OpsPlan p, {required String by}) {
    final n = OpsPlan(
      id: 'PL${now().microsecondsSinceEpoch}',
      companyId: c.id,
      category: p.category,
      year: p.year + 1,
      title: p.title,
      owner: p.owner,
      objectives: p.objectives,
      budget: p.budget,
      segment: p.segment,
      milestones: [
        for (final m in p.milestones)
          Milestone(id: 'M${now().microsecondsSinceEpoch}${m.id}', title: m.title, period: m.period, target: m.target),
      ],
      createdBy: by,
      createdAt: now(),
    );
    savePlan(c, n);
    return n;
  }

  void updateMilestone(Company c, OpsPlan p, Milestone m,
      {double? actual, MilestoneStatus? status, String? evidence, String? deviation, String? corrective}) {
    if (p.status != PlanStatus.approved) return;
    if (actual != null) m.actual = actual;
    if (status != null) m.status = status;
    if (evidence != null && evidence.trim().isNotEmpty) m.evidence = [...m.evidence, evidence.trim()];
    if (deviation != null) m.deviation = deviation.trim();
    if (corrective != null) m.corrective = corrective.trim();
    _put(c.id, 'plans', p.id, p.toJson());
    _log(c.id, 'تحديث تنفيذ "${m.title}" في خطة ${p.title}', 'plan', p.id,
        '${m.status.label}${m.variance == null ? '' : ' · الفرق ${m.variance!.toStringAsFixed(0)}'}${m.deviation == null || m.deviation!.isEmpty ? '' : ' · الانحراف: ${m.deviation}'}');
    _changed();
  }

  // ───────────── O16 المراسلات ─────────────

  List<Letter> lettersFor(String cid) => letters.where((l) => l.companyId == cid).toList()..sort((a, b) => b.date.compareTo(a.date));

  String nextReference(String cid, bool outgoing) {
    final y = now().year;
    final n = letters.where((l) => l.companyId == cid && l.outgoing == outgoing && l.date.year == y).length + 1;
    return '${outgoing ? 'OUT' : 'IN'}-$y-${n.toString().padLeft(3, '0')}';
  }

  void saveLetter(Company c, Letter l) {
    final i = letters.indexWhere((x) => x.id == l.id);
    if (i >= 0 && letters[i].locked && l.status == letters[i].status) return; // الصادر مقفل النص
    if (i < 0) {
      letters.add(l);
      _log(c.id, 'تسجيل مراسلة ${l.outgoing ? 'صادرة' : 'واردة'} ${l.reference}', 'letter', l.id, l.subject);
    }
    _put(c.id, 'letters', l.id, l.toJson());
    _changed();
  }

  /// إصدار المراسلة: تُسجَّل كصادرة ويُقفل نصها. الإرسال الفعلي يحتاج مزوّد بريد أو رسائل.
  void setLetterStatus(Company c, Letter l, LetterStatus s) {
    final ok = switch (s) {
      LetterStatus.sent => l.status == LetterStatus.draft,
      LetterStatus.delivered || LetterStatus.failed => l.status == LetterStatus.sent,
      LetterStatus.archived => l.status != LetterStatus.draft && l.status != LetterStatus.archived,
      LetterStatus.draft => false,
    };
    if (!ok) return;
    l.status = s;
    _put(c.id, 'letters', l.id, l.toJson());
    _log(c.id, 'المراسلة ${l.reference}: ${s.label}', 'letter', l.id, l.subject);
    _changed();
  }

  /// الحذف للمسودة فقط؛ المراسلة الصادرة أو الرسمية لا تُحذف
  bool deleteDraft(Company c, Letter l) {
    if (l.status != LetterStatus.draft) return false;
    letters.remove(l);
    _db?.collection('companies').doc(c.id).collection('letters').doc(l.id).delete();
    _log(c.id, 'حذف مسودة مراسلة ${l.reference}', 'letter', l.id, l.subject);
    _changed();
    return true;
  }

  // ───────────── O11 تنفيذ القرارات ─────────────

  /// القرارات المعتمدة التي تتطلب تنفيذاً تشغيلياً
  List<ApprovedDecision> decisions(Company c, ContractState cs, DisputeState ds, OperationsState ops) {
    final out = <ApprovedDecision>[];
    for (final s in cs.versionsFor(c.id).where((s) => s.isAmendment && s.status == SessionStatus.completed)) {
      out.add(ApprovedDecision(
        id: 'V-${s.id}',
        type: 'إصدار عقد ${s.version}',
        result: s.changeSummary ?? s.changeType.label,
        effective: s.completedAt ?? s.updatedAt,
        requiredAction: s.changeType == ChangeType.capTable
            ? 'تحديث السجل التجاري ودفاتر الشركاء وفق جدول الحصص الجديد'
            : 'إبلاغ الإدارات المعنية وتطبيق القيم الجديدة في الإجراءات اليومية',
      ));
    }
    for (final d in ds.disputesFor(c.id).where((d) => d.status == DisputeStatus.resolved || d.status == DisputeStatus.closed)) {
      if (d.outcome == null) continue;
      out.add(ApprovedDecision(
        id: 'D-${d.id}',
        type: 'حسم نزاع',
        result: d.outcome!,
        effective: d.resolvedAt ?? d.openedAt,
        requiredAction: 'تنفيذ ما نص عليه الحسم وإرفاق الدليل',
      ));
    }
    for (final x in ops.exceptionsFor(c.id).where((x) => x.status == ExceptionStatus.approved)) {
      out.add(ApprovedDecision(
        id: 'X-${x.id}',
        type: 'استثناء معتمد',
        result: 'استثناء لمرة واحدة من "${x.ruleName}" للعملية ${x.txId}',
        effective: x.decidedAt ?? x.createdAt,
        requiredAction: 'صرف العملية المعتمدة فقط وإرفاق سند الصرف',
      ));
    }
    out.sort((a, b) => b.effective.compareTo(a.effective));
    return out;
  }

  Execution executionOf(String decisionId) => executions[decisionId] ?? Execution(decisionId: decisionId, updatedAt: now());

  void updateExecution(Company c, ApprovedDecision d,
      {ExecStatus? status, String? owner, DateTime? deadline, String? evidence, String? issue}) {
    final e = executionOf(d.id);
    if (e.status == ExecStatus.completed && status != null && status != ExecStatus.completed) return;
    if (status == ExecStatus.completed && e.evidence.isEmpty && (evidence == null || evidence.trim().isEmpty)) return;
    if (status != null) e.status = status;
    if (owner != null) e.owner = owner;
    if (deadline != null) e.deadline = deadline;
    if (evidence != null && evidence.trim().isNotEmpty) e.evidence = [...e.evidence, evidence.trim()];
    if (issue != null) e.issue = issue;
    e.updatedAt = now();
    executions[d.id] = e;
    _put(c.id, 'executions', d.id, e.toJson());
    _log(c.id, 'تنفيذ قرار: ${d.type}', 'execution', d.id,
        '${e.status.label}${e.owner.isEmpty ? '' : ' · ${e.owner}'}${e.issue == null || e.issue!.isEmpty ? '' : ' · العائق: ${e.issue}'}');
    _changed();
  }

  // ───────────── O17 التنبيهات ─────────────

  List<OpsAlert> alerts(Company c, ContractState cs, DisputeState ds, OperationsState ops) {
    final t = now();
    final out = <OpsAlert>[];
    for (final x in ops.txFor(c.id).where((x) => x.status == TxStatus.frozen)) {
      out.add(OpsAlert(
          id: 'FRZ-${x.id}',
          type: 'عملية مجمّدة',
          title: '${x.category.label} ${formatCurrency(x.amount, x.currency)} لصالح ${x.payee}',
          detail: x.triggered.map((r) => r.ruleName).join('، '),
          created: x.evaluatedAt ?? x.createdAt,
          relatedType: 'transaction',
          relatedId: x.id,
          role: 'المدير المالي'));
    }
    for (final x in ops.exceptionsFor(c.id).where((x) => x.status == ExceptionStatus.pending)) {
      out.add(OpsAlert(
          id: 'EXC-${x.id}',
          type: 'استثناء بانتظار الشركاء',
          title: x.ruleName,
          detail: 'تنتهي المهلة دون قرار فتبقى العملية مجمّدة',
          created: x.createdAt,
          deadline: x.deadline,
          relatedType: 'exception',
          relatedId: x.id,
          role: 'الشركاء'));
    }
    for (final v in ops.violationsFor(c.id).where((v) => v.status == ViolationStatus.open || v.status == ViolationStatus.investigating)) {
      out.add(OpsAlert(
          id: 'VIO-${v.id}',
          type: 'مخالفة مفتوحة',
          title: v.ruleName,
          detail: v.description,
          created: v.createdAt,
          relatedType: 'violation',
          relatedId: v.id,
          role: v.owner.isEmpty ? 'المدير التنفيذي' : v.owner));
    }
    for (final d in ds.openFor(c.id).where((d) => d.stage.index < DisputeStage.arbitration.index && d.deadline.difference(t).inDays < 3)) {
      out.add(OpsAlert(
          id: 'DSP-${d.id}-${d.stage.name}',
          type: 'مهلة نزاع قريبة',
          title: '${d.trigger.label}: ${d.stage.label}',
          detail: d.issue,
          created: d.stageStartedAt,
          deadline: d.deadline,
          relatedType: 'dispute',
          relatedId: d.id,
          role: 'الشركاء'));
    }
    for (final b in payrollFor(c.id).where((b) => b.status == PayrollStatus.pendingApproval || b.status == PayrollStatus.awaitingPartners)) {
      out.add(OpsAlert(
          id: 'PAY-${b.id}-${b.status.name}',
          type: 'دفعة رواتب معلّقة',
          title: 'رواتب ${b.period} · ${formatCurrency(b.total, b.currency)}',
          detail: b.status.label,
          created: b.createdAt,
          relatedType: 'payroll',
          relatedId: b.id,
          role: b.status == PayrollStatus.awaitingPartners ? 'الشركاء' : 'المدير التنفيذي'));
    }
    for (final p in plansFor(c.id).where((p) => p.status == PlanStatus.approved)) {
      for (final m in p.milestones.where((m) => m.status == MilestoneStatus.delayed || m.status == MilestoneStatus.blocked)) {
        out.add(OpsAlert(
            id: 'PLN-${p.id}-${m.id}-${m.status.name}',
            type: 'انحراف عن الخطة',
            title: '${p.title}: ${m.title}',
            detail: '${m.status.label}${m.deviation == null || m.deviation!.isEmpty ? '' : ' · ${m.deviation}'}',
            created: t,
            relatedType: 'plan',
            relatedId: p.id,
            role: p.owner));
      }
    }
    for (final d in decisions(c, cs, ds, ops)) {
      final e = executions[d.id];
      if (e != null && (e.status == ExecStatus.blocked || (e.deadline != null && e.deadline!.isBefore(t) && e.status != ExecStatus.completed))) {
        out.add(OpsAlert(
            id: 'EXE-${d.id}-${e.status.name}',
            type: e.status == ExecStatus.blocked ? 'تنفيذ قرار متعثر' : 'تنفيذ قرار متأخر',
            title: d.type,
            detail: e.issue ?? d.requiredAction,
            created: e.updatedAt,
            deadline: e.deadline,
            relatedType: 'execution',
            relatedId: d.id,
            role: e.owner.isEmpty ? 'المدير التنفيذي' : e.owner));
      }
    }
    out.sort((a, b) => b.created.compareTo(a.created));
    return out;
  }

  AlertState? alertState(String id) => alertStates[id];

  /// الحالة الفعلية: المؤجَّل يعود جديداً بعد انتهاء التأجيل
  AlertStatus statusOf(String id) {
    final s = alertStates[id];
    if (s == null) return AlertStatus.open;
    if (s.snoozeUntil != null && now().isAfter(s.snoozeUntil!) && s.status == AlertStatus.acknowledged) return AlertStatus.open;
    return s.status;
  }

  void setAlert(Company c, OpsAlert a, AlertStatus s, {String? role, Duration? snooze}) {
    final st = AlertState(
        status: s, assignedRole: role ?? alertStates[a.id]?.assignedRole, snoozeUntil: snooze == null ? null : now().add(snooze), at: now());
    alertStates[a.id] = st;
    _put(c.id, 'alertStates', a.id, st.toJson());
    _log(c.id, 'تنبيه "${a.type}": ${s.label}', 'alert', a.id,
        '${a.title}${st.assignedRole == null ? '' : ' · مسند إلى ${st.assignedRole}'}${snooze == null ? '' : ' · مؤجل ${snooze.inHours} ساعة'}');
    _changed();
  }

  // ───────────── التحميل والخادم ─────────────

  void _log(String cid, String action, String type, String id, String result, {ActorType actor = ActorType.user}) =>
      auditSink?.call(cid, action: action, objectType: type, objectId: id, result: result, actorType: actor);

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
        ledger = l('ledger', LedgerEntry.fromJson);
        payroll = l('payroll', PayrollBatch.fromJson);
        plans = l('plans', OpsPlan.fromJson);
        letters = l('letters', Letter.fromJson);
        executions = {for (final e in l('executions', Execution.fromJson)) e.decisionId: e};
        alertStates = Map<String, dynamic>.from(j['alerts'] as Map? ?? {})
            .map((k, v) => MapEntry(k, AlertState.fromJson(Map<String, dynamic>.from(v as Map))));
      }
    } catch (e) {
      debugPrint('تعذر تحميل بيانات التشغيل اليومي: $e');
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
            'ledger': ledger.map((e) => e.toJson()).toList(),
            'payroll': payroll.map((e) => e.toJson()).toList(),
            'plans': plans.map((e) => e.toJson()).toList(),
            'letters': letters.map((e) => e.toJson()).toList(),
            'executions': executions.values.map((e) => e.toJson()).toList(),
            'alerts': alertStates.map((k, v) => MapEntry(k, v.toJson())),
          }));
    } catch (e) {
      debugPrint('تعذر حفظ بيانات التشغيل اليومي: $e');
    }
  }

  Future<void> attachCloud(FirebaseFirestore db) async {
    await detachCloud();
    _db = db;
    ledger = [];
    payroll = [];
    plans = [];
    letters = [];
    executions = {};
    alertStates = {};
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

    listen('ledger', (l) => ledger = l.map(LedgerEntry.fromJson).toList());
    listen('payroll', (l) => payroll = l.map(PayrollBatch.fromJson).toList());
    listen('plans', (l) => plans = l.map(OpsPlan.fromJson).toList());
    listen('letters', (l) => letters = l.map(Letter.fromJson).toList());
    listen('executions', (l) => executions = {for (final e in l.map(Execution.fromJson)) e.decisionId: e});
    listen('alertStates', (l) => alertStates = {for (final e in l) e['id'] as String: AlertState.fromJson(e)});
  }

  @override
  void dispose() {
    detachCloud();
    super.dispose();
  }
}
