import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/company.dart';
import '../../models/dispute.dart';
import '../../models/operations.dart';
import '../../models/ops_extra.dart';
import '../../models/questionnaire.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../providers/daily_ops_state.dart';
import '../../providers/dispute_state.dart';
import '../../providers/operations_state.dart';
import '../../services/report_pdf.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

final _d = DateFormat('yyyy/MM/dd');

enum ReportType { financial, compliance, governance, disputes, audit, currentAccount, payroll, plans }

extension ReportTypeX on ReportType {
  String get label => switch (this) {
        ReportType.financial => 'العمليات المالية',
        ReportType.compliance => 'المخالفات والاستثناءات',
        ReportType.governance => 'الحوكمة والإصدارات والقرارات',
        ReportType.disputes => 'النزاعات',
        ReportType.audit => 'سجل التدقيق',
        ReportType.currentAccount => 'الحساب الجاري للشريك المدير',
        ReportType.payroll => 'الرواتب',
        ReportType.plans => 'الخطط ومتابعة التنفيذ',
      };

  String get category => switch (this) {
        ReportType.financial || ReportType.currentAccount || ReportType.payroll => 'مالية',
        ReportType.compliance || ReportType.audit => 'رقابية',
        ReportType.governance || ReportType.disputes => 'حوكمة',
        ReportType.plans => 'إدارية',
      };

  IconData get icon => switch (this) {
        ReportType.financial => Icons.receipt_long_rounded,
        ReportType.compliance => Icons.gpp_bad_rounded,
        ReportType.governance => Icons.layers_rounded,
        ReportType.disputes => Icons.gavel_rounded,
        ReportType.audit => Icons.manage_search_rounded,
        ReportType.currentAccount => Icons.account_balance_wallet_rounded,
        ReportType.payroll => Icons.payments_rounded,
        ReportType.plans => Icons.event_note_rounded,
      };

  /// نقطة الإفصاح التي تحكم الاطلاع على التقرير
  String? get controlPoint => switch (this) {
        ReportType.currentAccount => 'partner.currentAccount',
        ReportType.payroll => 'payroll.salaries',
        ReportType.audit => 'audit.export',
        ReportType.disputes => 'dispute.case',
        _ => null,
      };
}

enum _Period { month, quarter, year, all }

extension on _Period {
  String get label => switch (this) {
        _Period.month => 'هذا الشهر',
        _Period.quarter => 'آخر 3 أشهر',
        _Period.year => 'هذه السنة',
        _Period.all => 'كل الفترات',
      };

  DateTime? get start {
    final n = DateTime.now();
    return switch (this) {
      _Period.month => DateTime(n.year, n.month),
      _Period.quarter => DateTime(n.year, n.month - 2),
      _Period.year => DateTime(n.year),
      _Period.all => null,
    };
  }
}

/// P20 (الشركاء) + O13 (التشغيل): كتالوج التقارير. كل تقرير يحدد الفترة وإصدار العقد الذي طُبقت
/// قواعده، ويُثبَّت ببصمة سلامة، ويحترم صلاحيات الدور ونقاط الإفصاح. التوليد عند الطلب.
class ReportsScreen extends StatelessWidget {
  final bool operational;
  const ReportsScreen({super.key, this.operational = false});

  static List<ReportType> catalog(bool operational) => operational
      ? const [ReportType.financial, ReportType.compliance, ReportType.currentAccount, ReportType.payroll, ReportType.plans, ReportType.audit]
      : const [
          ReportType.financial,
          ReportType.compliance,
          ReportType.governance,
          ReportType.disputes,
          ReportType.currentAccount,
          ReportType.audit,
        ];

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final list = catalog(operational);
    final cats = list.map((t) => t.category).toSet();

    return Scaffold(
      appBar: AppBar(title: Text(operational ? 'التقارير التشغيلية' : 'تقارير الشركاء')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            StateBanner.readOnly('التقارير تُولَّد عند الطلب فقط. الجدولة التلقائية تحتاج خادماً يعمل في الخلفية.'),
            for (final cat in cats) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 6),
                child: Text('تقارير $cat', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
              ),
              for (final t in list.where((t) => t.category == cat))
                Builder(builder: (context) {
                  final allowed = t.controlPoint == null || cs.canSee(t.controlPoint!);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      enabled: allowed,
                      leading: Icon(t.icon, color: allowed ? AppColors.gold : AppColors.textMuted),
                      title: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(allowed ? 'اختر الفترة ثم عاين وصدّر' : 'غير متاح لدورك حسب نقاط الإفصاح',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      trailing: const Icon(Icons.chevron_left_rounded),
                      onTap: allowed
                          ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportViewScreen(type: t)))
                          : null,
                    ),
                  );
                }),
            ],
          ],
        ),
      ),
    );
  }
}

