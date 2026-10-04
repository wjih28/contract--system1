import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/company.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../establishment/witness_tasks_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../admin/clause_library_screen.dart';
import '../admin/currency_settings_screen.dart';
import '../admin/logic_rules_screen.dart';
import '../admin/voting_settings_screen.dart';
import '../company/audit_log_screen.dart';
import '../company/compliance_screen.dart';
import '../company/partners_screen.dart';
import '../contract/new_session_screen.dart';
import '../contract/question_bank_screen.dart';
import '../contracts_screen.dart';
import '../company/my_companies_screen.dart';
import '../company/partner_dashboard_screen.dart';
import '../establishment/voting_center_screen.dart';
import '../admin/admin_dashboard_screen.dart';
import '../admin/companies_screen.dart';
import '../admin/control_points_screen.dart';
import '../admin/platform_settings_screen.dart';
import '../admin/roles_screen.dart';
import '../admin/security_monitor_screen.dart';
import '../admin/users_screen.dart';
import '../admin/version_manager_screen.dart';
import '../disputes/disputes_screen.dart';
import '../operations/approval_center_screen.dart';
import '../operations/correspondence_screen.dart';
import '../operations/current_account_screen.dart';
import '../operations/decision_execution_screen.dart';
import '../operations/expense_limits_screen.dart';
import '../operations/ops_alerts_screen.dart';
import '../operations/payroll_screen.dart';
import '../operations/plans_screen.dart';
import '../reports/reports_screen.dart';
import '../family/constitution_screen.dart';
import '../family/distribution_succession_screens.dart';
import '../family/family_dashboard_screen.dart';
import '../family/family_decisions_screen.dart';
import '../family/family_tree_screen.dart';
import '../../providers/family_state.dart';
import '../professional/accounting_review_screen.dart';
import '../professional/invitation_screen.dart';
import '../professional/legal_review_screen.dart';
import '../professional/pro_archive_screen.dart';
import '../professional/pro_comments_screen.dart';
import '../professional/pro_dashboard_screen.dart';
import '../professional/professional_reviews_screen.dart';
import '../../providers/professional_state.dart';
import '../../providers/daily_ops_state.dart';
import '../versions/versions_screen.dart';
import '../profile_screen.dart';
import '../../providers/dispute_state.dart';
import '../../providers/operations_state.dart';
import '../admin/channels_screen.dart';
import '../admin/expense_limits_screen.dart';
import '../admin/integrations_screen.dart';
import '../admin/rule_test_screen.dart';
import '../operations/approvals_screen.dart';
import '../operations/notifications_center_screen.dart';
import '../operations/ops_dashboard_screen.dart';
import '../operations/transactions_screen.dart';
import '../operations/violations_screen.dart';

