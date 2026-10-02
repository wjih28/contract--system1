import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/admin.dart';
import '../../models/company.dart';
import '../../models/governance_config.dart';
import '../../models/operations.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../providers/operations_state.dart';
import '../../services/security_monitor.dart';
import '../../theme/app_theme.dart';
import '../company/audit_log_screen.dart';
import '../operations/tx_widgets.dart';
import 'companies_screen.dart';
import 'integrations_screen.dart';
import 'security_monitor_screen.dart';
import 'users_screen.dart';
import 'version_manager_screen.dart';

final _dt = DateFormat('yyyy/MM/dd HH:mm');

/// A01: لوحة الإدارة. مخاطر الإعداد والتشغيل التي تحتاج إجراء، وكل بطاقة تفتح شاشتها.
/// أدوات اللوحة لا تتجاوز موافقة الشركاء ولا إصدارات العقد.
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final st = context.watch<ContractState>();
    final ops = context.watch<OperationsState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');

    void go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    final drafts = st.clauseVersions.where((x) => x.status == ConfigStatus.draft).length +
        st.ruleVersions.where((x) => x.status == ConfigStatus.draft).length;
    final rules = ops.activeRules(st, c.id).length;
    final mandatory = ops.notifications.where((n) => n.companyId == c.id && n.category.mandatory).toList();
    final undelivered = mandatory.where((n) => n.deliveries.any((d) => d.status == DeliveryStatus.notConfigured)).length;
    final events = SecurityMonitor.events(c, cs.audit, ops.notifications);
    final openEvents = events
        .where((e) => e.severity != Severity.info && (c.triage[e.id] == null || Triage.fromJson(c.triage[e.id]!).state == TriageState.open))
        .length;
    final pendingInvites = c.staffMembers.where((m) => m.active && c.lastSeen[m.id] == null).length;
    final lastImport = cs.audit.where((e) => e.objectType == 'integration').firstOrNull;
    final adminActions = cs.audit.where((e) => const {'users', 'permissions', 'settings', 'security'}.contains(e.objectType)).take(6).toList();
    final attention = <(String, String, Widget)>[
      if (st.activeAmendment(c.id) != null) ('مقترح تعديل عقد قائم', 'بانتظار تصويت الشركاء وتوقيعهم', const CompaniesScreen()),
      if (c.contractVersion == 0) ('لا يوجد عقد معتمد', 'قواعد الرقابة لا تعمل قبل اعتماد عقد التأسيس', const CompaniesScreen()),
      if (drafts > 0) ('$drafts مسودات بنود وقواعد', 'تنتظر المراجعة والنشر', const VersionManagerScreen()),
      if (openEvents > 0) ('$openEvents أحداث أمنية جديدة', 'تحتاج فرزاً ومعالجة', const SecurityMonitorScreen()),
      if (pendingInvites > 0) ('$pendingInvites دعوات معلّقة', 'مستخدمون لم يدخلوا بعد', const UsersScreen()),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('لوحة الإدارة')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            KpiGrid(items: [
              (w) => KpiCard(
                  label: 'شركاتي (${cs.companies.length})',
                  value: c.status.label,
                  icon: Icons.apartment_rounded,
                  color: AppColors.gold,
                  width: w,
                  onTap: () => go(const CompaniesScreen())),
              (w) => KpiCard(
                  label: 'قواعد سارية من الإصدار ${c.contractVersion == 0 ? '—' : c.contractVersion}',
                  value: '$rules',
                  icon: Icons.rule_rounded,
                  color: rules == 0 ? AppColors.warning : AppColors.success,
                  width: w,
                  onTap: () => go(const VersionManagerScreen())),
              (w) => KpiCard(
                  label: 'إشعارات إلزامية بلا قناة خارجية',
                  value: '$undelivered من ${mandatory.length}',
                  icon: Icons.sms_failed_rounded,
                  color: undelivered == 0 ? AppColors.success : AppColors.warning,
                  width: w,
                  onTap: () => go(const SecurityMonitorScreen())),
              (w) => KpiCard(
                  label: lastImport == null ? 'التكامل: لم تُجرَ مزامنة' : 'آخر مزامنة ${_dt.format(lastImport.at.toLocal())}',
                  value: 'Xero / QB غير مربوط',
                  icon: Icons.sync_alt_rounded,
                  color: AppColors.textMuted,
                  width: w,
                  onTap: () => go(const IntegrationsScreen())),
            ]),
            const SizedBox(height: 14),
            GovCard(
              title: 'تحتاج انتباهك',
              icon: Icons.notification_important_rounded,
              child: attention.isEmpty
                  ? const Text('لا توجد مخاطر إعداد أو تشغيل تنتظر إجراء.', style: TextStyle(color: AppColors.success))
                  : Column(children: [
                      for (final (t, s, w) in attention)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.error_outline_rounded, color: AppColors.warning),
                          title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(s, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                          trailing: const Icon(Icons.chevron_left_rounded),
                          onTap: () => go(w),
                        ),
                    ]),
            ),
            const SizedBox(height: 12),
            GovCard(
              title: 'آخر الإجراءات الإدارية والأمنية',
              icon: Icons.history_rounded,
              trailing: TextButton(onPressed: () => go(const AuditLogScreen()), child: const Text('السجل كاملاً')),
              child: AuditTimeline(events: adminActions),
            ),
          ],
        ),
      ),
    );
  }
}
