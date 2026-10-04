import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/gov_status.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/operations.dart';
import '../../models/questionnaire.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../providers/dispute_state.dart';
import '../../providers/operations_state.dart';
import '../../services/identity_service.dart';
import '../../theme/app_theme.dart';
import '../contract/finalize_screen.dart';
import '../establishment/decision_details_screen.dart';
import '../establishment/final_contract_screen.dart';
import 'versions_screen.dart';

/// J03 الخطوة 1: مقترح تعديل. يحدد الشريك البنود المتأثرة وقيمها الجديدة وسبب التعديل.
/// العقد الساري لا يتغير؛ يُنشأ إصدار جديد يمر بالتصويت المرجّح ثم التوقيع ثم الاعتماد.
class AmendmentProposalScreen extends StatefulWidget {
  /// النزاع الذي يُنفَّذ صلحه بهذا التعديل (يتجاوز قفل التعديلات لهذا النزاع فقط)
  final String? disputeRef;
  const AmendmentProposalScreen({super.key, this.disputeRef});

  @override
  State<AmendmentProposalScreen> createState() => _AmendmentProposalScreenState();
}

class _AmendmentProposalScreenState extends State<AmendmentProposalScreen> {
  final Map<String, TextEditingController> _ctrl = {};
  final _reason = TextEditingController();
  String? _error;
  bool _burden = false;

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final st = context.watch<ContractState>();
    final c = cs.current;
    final base = st.currentContract(c?.id);
    if (c == null || base == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('اقتراح تعديل')),
          body: const StateView.empty(title: 'لا يوجد عقد معتمد', message: 'التعديل يكون على عقد معتمد وموقّع.'));
    }
    final blocker = st.amendmentBlocker(c.id, disputeRef: widget.disputeRef);
    final records = st.amendableRecords(base);

    return Scaffold(
      appBar: AppBar(title: Text('مقترح الإصدار ${base.version + 1}')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            if (blocker != null)
              StateBanner(color: AppColors.warning, icon: Icons.lock_clock_rounded, text: blocker)
            else
              StateBanner(
                color: AppColors.info,
                icon: Icons.info_outline_rounded,
                text: 'يبقى الإصدار ${base.version} سارياً حتى يُعتمد الإصدار الجديد ويوقّعه الشركاء. '
                    'البنود التي تعدّلها فقط تُطرح للتصويت بالنصاب والعتبة المرجّحين بالحصص.',
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
              ),
            const Text('البنود القابلة للتعديل', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final r in records) _row(st, base, r),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'سبب التعديل (إلزامي)', alignLabelWithHint: true),
            ),
            CheckboxListTile(
              value: _burden,
              onChanged: (v) => setState(() => _burden = v ?? false),
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.gold,
              title: const Text('التعديل يزيد الأعباء المالية على الشركاء', style: TextStyle(fontSize: 13)),
              subtitle: Text(
                  _burden
                      ? 'يتطلب إجماع الشركاء (100%) وفق القانون اليمني'
                      : 'تعديل العقد قرار جوهري يتطلب موافقة 75% من رأس المال على الأقل',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: blocker == null ? () => _submit(context, base) : null,
              icon: const Icon(Icons.send_rounded),
              label: const Text('تقديم المقترح للتصويت'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(ContractState st, ContractSession base, ClauseRecord r) {
    final q = st.question(r.questionId);
    final ctrl = _ctrl.putIfAbsent(r.key, TextEditingController.new);
    final partner = r.concernedPartnerId == null
        ? null
        : base.partners.where((p) => p.id == r.concernedPartnerId).firstOrNull?.name;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${q.title}${partner == null ? '' : ' ($partner)'}',
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13.5)),
              const SizedBox(height: 2),
              Text('الحالي: ${st.formatValue(base, q, r.value)}${q.paramKind == ParamKind.percent ? '%' : ''}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ]),
          ),
          SizedBox(
            width: 130,
            child: TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              onChanged: (_) => setState(() => _error = null),
              decoration: const InputDecoration(labelText: 'القيمة الجديدة', isDense: true),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _submit(BuildContext context, ContractSession base) async {
    final st = context.read<ContractState>();
    final cs = context.read<CompanyState>();
    final changes = <String, double>{};
    for (final e in _ctrl.entries) {
      final v = double.tryParse(e.value.text.trim());
      final cur = base.records.firstWhere((r) => r.key == e.key).value;
      if (v != null && v != cur) changes[e.key] = v;
    }
    if (changes.isEmpty) return setState(() => _error = 'أدخل قيمة جديدة لبند واحد على الأقل.');
    if (_reason.text.trim().length < 5) return setState(() => _error = 'اكتب سبب التعديل.');
    final me = cs.me;
    if (me == null) return;
    final m = await IdentityService.confirm(context, partnerName: me.name, action: 'تقديم مقترح تعديل العقد');
    if (m == null || !context.mounted) return;
    final s = st.proposeAmendment(base,
        changes: changes, reason: _reason.text, proposedBy: me.id, disputeRef: widget.disputeRef, burdenIncrease: _burden);
    final ds = context.read<DisputeState>();
    final d = widget.disputeRef == null ? null : ds.dispute(widget.disputeRef!);
    if (d != null) ds.linkAmendment(cs.current!, d, s.id);
    context.read<OperationsState>().notifyCompany(cs.current!, NotifCategory.legal, 'T-AMENDMENT',
        subject: s.changeSummary ?? '', relatedType: 'contract', relatedId: s.id);
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AmendmentDetailScreen(sessionId: s.id)));
  }
}

