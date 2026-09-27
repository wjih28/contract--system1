import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'transaction_detail_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final user = appState.currentUser;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'لوحة المراقبة',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            user != null
                                ? 'مرحباً، ${user.fullName}'
                                : 'برج مراقبة المستثمر',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: AppColors.gold.withValues(alpha: 0.15),
                      child: Text(
                        user?.avatarInitial ?? 'م',
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _ComplianceGauge(score: appState.complianceScore),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: StatCard(
                          label: 'الرصيد النقدي',
                          value: formatCurrency(appState.cashBalance),
                          icon: Icons.account_balance_wallet_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatCard(
                          label: 'المصروف الشهري',
                          value: formatCurrency(appState.monthlyExpense),
                          icon: Icons.trending_down_rounded,
                          accentColor: AppColors.warning,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatCard(
                          label: 'الأرباح المحققة',
                          value: formatCurrency(appState.realizedProfits),
                          icon: Icons.trending_up_rounded,
                          accentColor: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (appState.lossRatio >= 0.4) _CapitalRiskRadar(appState: appState),
                  if (appState.lossRatio >= 0.4) const SizedBox(height: 20),
                  GoldBorderCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SectionHeader(title: 'الرادار المالي - آخر 12 شهر'),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 140,
                          child: _RevenueChart(data: appState.revenueTrend),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'موازنة المصروف: ${formatCurrency(appState.monthlyExpense)} / ${formatCurrency(appState.monthlyExpenseCap)}',
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11.5,
                              ),
                            ),
                            Text(
                              '${((appState.monthlyExpense / appState.monthlyExpenseCap) * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: AppColors.gold,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: (appState.monthlyExpense /
                                    appState.monthlyExpenseCap)
                                .clamp(0, 1),
                            minHeight: 8,
                            backgroundColor: AppColors.navyLight,
                            color: AppColors.gold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const SectionHeader(title: 'أحدث المعاملات'),
                  const SizedBox(height: 12),
                  ...appState.transactions.map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _TransactionTile(transaction: t),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComplianceGauge extends StatelessWidget {
  final double score;
  const _ComplianceGauge({required this.score});

  @override
  Widget build(BuildContext context) {
    return GoldBorderCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Text(
            'مؤشر الالتزام التعاقدي',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: 160,
            height: 160,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 160,
                  height: 160,
                  child: CircularProgressIndicator(
                    value: 1,
                    strokeWidth: 12,
                    color: AppColors.navyLight,
                  ),
                ),
                SizedBox(
                  width: 160,
                  height: 160,
                  child: CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 12,
                    backgroundColor: Colors.transparent,
                    color: AppColors.gold,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${score.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Text(
                      'التزام مرتفع',
                      style: TextStyle(
                        color: AppColors.success,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CapitalRiskRadar extends StatelessWidget {
  final AppState appState;
  const _CapitalRiskRadar({required this.appState});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'رادار الإنذار المبكر لرأس المال',
                  style: TextStyle(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'الخسائر التراكمية بلغت ${(appState.lossRatio * 100).toStringAsFixed(0)}% من رأس المال',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RevenueChart extends StatelessWidget {
  final List<double> data;
  const _RevenueChart({required this.data});

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        minY: 0,
        maxY: 100,
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (int i = 0; i < data.length; i++)
                FlSpot(i.toDouble(), data[i]),
            ],
            isCurved: true,
            color: AppColors.gold,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.gold.withValues(alpha: 0.25),
                  AppColors.gold.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final LedgerTransaction transaction;
  const _TransactionTile({required this.transaction});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TransactionDetailScreen(transaction: transaction),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.navySurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: transaction.status.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                transaction.status.icon,
                color: transaction.status.color,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  StatusChip(
                    label: transaction.status.label,
                    color: transaction.status.color,
                    icon: transaction.status.icon,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatCurrency(transaction.amount),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