/// هيكل التطبيق الموحد للبوابات الأربع:
/// - شريط علوي: الشركة الحالية، البوابة، الإشعارات، الحساب
/// - قائمة هامبرغر تجمع كل واجهات البوابة المسموحة للدور، وتبديل البوابة، والشركات
/// - جوال ولوحي: القائمة منزلقة من زر الهامبرغر، حاسب: القائمة نفسها مثبتة ويطويها الزر
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppModule? _module;
  bool _menuOpen = true;

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    if (!cs.loaded) return const Scaffold(body: SkeletonList());
    if (cs.companies.isEmpty) {
      // شاهد مدعو من خارج الشركة: يرى مهامه فقط
      return context.watch<ContractState>().witnessTasks.isNotEmpty ? const WitnessTasksScreen() : const _NoCompany();
    }

    // متابعة عمليات الشركة الحالية لحظياً (في وضع الخادم)
    final companyId = cs.current?.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CompanyState>().touchLastSeen();
      context.read<OperationsState>().watchCompany(companyId);
      context.read<DisputeState>().watchCompany(companyId);
      context.read<DailyOpsState>().watchCompany(companyId);
      context.read<ProfessionalState>().watchCompany(companyId);
      context.read<FamilyState>().watchCompany(companyId);
      final me = context.read<CompanyState>().me;
      if (me != null && me.staff && me.roles.any((r) => r == CompanyRole.lawyer || r == CompanyRole.accountant)) {
        context.read<ContractState>().watchCompanySessions(companyId);
      }
    });

    final modules = cs.myModules;
    if (modules.isEmpty) {
      return Scaffold(
        appBar: const _TopBar(),
        body: const StateView.denied(message: 'لا يوجد لك دور مفعّل في هذه الشركة بعد.'),
      );
    }
    final current = modules.contains(_module) ? _module! : modules.first;
    // R01: الطرف المهني لا يصل إلى وحداته قبل قبول دعوته، ولا بعد انتهاء تكليفه
    final page = KeyedSubtree(
        key: ValueKey('${cs.current?.id}-$current'), child: ProfessionalGate(child: _pageFor(current)));
    final size = context.screenSize;

    void go(AppModule m) => setState(() => _module = m);

    final desktop = size == ScreenSize.desktop;
    final menu = _NavMenu(modules: modules, current: current, onSelect: go, pinned: desktop);

    // الجوال واللوحي: كل واجهات البوابة في قائمة الهامبرغر
    if (!desktop) {
      return Scaffold(
        appBar: const _TopBar(),
        drawer: Drawer(
          width: MediaQuery.sizeOf(context).width * 0.86 > 320 ? 320 : MediaQuery.sizeOf(context).width * 0.86,
          backgroundColor: AppColors.navyMedium,
          child: menu,
        ),
        body: page,
      );
    }

    // الحاسب: القائمة نفسها مثبتة بجانب المحتوى، وزر الهامبرغر يطويها ويفتحها
    return Scaffold(
      appBar: _TopBar(onMenu: () => setState(() => _menuOpen = !_menuOpen)),
      body: Row(
        children: [
          if (_menuOpen) ...[
            SizedBox(width: 280, child: Material(color: AppColors.navyMedium, child: menu)),
            const VerticalDivider(width: 1),
          ],
          Expanded(child: page),
        ],
      ),
    );
  }

  Widget _pageFor(AppModule m) => switch (m) {
        AppModule.dashboard => const PartnerDashboardScreen(),
        AppModule.partners => const PartnersScreen(),
        AppModule.establishment => const ContractsScreen(),
        AppModule.voting => const VotingCenterScreen(),
        AppModule.approvals => const ApprovalsScreen(),
        AppModule.transactions => const TransactionsScreen(),
        AppModule.disputes => const DisputesScreen(),
        AppModule.partnerReports => const ReportsScreen(),
        AppModule.opsExpenses => const ExpenseLimitsMonitorScreen(),
        AppModule.currentAccount => const CurrentAccountScreen(),
        AppModule.payroll => const PayrollScreen(),
        AppModule.approvalCenter => const ApprovalCenterScreen(),
        AppModule.decisionExecution => const DecisionExecutionScreen(),
        AppModule.plans => const PlansScreen(),
        AppModule.correspondence => const CorrespondenceScreen(),
        AppModule.opsAlerts => const OpsAlertsScreen(),
        AppModule.opsReports => const ReportsScreen(operational: true),
        AppModule.versions => const VersionsScreen(),
        AppModule.versionManager => const VersionManagerScreen(),
        AppModule.notifications => const NotificationsCenterScreen(),
        AppModule.profile => const ProfileScreen(),
        AppModule.adminDashboard => const AdminDashboardScreen(),
        AppModule.companies => const CompaniesScreen(),
        AppModule.users => const UsersScreen(),
        AppModule.roles => const RolesScreen(),
        AppModule.controlPoints => const ControlPointsScreen(),
        AppModule.securityMonitor => const SecurityMonitorScreen(),
        AppModule.platformSettings => const PlatformSettingsScreen(),
        AppModule.questionBank => const QuestionBankScreen(),
        AppModule.clauseLibrary => const ClauseLibraryScreen(),
        AppModule.logicRules => const LogicRulesScreen(),
        AppModule.votingSettings => const VotingSettingsScreen(),
        AppModule.currencySettings => const CurrencySettingsScreen(),
        AppModule.auditLog => const AuditLogScreen(),
        AppModule.operationsDashboard => const OpsDashboardScreen(),
        AppModule.opsTransactions => const TransactionsScreen(),
        AppModule.opsFrozen => const TransactionsScreen(frozenOnly: true),
        AppModule.opsViolations => const ViolationsScreen(),
        AppModule.ruleTest => const RuleTestScreen(),
        AppModule.expenseLimits => const ExpenseLimitsScreen(),
        AppModule.channels => const ChannelsScreen(),
        AppModule.integrations => const IntegrationsScreen(),
        AppModule.professionalTasks => const ProDashboardScreen(),
        AppModule.engagement => const EngagementScreen(),
        AppModule.legalReview => const LegalReviewScreen(),
        AppModule.accountingReview => const AccountingReviewScreen(),
        AppModule.proComments => const ProCommentsScreen(),
        AppModule.proArchive => const ProArchiveScreen(),
        AppModule.professionalReviews => const ProfessionalReviewsScreen(),
        AppModule.compliance => const ComplianceScreen(),
        AppModule.familyDashboard => const FamilyDashboardScreen(),
        AppModule.familyConstitution => const ConstitutionScreen(),
        AppModule.familyTree => const FamilyTreeScreen(),
        AppModule.familyDistribution => const DistributionScreen(),
        AppModule.familySuccession => const SuccessionScreen(),
        AppModule.familyDecisions => const FamilyDecisionsScreen(),
      };
}

