import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../models/company.dart';
import '../theme/app_theme.dart';
import 'gov_status.dart';

String _pct(double v) => '${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}%';

final _dt = DateFormat('yyyy/MM/dd HH:mm');

/// إطار موحد لكل مكوّن: عنوان وأيقونة ومحتوى
class GovCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  const GovCard({super.key, required this.title, required this.icon, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.navySurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.gold, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 13.5)),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ───────────────────────── مكوّن الموافقة ─────────────────────────

/// صوت واحد في مصفوفة التصويت
class VoterLine {
  final String name;
  final double weight; // نسبة الملكية
  final String? vote; // null = لم يصوّت بعد
  final Color? voteColor;
  const VoterLine({required this.name, required this.weight, this.vote, this.voteColor});
}

/// مكوّن الموافقة (2.3): العتبة، النتيجة المرجّحة، النصاب، المصوّتون، المهلة، القرار.
/// يفصل بين "النصاب" (نسبة الحصص المشاركة) و"العتبة" (نسبة الموافقة المطلوبة)،
/// ولا يعرض عدم التصويت أبداً كموافقة.
class ApprovalPanel extends StatelessWidget {
  final double threshold; // نسبة الموافقة المطلوبة من إجمالي الحصص
  final double quorum; // الحد الأدنى للحصص المشاركة (0 = لا يوجد)
  final double agree;
  final double disagree;
  final double neutral;
  final List<VoterLine> voters;
  final DateTime? deadline;
  final GovStatus? decision;

  const ApprovalPanel({
    super.key,
    required this.threshold,
    this.quorum = 0,
    required this.agree,
    required this.disagree,
    required this.neutral,
    this.voters = const [],
    this.deadline,
    this.decision,
  });

  double get participating => agree + disagree + neutral;
  double get notVoted => (100 - participating).clamp(0, 100).toDouble();
  bool get quorumMet => participating + 1e-6 >= quorum;

  @override
  Widget build(BuildContext context) {
    return GovCard(
      title: 'حالة القرار',
      icon: Icons.how_to_vote_rounded,
      trailing: decision == null ? null : StatusBadge(decision!, dense: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Meter(threshold: threshold, agree: agree, neutral: neutral, disagree: disagree),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _Legend('موافق', agree, const Color(0xFF2ECC71)),
              _Legend('محايد', neutral, const Color(0xFF7C8CA3)),
              _Legend('غير موافق', disagree, const Color(0xFFE74C3C)),
              _Legend('لم يصوّت', notVoted, AppColors.navyLight, outline: true),
            ],
          ),
          const Divider(height: 22),
          _Row('العتبة المطلوبة', '${_pct(threshold)} موافقة من إجمالي الحصص'),
          if (quorum > 0)
            _Row('النصاب', '${_pct(participating)} مشاركة من ${_pct(quorum)} مطلوبة',
                color: quorumMet ? AppColors.success : AppColors.warning),
          _Row('النتيجة الحالية', '${_pct(agree)} موافقة',
              color: agree + 1e-6 >= threshold ? AppColors.success : AppColors.textPrimary),
          if (deadline != null) _Row('المهلة', _dt.format(deadline!)),
          if (notVoted > 0)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('عدم التصويت لا يُحتسب موافقة.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ),
          if (voters.isNotEmpty) ...[
            const Divider(height: 22),
            ...voters.map((v) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text(v.name,
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5))),
                      Text(_pct(v.weight), style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 86,
                        child: Text(v.vote ?? 'لم يصوّت',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                                color: v.voteColor ?? AppColors.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  final double threshold, agree, neutral, disagree;
  const _Meter({required this.threshold, required this.agree, required this.neutral, required this.disagree});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      Widget seg(double p, Color col) => Container(width: w * p / 100, color: col);
      return SizedBox(
        height: 22,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(color: AppColors.navyLight, borderRadius: BorderRadius.circular(8)),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Row(children: [
                seg(agree, const Color(0xFF2ECC71)),
                seg(neutral, const Color(0xFF7C8CA3)),
                seg(disagree, const Color(0xFFE74C3C)),
              ]),
            ),
            PositionedDirectional(
              start: (w * threshold / 100).clamp(0, w - 2),
              top: -4,
              bottom: -4,
              child: Container(width: 2.5, color: AppColors.goldLight),
            ),
          ],
        ),
      );
    });
  }
}

class _Legend extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final bool outline;
  const _Legend(this.label, this.value, this.color, {this.outline = false});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: outline ? Colors.transparent : color,
              shape: BoxShape.circle,
              border: outline ? Border.all(color: AppColors.textMuted) : null,
            ),
          ),
          const SizedBox(width: 5),
          Text('$label ${_pct(value)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
        ],
      );
}

