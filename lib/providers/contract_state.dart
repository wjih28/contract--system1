import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/question_bank.dart';
import '../models/questionnaire.dart';
import '../widgets/common_widgets.dart';

/// حالة محرك الاستبانة: بنك الأسئلة وجلسات إعداد العقود.
/// تُحفظ كل عملية فور حدوثها حتى لا يضيع التقدم عند انقطاع الجلسة.
class ContractState extends ChangeNotifier {
  static const _sessionsKey = 'contract_sessions_v1';
  static const _customBankKey = 'custom_bank_v1';

  final List<BankQuestion> _customQuestions = [];
  List<ContractSession> sessions = [];
  bool loaded = false;

  List<BankQuestion> get bank => [...seedQuestionBank, ..._customQuestions];

  BankQuestion question(String id) => bank.firstWhere((q) => q.id == id);

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
      if (raw != null) {
        sessions = (jsonDecode(raw) as List)
            .map((e) => ContractSession.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('تعذر تحميل الجلسات المحفوظة: $e');
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _sessionsKey,
        jsonEncode(sessions.map((s) => s.toJson()).toList()),
      );
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
    required String companyName,
    required String companyType,
    required AppCurrency currency,
    required double capital,
    required List<SessionPartner> partners,
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
      companyName: companyName,
      companyType: companyType,
      currency: currency,
      capital: capital,
      partners: partners,
      records: records,
      createdAt: now,
      updatedAt: now,
    );
    sessions.insert(0, s);
    _touch(s);
    return s;
  }

  void deleteSession(ContractSession s) {
    sessions.remove(s);
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
    return QuorumResult(
      agreeShare: agree,
      disagreeShare: disagree,
      neutralShare: neutral,
      required: required,
      complete: complete,
      passed: agree + 1e-6 >= required,
    );
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
    final result = quorum(s, r);
    if (result.complete) {
      r.status = result.passed ? ClauseStatus.agreed : ClauseStatus.rejected;
      r.resolvedAt = DateTime.now();
    } else {
      r.status = ClauseStatus.pending;
      r.resolvedAt = null;
    }
    _touch(s);
  }

  /// تعديل القيمة المقترحة يلغي الأصوات السابقة لأنها كانت على قيمة مختلفة
  void setValue(ContractSession s, ClauseRecord r, double? value) {
    if (r.value == value) return;
    r.value = value;
    if (r.votes.isNotEmpty) {
      r.votes.clear();
      r.round++;
    }
    r.status = ClauseStatus.pending;
    r.resolvedAt = null;
    _touch(s);
  }

  void revote(ContractSession s, ClauseRecord r) {
    r.votes.clear();
    r.round++;
    r.status = ClauseStatus.pending;
    r.resolvedAt = null;
    _touch(s);
  }

  void defer(ContractSession s, ClauseRecord r) {
    r.status = ClauseStatus.deferred;
    r.resolvedAt = null;
    _touch(s);
  }

  /// إعادة فتح بند مؤجل أو محيّد للنقاش والتصويت
  void reopen(ContractSession s, ClauseRecord r) {
    r.votes.clear();
    r.round++;
    r.status = ClauseStatus.pending;
    r.resolvedAt = null;
    _touch(s);
  }

  /// التحييد يتم باتفاق جميع الشركاء ويُسقط البند من العقد
  void neutralize(ContractSession s, ClauseRecord r) {
    r.status = ClauseStatus.neutralized;
    r.resolvedAt = DateTime.now();
    _touch(s);
  }

  void suspend(ContractSession s) {
    s.status = SessionStatus.suspended;
    _touch(s);
  }

  void resume(ContractSession s) {
    if (s.status == SessionStatus.suspended) {
      s.status = SessionStatus.active;
      s.sittings++;
      _touch(s);
    }
  }

  void markAwaitingSignature(ContractSession s) {
    if (s.allResolved && s.status != SessionStatus.completed) {
      s.status = SessionStatus.awaitingSignature;
      _touch(s);
    }
  }

  void signOff(ContractSession s, PartnerSignOff so) {
    s.signOffs[so.partnerId] = so;
    _touch(s);
  }

  void setWitnesses(ContractSession s, List<Witness> w) {
    s.witnesses = w;
    _touch(s);
  }

  void complete(ContractSession s) {
    s.status = SessionStatus.completed;
    s.completedAt = DateTime.now();
    s.contentHash = computeHash(s);
    _touch(s);
  }

  /// المحتوى القانوني للعقد بترتيب ثابت: البنود بنصها النهائي، الأصوات، التواقيع، الشهود.
  /// التواقيع تدخل ببصمتها لا بصورتها حتى يبقى المحتوى خفيفاً.
  String canonicalContent(ContractSession s) {
    String digest(String? v) => v == null ? '' : sha256.convert(utf8.encode(v)).toString();
    final sortedSign = s.signOffs.keys.toList()..sort();
    return jsonEncode({
      'id': s.id,
      'company': [s.companyName, s.companyType, s.currency.code, s.capital],
      'partners': s.partners.map((p) => [p.id, p.name, p.nationalId, p.phone, p.equity]).toList(),
      'clauses': s.records.map((r) {
        final voteIds = r.votes.keys.toList()..sort();
        return [
          r.key,
          r.status.name,
          r.value,
          r.status == ClauseStatus.agreed ? renderClause(s, r) : null,
          voteIds.map((id) {
            final v = r.votes[id]!;
            return [id, v.ballot.name, v.at.toIso8601String(), v.method.name];
          }).toList(),
        ];
      }).toList(),
      'signOffs': sortedSign.map((id) {
        final so = s.signOffs[id]!;
        return [id, digest(so.signaturePng), so.at.toIso8601String(), so.method.name];
      }).toList(),
      'witnesses': s.witnesses.map((w) => [w.name, w.nationalId, w.internal, digest(w.signaturePng)]).toList(),
      'completedAt': s.completedAt?.toIso8601String(),
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
}
