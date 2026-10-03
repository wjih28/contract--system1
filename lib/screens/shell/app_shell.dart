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
import '../company/partners_screen.dart';
import '../contract/new_session_screen.dart';
import '../contract/question_bank_screen.dart';
import '../contracts_screen.dart';
import '../company/my_companies_screen.dart';
import '../company/partner_dashboard_screen.dart';
import '../establishment/voting_center_screen.dart';
import '../admin/version_manager_screen.dart';
import '../disputes/disputes_screen.dart';
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
/// - قائمة تُظهر الوحدات المسموحة للدور فقط
/// - جوال: شريط سفلي، لوحي: شريط جانبي مختصر، حاسب: قائمة جانبية كاملة
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppModule? _module;

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
      context.read<OperationsState>().watchCompany(companyId);
      context.read<DisputeState>().watchCompany(companyId);
    });

    final modules = cs.myModules;
    if (modules.isEmpty) {
      return Scaffold(
        appBar: const _TopBar(),
        body: const StateView.denied(message: 'لا يوجد لك دور مفعّل في هذه الشركة بعد.'),
      );
    }
    final current = modules.contains(_module) ? _module! : modules.first;
    final page = KeyedSubtree(key: ValueKey('${cs.current?.id}-$current'), child: _pageFor(current));
    final size = context.screenSize;

    void go(AppModule m) => setState(() => _module = m);

    if (size == ScreenSize.phone) {
      // الجوال: أول أربع وحدات في الشريط السفلي والباقي تحت "المزيد"
      final primary = modules.take(4).toList();
      final rest = modules.skip(4).toList();
      final idx = primary.indexOf(current);
      return Scaffold(
        appBar: const _TopBar(),
        body: page,
        bottomNavigationBar: NavigationBar(
          backgroundColor: AppColors.navyMedium,
          indicatorColor: AppColors.gold.withValues(alpha: 0.2),
          selectedIndex: idx < 0 ? primary.length : idx,
          onDestinationSelected: (i) {
            if (i < primary.length) {
              go(primary[i]);
            } else {
              _showMore(context, rest, current, go);
            }
          },
          destinations: [
            for (final m in primary) NavigationDestination(icon: Icon(m.icon), label: m.label),
            if (rest.isNotEmpty)
              const NavigationDestination(icon: Icon(Icons.more_horiz_rounded), label: 'المزيد'),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: const _TopBar(),
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: AppColors.navyMedium,
            extended: size == ScreenSize.desktop,
            minExtendedWidth: 230,
            selectedIndex: modules.indexOf(current),
            onDestinationSelected: (i) => go(modules[i]),
            indicatorColor: AppColors.gold.withValues(alpha: 0.2),
            selectedIconTheme: const IconThemeData(color: AppColors.gold),
            unselectedIconTheme: const IconThemeData(color: AppColors.textMuted),
            selectedLabelTextStyle: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800),
            unselectedLabelTextStyle: const TextStyle(color: AppColors.textSecondary),
            labelType: size == ScreenSize.desktop ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            destinations: [
              for (final m in modules) NavigationRailDestination(icon: Icon(m.icon), label: Text(m.label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: page),
        ],
      ),
    );
  }

  void _showMore(BuildContext context, List<AppModule> rest, AppModule current, void Function(AppModule) go) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.navySurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            for (final m in rest)
              ListTile(
                leading: Icon(m.icon, color: m == current ? AppColors.gold : AppColors.textSecondary),
                title: Text(m.label),
                onTap: () {
                  Navigator.pop(ctx);
                  go(m);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
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
        AppModule.versions => const VersionsScreen(),
        AppModule.versionManager => const VersionManagerScreen(),
        AppModule.notifications => const NotificationsCenterScreen(),
        AppModule.profile => const ProfileScreen(),
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
        AppModule.professionalTasks => const WitnessTasksScreen(),
      };
}

/// الشريط العلوي: الشركة الحالية، البوابة، الإشعارات، الحساب
class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopBar();

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final c = cs.current;
    final portals = cs.myPortals;
    return AppBar(
      toolbarHeight: 60,
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
                  Text(c?.legalName ?? 'ميثاق',
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
      actions: [
        if (portals.length > 1)
          PopupMenuButton<Portal>(
            tooltip: 'تبديل البوابة',
            icon: Icon(cs.portal.icon),
            color: AppColors.navySurface,
            onSelected: (p) => cs.portal = p,
            itemBuilder: (_) => [
              for (final p in portals)
                PopupMenuItem(value: p, child: Row(children: [Icon(p.icon, size: 18), const SizedBox(width: 8), Text(p.label)])),
            ],
          ),
        const SizedBox(width: 6),
      ],
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