/// الشريط العلوي: الشركة الحالية، البوابة، الإشعارات، الحساب
class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  /// في الحاسب: طي القائمة المثبتة وفتحها. في الجوال واللوحي يظهر زر القائمة تلقائياً.
  final VoidCallback? onMenu;
  const _TopBar({this.onMenu});

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final c = cs.current;
    return AppBar(
      toolbarHeight: 60,
      leading: onMenu == null ? null : IconButton(tooltip: 'القائمة', icon: const Icon(Icons.menu_rounded), onPressed: onMenu),
      centerTitle: false,
      titleSpacing: 12,
      title: PopupMenuButton<String>(
        tooltip: 'تبديل الشركة',
        color: AppColors.navySurface,
        onSelected: (v) {
          if (v == '_new') {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const NewSessionScreen()));
          } else if (v == '_all') {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const MyCompaniesScreen()));
          } else {
            cs.select(v);
          }
        },
        itemBuilder: (_) => [
          for (final x in cs.companies)
            PopupMenuItem(
              value: x.id,
              child: Row(children: [
                Icon(x.id == c?.id ? Icons.check_rounded : Icons.business_rounded,
                    size: 18, color: x.id == c?.id ? AppColors.gold : AppColors.textMuted),
                const SizedBox(width: 8),
                Expanded(child: Text(x.legalName)),
              ]),
            ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: '_all',
            child: Row(children: [
              Icon(Icons.apartment_rounded, size: 18, color: AppColors.gold),
              SizedBox(width: 8),
              Text('كل شركاتي'),
            ]),
          ),
          const PopupMenuItem(
            value: '_new',
            child: Row(children: [
              Icon(Icons.add_business_rounded, size: 18, color: AppColors.gold),
              SizedBox(width: 8),
              Text('تأسيس شركة جديدة'),
            ]),
          ),
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MithaqLogo(size: 34),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text((c?.legalName.isNotEmpty ?? false) ? c!.legalName : 'ميثاق',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                  Text(
                    '${cs.portal.label}${c == null ? '' : ' · ${c.status.label}'}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.expand_more_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
      actions: const [SizedBox(width: 6)],
    );
  }
}