/// تفاصيل مقترح التعديل: البنود المعدّلة (قبل وبعد) وحالة التصويت عليها، ثم التوقيع والاعتماد.
class AmendmentDetailScreen extends StatelessWidget {
  final String sessionId;
  const AmendmentDetailScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<ContractState>();
    final cs = context.watch<CompanyState>();
    final s = st.sessions.where((x) => x.id == sessionId).firstOrNull;
    if (s == null) return const Scaffold(body: StateView.empty(title: 'المقترح غير متاح', message: ''));
    if (s.status == SessionStatus.completed) return FinalContractScreen(sessionId: s.id);
    final base = st.sessions.where((x) => x.id == s.amends).firstOrNull;
    final (gs, label) = versionState(s);
    final amended = s.records.where((r) => r.amended).toList();
    final open = s.status != SessionStatus.withdrawn;
    final failed = amended.any((r) =>
        r.status == ClauseStatus.rejected || r.status == ClauseStatus.quorumFailed || r.status == ClauseStatus.deadlock);

    return Scaffold(
      appBar: AppBar(title: Text('مقترح الإصدار ${s.version}')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            if (!open)
              StateBanner.readOnly('أُنهي هذا المقترح دون اعتماد، ويبقى محفوظاً في سجل الإصدارات.')
            else if (failed)
              const StateBanner(
                color: AppColors.warning,
                icon: Icons.report_problem_rounded,
                text: 'لم يحصل بند معدّل على الأغلبية المطلوبة. يمكن إعادة التصويت من تفاصيل البند، أو إنهاء المقترح ويبقى العقد الحالي سارياً.',
              ),
            GovCard(
              title: '${s.changeType.label} · يعدّل الإصدار ${base?.version ?? s.version - 1}',
              icon: Icons.edit_note_rounded,
              trailing: StatusBadge(gs, overrideLabel: label, dense: true),
              child: Text(s.changeSummary ?? '',
                  style: const TextStyle(color: AppColors.textSecondary, height: 1.7, fontSize: 13)),
            ),
            const SizedBox(height: 12),
            if (s.changeType == ChangeType.capTable && base != null)
              GovCard(
                title: 'جدول الحصص قبل وبعد',
                icon: Icons.pie_chart_rounded,
                child: Column(children: [
                  for (final p in s.partners)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(p.name),
                      trailing: Text(
                        '${base.partners.firstWhere((x) => x.id == p.id, orElse: () => p).equity.toStringAsFixed(2)}% ← '
                        '${p.equity.toStringAsFixed(2)}%',
                        style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800),
                      ),
                    ),
                  const Text('لا يجري أي دفع داخل التطبيق؛ السداد يتم خارجه ويُرفق دليله في النزاع.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                ]),
              ),
            for (final r in amended) _amendedTile(context, st, s, r),
            const SizedBox(height: 12),
            if (open) ...[
              ElevatedButton.icon(
                onPressed: s.allResolved
                    ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => FinalizeScreen(sessionId: s.id)))
                    : null,
                icon: const Icon(Icons.draw_rounded),
                label: Text(s.allResolved ? 'التوقيع على الإصدار ${s.version} واعتماده' : 'التوقيع بعد حسم البنود المعدّلة'),
              ),
              const SizedBox(height: 8),
              if (cs.me?.isPartner ?? false)
                OutlinedButton.icon(
                  onPressed: () => _withdraw(context, s),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('إنهاء المقترح دون اعتماد'),
                ),
            ],
            if (base != null)
              TextButton.icon(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => VersionCompareScreen(fromId: base.id, toId: s.id))),
                icon: const Icon(Icons.compare_arrows_rounded),
                label: Text('مقارنة بالإصدار ${base.version}'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _amendedTile(BuildContext context, ContractState st, ContractSession s, ClauseRecord r) {
    final q = st.question(r.questionId);
    final unit = q.paramKind == ParamKind.percent ? '%' : '';
    final qr = st.quorum(s, r);
    final gs = switch (r.status) {
      ClauseStatus.agreed => GovStatus.approved,
      ClauseStatus.rejected || ClauseStatus.quorumFailed => GovStatus.rejected,
      ClauseStatus.deadlock => GovStatus.dispute,
      ClauseStatus.deferred => GovStatus.deferred,
      ClauseStatus.neutralized => GovStatus.neutralized,
      _ => GovStatus.pending,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => DecisionDetailsScreen(sessionId: s.id, recordKey: r.key))),
        title: Text(q.title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          '${st.formatValue(s, q, r.previousValue)}$unit ← ${st.formatValue(s, q, r.value)}$unit\n'
          'موافقة ${qr.agreeShare.toStringAsFixed(1)}% من ${qr.required.toStringAsFixed(0)}% مطلوبة · المشاركة ${qr.participation.toStringAsFixed(1)}%',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.6),
        ),
        isThreeLine: true,
        trailing: StatusBadge(gs, overrideLabel: r.status.label, dense: true),
      ),
    );
  }

  Future<void> _withdraw(BuildContext context, ContractSession s) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navySurface,
        title: const Text('إنهاء المقترح'),
        content: TextField(controller: reason, decoration: const InputDecoration(labelText: 'السبب')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تراجع')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إنهاء')),
        ],
      ),
    );
    if (ok == true && context.mounted) context.read<ContractState>().withdrawAmendment(s, reason: reason.text);
    reason.dispose();
  }
}