class _Row extends StatelessWidget {
  final String k, v;
  final Color? color;
  const _Row(this.k, this.v, {this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 110,
                child: Text(k, style: const TextStyle(color: AppColors.textMuted, fontSize: 12))),
            Expanded(
              child: Text(v,
                  style: TextStyle(
                      color: color ?? AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

// ───────────────────────── مكوّن التدقيق والخط الزمني ─────────────────────────

/// الخط الزمني لأحداث التدقيق: يميز فعل المستخدم عن فعل النظام ومحرك القواعد
class AuditTimeline extends StatelessWidget {
  final List<AuditEvent> events;
  final bool shrinkWrap;
  const AuditTimeline({super.key, required this.events, this.shrinkWrap = true});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('لا توجد أحداث مسجلة بعد.', style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < events.length; i++)
          _AuditTile(event: events[i], last: i == events.length - 1),
      ],
    );
  }
}

class _AuditTile extends StatelessWidget {
  final AuditEvent event;
  final bool last;
  const _AuditTile({required this.event, required this.last});

  @override
  Widget build(BuildContext context) {
    final e = event;
    final c = e.actorType == ActorType.user ? AppColors.gold : AppColors.info;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: c.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Icon(e.actorType.icon, size: 13, color: c),
                ),
                if (!last) Expanded(child: Container(width: 1.4, color: AppColors.divider)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.action,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '${e.actorName.isEmpty ? e.actorType.label : e.actorName} · ${_dt.format(e.at.toLocal())}'
                    '${e.result.isEmpty ? '' : ' · ${e.result}'}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                  if (e.evidenceRef != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text('مرجع: ${e.evidenceRef}',
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── لوحة الأدلة ─────────────────────────

enum EvidenceKind { signature, biometric, witness, notification, hash, timestamp }

extension EvidenceKindX on EvidenceKind {
  IconData get icon => switch (this) {
        EvidenceKind.signature => Icons.draw_rounded,
        EvidenceKind.biometric => Icons.fingerprint_rounded,
        EvidenceKind.witness => Icons.person_pin_rounded,
        EvidenceKind.notification => Icons.sms_rounded,
        EvidenceKind.hash => Icons.lock_rounded,
        EvidenceKind.timestamp => Icons.schedule_rounded,
      };
}

class EvidenceItem {
  final EvidenceKind kind;
  final String label;
  final String value;
  final bool ok;
  final bool copyable;
  const EvidenceItem(this.kind, this.label, this.value, {this.ok = true, this.copyable = false});
}

/// لوحة الأدلة (2.3 و 9.1): التوقيع، البصمة، الشاهد، مرجع الإشعار، مرجع سلامة المستند
class EvidencePanel extends StatelessWidget {
  final List<EvidenceItem> items;
  const EvidencePanel({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return GovCard(
      title: 'الأدلة',
      icon: Icons.verified_user_rounded,
      child: Column(
        children: items
            .map((it) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(it.kind.icon, size: 18, color: it.ok ? AppColors.success : AppColors.textMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(it.label,
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                            Text(it.value,
                                textDirection: it.kind == EvidenceKind.hash ? TextDirection.ltr : null,
                                style: const TextStyle(
                                    color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      if (it.copyable)
                        IconButton(
                          tooltip: 'نسخ المرجع',
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          onPressed: () => Clipboard.setData(ClipboardData(text: it.value)),
                        ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

// ───────────────────────── مكوّن تقييم القاعدة ─────────────────────────

/// مكوّن تقييم القاعدة (2.3): معرّف القاعدة، الشرط، القيمة المرصودة، الحد، النتيجة، الإجراء
class RuleEvaluationCard extends StatelessWidget {
  final String ruleId;
  final String condition;
  final String observed;
  final String expected;
  final GovStatus result;
  final String action;
  final String? ruleVersion;

  const RuleEvaluationCard({
    super.key,
    required this.ruleId,
    required this.condition,
    required this.observed,
    required this.expected,
    required this.result,
    required this.action,
    this.ruleVersion,
  });

  @override
  Widget build(BuildContext context) {
    return GovCard(
      title: 'تقييم القاعدة $ruleId',
      icon: Icons.rule_rounded,
      trailing: StatusBadge(result, dense: true),
      child: Column(
        children: [
          _Row('الشرط', condition),
          _Row('القيمة المرصودة', observed),
          _Row('الحد في العقد', expected),
          _Row('الإجراء', action, color: result.color),
          if (ruleVersion != null) _Row('إصدار القاعدة', ruleVersion!),
        ],
      ),
    );
  }
}