/// لا توجد شركات بعد (P02 حالة فارغة): شرح وإجراء تالٍ واضح
class _NoCompany extends StatelessWidget {
  const _NoCompany();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: StateView.empty(
          icon: Icons.add_business_rounded,
          title: 'لا توجد لديك شركات بعد',
          message: 'ابدأ بتأسيس شركة: بياناتها، ثم الشركاء وحصصهم، ثم جلسة التأسيس للتصويت على بنود العقد.\n'
              'إذا دعاك شريك إلى شركته فستظهر هنا تلقائياً بعد أن يضيف رقم جوالك.',
          actionLabel: 'تأسيس شركة جديدة',
          onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewSessionScreen())),
        ),
      ),
    );
  }
}

/// قائمة الهامبرغر الموحدة لكل البوابات: رأس بالشركة والمستخدم، ثم تبديل البوابة،
/// ثم واجهات البوابة الحالية، ثم الواجهات العامة، ثم الشركات.
class _NavMenu extends StatelessWidget {
  final List<AppModule> modules;
  final AppModule current;
  final void Function(AppModule) onSelect;
  final bool pinned;
  const _NavMenu({required this.modules, required this.current, required this.onSelect, required this.pinned});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final c = cs.current;
    final me = cs.me;
    final portals = cs.myPortals;
    final own = modules.where((m) => m.portal == cs.portal && !m.shared).toList();
    final general = modules.where((m) => !own.contains(m)).toList();

    void close() {
      if (!pinned) Navigator.of(context).maybePop();
    }

    void open(AppModule m) {
      close();
      onSelect(m);
    }

    Widget section(String title) => Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 6),
          child: Text(title,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .3)),
        );

    Widget item(AppModule m) {
      final selected = m == current;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        child: ListTile(
          dense: true,
          selected: selected,
          selectedTileColor: AppColors.gold.withValues(alpha: 0.14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: Icon(m.icon, size: 21, color: selected ? AppColors.gold : AppColors.textSecondary),
          title: Text(m.label,
              style: TextStyle(
                  fontSize: 14,
                  color: selected ? AppColors.gold : AppColors.textPrimary,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
          onTap: () => open(m),
        ),
      );
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          // رأس القائمة: الشركة والمستخدم ودوره
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider))),
            child: Row(children: [
              const MithaqLogo(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((c?.legalName.isNotEmpty ?? false) ? c!.legalName : 'ميثاق',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
                  if (me != null)
                    Text('${me.name} · ${me.roles.map((r) => r.label).join('، ')}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ]),
              ),
            ]),
          ),
          // تبديل البوابة: كل بوابات المستخدم من القائمة نفسها
          if (portals.length > 1) ...[
            section('البوابات'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final p in portals)
                  ChoiceChip(
                    avatar: Icon(p.icon, size: 16, color: p == cs.portal ? AppColors.gold : AppColors.textMuted),
                    label: Text(p.label, style: const TextStyle(fontSize: 12.5)),
                    selected: p == cs.portal,
                    onSelected: (_) => cs.portal = p,
                  ),
              ]),
            ),
          ],
          section(cs.portal.label),
          for (final m in own) item(m),
          if (general.isNotEmpty) ...[
            section('عام'),
            for (final m in general) item(m),
          ],
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1)),
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 26),
            leading: const Icon(Icons.apartment_rounded, size: 21, color: AppColors.textSecondary),
            title: const Text('كل شركاتي', style: TextStyle(fontSize: 14)),
            onTap: () {
              close();
              Navigator.push(context, MaterialPageRoute(builder: (_) => const MyCompaniesScreen()));
            },
          ),
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 26),
            leading: const Icon(Icons.add_business_rounded, size: 21, color: AppColors.gold),
            title: const Text('تأسيس شركة جديدة', style: TextStyle(fontSize: 14)),
            onTap: () {
              close();
              Navigator.push(context, MaterialPageRoute(builder: (_) => const NewSessionScreen()));
            },
          ),
        ],
      ),
    );
  }
}
