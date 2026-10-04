import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/admin.dart';
import '../../models/company.dart';
import '../../providers/company_state.dart';
import '../../providers/operations_state.dart';
import '../../services/security_monitor.dart';
import '../../theme/app_theme.dart';
import '../operations/tx_widgets.dart';

final _dt = DateFormat('yyyy/MM/dd HH:mm');

/// A20: مراقبة الأمان والتكامل. فرز الأحداث ومعالجتها دون كشف أي أسرار أو بيانات بصمة.
class SecurityMonitorScreen extends StatefulWidget {
  const SecurityMonitorScreen({super.key});

  @override
  State<SecurityMonitorScreen> createState() => _SecurityMonitorScreenState();
}

class _SecurityMonitorScreenState extends State<SecurityMonitorScreen> {
  TriageState? _state;
  Severity? _sev;

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final ops = context.watch<OperationsState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final all = SecurityMonitor.events(c, cs.audit, ops.notifications);
    TriageState stateOf(SecurityEvent e) =>
        c.triage[e.id] == null ? (e.severity == Severity.info ? TriageState.resolved : TriageState.open) : Triage.fromJson(c.triage[e.id]!).state;
    final list = all
        .where((e) => _state == null || stateOf(e) == _state)
        .where((e) => _sev == null || e.severity == _sev)
        .toList();
    int count(bool Function(SecurityEvent) f) => all.where(f).length;

    return Scaffold(
      appBar: AppBar(title: const Text('مراقبة الأمان والتكامل')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            KpiGrid(items: [
              (w) => KpiCard(
                  label: 'أحداث جديدة تحتاج معالجة',
                  value: '${count((e) => stateOf(e) == TriageState.open)}',
                  icon: Icons.new_releases_rounded,
                  color: AppColors.warning,
                  width: w),
              (w) => KpiCard(
                  label: 'قيد التحقيق',
                  value: '${count((e) => stateOf(e) == TriageState.investigating)}',
                  icon: Icons.manage_search_rounded,
                  color: AppColors.info,
                  width: w),
              (w) => KpiCard(
                  label: 'شدّة مرتفعة',
                  value: '${count((e) => e.severity == Severity.high)}',
                  icon: Icons.priority_high_rounded,
                  color: AppColors.danger,
                  width: w),
              (w) => KpiCard(
                  label: 'تغييرات صلاحيات',
                  value: '${count((e) => e.type == 'تغيير صلاحيات')}',
                  icon: Icons.admin_panel_settings_rounded,
                  color: AppColors.gold,
                  width: w),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(label: const Text('كل الحالات'), selected: _state == null, onSelected: (_) => setState(() => _state = null)),
              for (final s in TriageState.values)
                ChoiceChip(label: Text(s.label), selected: _state == s, onSelected: (_) => setState(() => _state = s)),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(label: const Text('كل الشدّات'), selected: _sev == null, onSelected: (_) => setState(() => _sev = null)),
              for (final s in Severity.values)
                ChoiceChip(label: Text(s.label), selected: _sev == s, onSelected: (_) => setState(() => _sev = s)),
            ]),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const StateView.empty(
                icon: Icons.verified_user_rounded,
                title: 'لا توجد أحداث هنا',
                message: 'تظهر هنا أحداث الدخول وتغيير الصلاحيات والإعدادات والتوقيع والمزامنة وتسليم الإشعارات.',
              ),
            for (final e in list) _EventCard(c: c, e: e, state: stateOf(e)),
          ],
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final Company c;
  final SecurityEvent e;
  final TriageState state;
  const _EventCard({required this.c, required this.e, required this.state});

  @override
  Widget build(BuildContext context) {
    final t = c.triage[e.id] == null ? null : Triage.fromJson(c.triage[e.id]!);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => _open(context, t),
        leading: Icon(Icons.shield_outlined, color: e.severity.color),
        title: Text('${e.type} · ${e.component}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
        subtitle: Text(
          '${e.description}\n${_dt.format(e.at.toLocal())} · الشدّة: ${e.severity.label} · ${state.label}'
          '${t?.assignee == null ? '' : ' · ${t!.assignee}'}',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.5),
        ),
        isThreeLine: true,
      ),
    );
  }

  Future<void> _open(BuildContext context, Triage? t) async {
    final cs = context.read<CompanyState>();
    final note = TextEditingController(text: t?.note ?? '');
    var assignee = t?.assignee;
    var state = this.state;
    final admins = c.members.where((m) => m.active && m.roles.any((r) => r.portal == Portal.admin)).map((m) => m.name).toList();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.navySurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(e.type, style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(e.description, style: const TextStyle(color: AppColors.textSecondary, height: 1.6)),
            const SizedBox(height: 6),
            SelectableText('معرّف الربط: ${e.correlationId}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const Text('لا تُعرض هنا أي كلمات مرور أو مفاتيح أو بيانات بصمة أو مواد توقيع خاصة.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final s in TriageState.values)
                ChoiceChip(label: Text(s.label), selected: state == s, onSelected: (_) => set(() => state = s)),
            ]),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              initialValue: admins.contains(assignee) ? assignee : null,
              isExpanded: true,
              dropdownColor: AppColors.navySurface,
              decoration: const InputDecoration(labelText: 'إسناد إلى'),
              items: [
                const DropdownMenuItem(value: null, child: Text('غير مسند')),
                for (final a in admins) DropdownMenuItem(value: a, child: Text(a)),
              ],
              onChanged: (v) => set(() => assignee = v),
            ),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة التحقيق')),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: () {
                cs.triageEvent(c.id, e.id, state, assignee: assignee, note: note.text.trim());
                Navigator.pop(ctx);
              },
              child: const Text('حفظ المعالجة'),
            ),
          ]),
        ),
      ),
    );
    note.dispose();
  }
}
