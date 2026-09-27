import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';
import 'contracts_screen.dart';
import 'notifications_screen.dart';
import 'dispute_room_screen.dart';
import 'profile_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  final _pages = const [
    DashboardScreen(),
    ContractsScreen(),
    NotificationsScreen(),
    DisputeRoomScreen(),
    ProfileScreen(),
  ];

  final _items = const [
    (Icons.space_dashboard_rounded, 'المراقبة'),
    (Icons.description_rounded, 'العقود'),
    (Icons.notifications_active_rounded, 'التنبيهات'),
    (Icons.gavel_rounded, 'التقاضي'),
    (Icons.person_rounded, 'حسابي'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.navyMedium,
          border: const Border(
            top: BorderSide(color: AppColors.divider, width: 1),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 64,
            child: Row(
              children: List.generate(_items.length, (i) {
                final selected = i == _index;
                final item = _items[i];
                return Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _index = i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          item.$1,
                          color: selected
                              ? AppColors.gold
                              : AppColors.textMuted,
                          size: 22,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.$2,
                          style: TextStyle(
                            color: selected
                                ? AppColors.gold
                                : AppColors.textMuted,
                            fontSize: 10.5,
                            fontWeight: selected
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
