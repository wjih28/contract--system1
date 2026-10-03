import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'providers/company_state.dart';
import 'providers/contract_state.dart';
import 'providers/operations_state.dart';
import 'services/backend.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Backend.init();
  runApp(const MithaqApp());
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
