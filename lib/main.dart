import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'providers/company_state.dart';
import 'providers/contract_state.dart';
import 'models/company.dart';
import 'models/dispute.dart';
import 'models/operations.dart';
import 'providers/daily_ops_state.dart';
import 'providers/dispute_state.dart';
import 'providers/operations_state.dart';
import 'services/backend.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Backend.init();
  runApp(const MithaqApp());
}

/// ربط مزوّد النزاعات ببقية الحالة:
/// - اعتماد إصدار جديد يحدّث رقم إصدار الشركة وجدول الحصص
/// - الجمود في التصويت وتصعيد المخالفة يفتحان تذكرة نزاع
/// - النزاع القائم يقفل التعديلات، والتحكيم يوقف الاستثناءات
DisputeState _wireDisputes(BuildContext ctx) {
  final companies = ctx.read<CompanyState>();
  final contracts = ctx.read<ContractState>();
  final ops = ctx.read<OperationsState>();
  Company? companyOf(String? id) => companies.companies.where((c) => c.id == id).firstOrNull;

  final d = DisputeState()
    ..auditSink = companies.log
    ..companyOf = companyOf
    ..onCompanyStatus = companies.setStatus;
  d.notifier = (c, dispute, subject, {deadline = '—'}) => ops.notifyCompany(
        c,
        NotifCategory.legal,
        dispute.entries.length <= 1 ? 'T-DISPUTE' : 'T-DISPUTE-STAGE',
        subject: subject,
        deadline: deadline,
        relatedType: 'dispute',
        relatedId: dispute.id,
      );

  contracts
    ..amendmentLocked = d.locked
    ..onVersionCompleted = (s) {
      if (s.companyId == null) return;
      companies.applyVersion(s.companyId!, s.version, equity: {for (final p in s.partners) p.id: p.equity});
      final c = companyOf(s.companyId);
      final dispute = s.disputeRef == null ? null : d.dispute(s.disputeRef!);
      if (c != null && dispute != null) {
        d.addEntry(c, dispute, EntryKind.evidence, 'اعتُمد الإصدار ${s.version} من العقد تنفيذاً للحسم.',
            authorId: 'system', authorName: 'النظام', evidenceRef: 'SHA-256: ${s.contentHash}');
      }
    }
    ..onDeadlock = (s, r) {
      final c = companyOf(s.companyId);
      if (c == null) return;
      d.open(
        c,
        trigger: DisputeTrigger.deadlock,
        issue: 'جمود في البند "${contracts.question(r.questionId).title}" بعد ${r.failures + 1} جولات لم تُحسم'
            '${s.isAmendment ? ' (مقترح الإصدار ${s.version})' : ''}',
        relatedType: 'clause',
        relatedId: '${s.id}:${r.key}:${r.round}',
        openedBy: 'system',
        openedByName: 'النظام',
      );
    };

  ops
    ..exceptionsLocked = d.arbitrationActive
    ..onViolationEscalated = (c, v) => d.open(
          c,
          trigger: DisputeTrigger.violation,
          issue: v.description,
          relatedType: 'violation',
          relatedId: v.id,
          openedBy: companies.me?.id ?? 'system',
          openedByName: companies.me?.name ?? 'النظام',
        );

  return d
    ..load()
    ..startTicker();
}

class MithaqApp extends StatelessWidget {
  const MithaqApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => CompanyState()..load()),
        // كل إجراء في جلسات التأسيس يُسجَّل في سجل تدقيق الشركة
        ChangeNotifierProvider(
          create: (ctx) => ContractState()
            ..auditSink = ctx.read<CompanyState>().log
            ..load(),
        ),
        // الرقابة المالية: العمليات والتجميد والاستثناءات والمخالفات والإشعارات
        ChangeNotifierProvider(
          create: (ctx) => OperationsState()
            ..auditSink = ctx.read<CompanyState>().log
            ..load(),
        ),
        // التشغيل اليومي: الحساب الجاري، الرواتب، الخطط، المراسلات، تنفيذ القرارات، التنبيهات
        ChangeNotifierProvider(
          create: (ctx) => DailyOpsState()
            ..auditSink = ctx.read<CompanyState>().log
            ..load(),
        ),
        // الإصدارات والنزاعات: تربط العقد والرقابة المالية بمسار النزاع
        ChangeNotifierProvider(lazy: false, create: (ctx) => _wireDisputes(ctx)),
      ],
      child: MaterialApp(
        title: 'ميثاق',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        locale: const Locale('ar'),
        builder: (context, child) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const SplashScreen(),
      ),
    );
  }
}