/// بيانات تقرير جاهزة للعرض والتصدير
class ReportData {
  final String title;
  final String context;
  final List<(String, List<(String, String)>)> sections;
  const ReportData(this.title, this.context, this.sections);

  int get rows => sections.fold(0, (a, s) => a + s.$2.length);
}

ReportData buildReport(ReportType t, DateTime? since, Company c, CompanyState cs, ContractState st, OperationsState ops,
    DisputeState ds, DailyOpsState daily) {
  bool inPeriod(DateTime d) => since == null || !d.isBefore(since);
  final current = st.currentContract(c.id);
  final ctx = current == null ? 'لا يوجد عقد معتمد' : 'إصدار العقد الساري ${current.version}';
  String name(String id) => c.members.where((m) => m.id == id).firstOrNull?.name ?? id;
  switch (t) {
    case ReportType.financial:
      final txs = ops.txFor(c.id).where((x) => inPeriod(x.date)).toList();
      final versions = txs.map((x) => st.sessions.where((s) => s.id == x.contractRef).firstOrNull?.version).whereType<int>().toSet();
      return ReportData(t.label, '$ctx · القواعد المطبقة من الإصدار ${versions.isEmpty ? '—' : versions.join('، ')}', [
        ('الإجمالي حسب الفئة', [
          for (final cat in TxCategory.values)
            if (txs.any((x) => x.category == cat))
              (cat.label,
                  '${txs.where((x) => x.category == cat).length} عمليات · المقبول ${formatCurrency(txs.where((x) => x.category == cat && (x.status == TxStatus.allowed || x.status == TxStatus.releasedException)).fold<double>(0, (a, x) => a + x.amount), c.currency)}'),
        ]),
        ('العمليات', [
          for (final x in txs)
            ('${_d.format(x.date)} · ${x.category.label} · ${x.status.label}',
                '${x.payee}: ${formatCurrency(x.amount, x.currency)}${x.triggered.isEmpty ? '' : ' · ${x.triggered.map((r) => '${r.ruleId} ج${r.ruleVersion}').join('، ')}'}'),
        ]),
      ]);
    case ReportType.compliance:
      return ReportData(t.label, ctx, [
        ('المخالفات', [
          for (final v in ops.violationsFor(c.id).where((v) => inPeriod(v.createdAt)))
            ('${_d.format(v.createdAt)} · ${v.status.label}', '${v.ruleName}: ${v.description}'),
        ]),
        ('الاستثناءات لمرة واحدة', [
          for (final x in ops.exceptionsFor(c.id).where((x) => inPeriod(x.createdAt)))
            ('${_d.format(x.createdAt)} · ${x.status.label}', '${x.ruleName}: ${formatCurrency(x.requestedAmount, c.currency)} (الحد ${x.originalLimit})'),
        ]),
      ]);
    case ReportType.governance:
      return ReportData(t.label, ctx, [
        ('إصدارات العقد', [
          for (final s in st.versionsFor(c.id))
            ('الإصدار ${s.version} · ${s.changeType.label} · ${s.status.label}${s.archived ? ' (مؤرشف)' : ''}',
                '${s.changeSummary ?? 'عقد التأسيس'}${s.contentHash == null ? '' : ' · SHA-256 ${s.contentHash!.substring(0, 16)}…'}'),
        ]),
        ('تنفيذ القرارات', [
          for (final d in daily.decisions(c, st, ds, ops).where((d) => inPeriod(d.effective)))
            ('${_d.format(d.effective)} · ${d.type} · ${daily.executionOf(d.id).status.label}', d.result),
        ]),
      ]);
    case ReportType.disputes:
      return ReportData(t.label, ctx, [
        ('التذاكر', [
          for (final d in ds.disputesFor(c.id).where((d) => inPeriod(d.openedAt)))
            ('${_d.format(d.openedAt)} · ${d.trigger.label} · ${d.stage.label} · ${d.status.label}', '${d.issue}${d.outcome == null ? '' : ' · النتيجة: ${d.outcome}'}'),
        ]),
      ]);
    case ReportType.audit:
      return ReportData(t.label, ctx, [
        ('الأحداث', [
          for (final e in cs.audit.where((e) => inPeriod(e.at)))
            ('${_d.format(e.at)} · ${e.actorType.label}${e.contractVersion == null ? '' : ' · الإصدار ${e.contractVersion}'}',
                '${e.actorName.isEmpty ? '' : '${e.actorName}: '}${e.action}${e.result.isEmpty ? '' : ' · ${e.result}'}'),
        ]),
      ]);
    case ReportType.currentAccount:
      final entries = daily.ledgerFor(c, ops).where((e) => inPeriod(e.date)).toList();
      final bal = daily.balances(c, ops);
      return ReportData(t.label, ctx, [
        ('الأرصدة (كل عملة منفصلة)', [
          for (final e in bal.entries)
            for (final b in e.value.entries) (name(e.key), '${b.key.label}: ${formatCurrency(b.value, b.key)}'),
        ]),
        ('القيود', [
          for (final e in entries)
            ('${_d.format(e.date)} · ${e.kind.label}${e.automatic ? ' (آلي)' : ''}',
                '${e.signed > 0 ? '+' : '−'}${formatCurrency(e.amount, e.currency)} · ${e.reference}'),
        ]),
      ]);
    case ReportType.payroll:
      return ReportData(t.label, ctx, [
        for (final b in daily.payrollFor(c.id).where((b) => inPeriod(b.createdAt)))
          ('دفعة ${b.period} · ${b.status.label} · ${formatCurrency(b.total, b.currency)}', [
            for (final l in b.lines) ('${l.employee} · ${l.role}', formatCurrency(l.total, b.currency)),
          ]),
      ]);
    case ReportType.plans:
      return ReportData(t.label, ctx, [
        for (final p in daily.plansFor(c.id).where((p) => since == null || p.year >= since.year))
          ('${p.title} · ${p.category.label} ${p.year} · ${p.status.label}', [
            for (final m in p.milestones)
              ('${m.period}: ${m.title}',
                  '${m.status.label}${m.target == null ? '' : ' · المستهدف ${m.target!.toStringAsFixed(0)}'}${m.actual == null ? '' : ' · الفعلي ${m.actual!.toStringAsFixed(0)}'}${m.deviation == null || m.deviation!.isEmpty ? '' : ' · ${m.deviation}'}'),
          ]),
      ]);
  }
}

class ReportViewScreen extends StatefulWidget {
  final ReportType type;
  const ReportViewScreen({super.key, required this.type});

  @override
  State<ReportViewScreen> createState() => _ReportViewScreenState();
}

class _ReportViewScreenState extends State<ReportViewScreen> {
  _Period _p = _Period.month;
  bool _preview = false;

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final c = cs.current!;
    final data = buildReport(widget.type, _p.start, c, cs, context.watch<ContractState>(), context.watch<OperationsState>(),
        context.watch<DisputeState>(), context.watch<DailyOpsState>());
    final hash = sha256.convert(utf8.encode(jsonEncode(data.sections.map((s) => [s.$1, s.$2.map((r) => [r.$1, r.$2]).toList()]).toList()))).toString();
    final subtitle = '${c.legalName} · ${_p.label} · ${data.context} · طلبه ${cs.me?.name ?? ''} · ${_d.format(DateTime.now())}';

    return Scaffold(
      appBar: AppBar(title: Text(widget.type.label)),
      body: _preview
          ? PdfPreview(
              build: (f) => ReportPdf.build(f, title: 'تقرير ${data.title}', subtitle: subtitle, hash: hash, sections: data.sections),
              initialPageFormat: PdfPageFormat.a4,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              pdfFileName: 'تقرير_${widget.type.name}.pdf',
              scrollViewDecoration: const BoxDecoration(color: AppColors.navyDark),
              loadingWidget: const Center(child: CircularProgressIndicator()),
              onError: (context, error) => const StateView.error(message: 'تعذّر توليد الملف. تحقق من الاتصال لتحميل الخطوط ثم أعد المحاولة.'),
            )
          : ContentWidth(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
                children: [
                  SegmentedButton<_Period>(
                    segments: [for (final p in _Period.values) ButtonSegment(value: p, label: Text(p.label, style: const TextStyle(fontSize: 12)))],
                    selected: {_p},
                    onSelectionChanged: (s) => setState(() => _p = s.first),
                  ),
                  const SizedBox(height: 12),
                  StateBanner(
                    color: AppColors.info,
                    icon: Icons.verified_rounded,
                    text: '${data.context} · مرجع سلامة التقرير ${hash.substring(0, 16)}…',
                  ),
                  if (data.rows == 0)
                    const StateView.empty(icon: Icons.inbox_rounded, title: 'لا توجد بيانات', message: 'غيّر الفترة أو انتظر تسجيل عمليات.')
                  else ...[
                    for (final (name, rows) in data.sections)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ExpansionTile(
                          initiallyExpanded: true,
                          title: Text('$name (${rows.length})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          children: [
                            for (final (k, v) in rows.take(30))
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(v, style: const TextStyle(fontSize: 12.5)),
                                subtitle: Text(k, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                              ),
                            if (rows.length > 30)
                              Text('و${rows.length - 30} سطراً آخر في الملف', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                          ],
                        ),
                      ),
                    ElevatedButton.icon(
                      onPressed: () {
                        cs.log(c.id,
                            action: 'توليد تقرير: ${data.title}',
                            objectType: 'report',
                            objectId: widget.type.name,
                            result: '${_p.label} · ${data.rows} سطراً',
                            evidenceRef: 'SHA-256: $hash');
                        setState(() => _preview = true);
                      },
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      label: const Text('معاينة وتصدير PDF'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
