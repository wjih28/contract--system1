import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/gov_status.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/questionnaire.dart';
import '../../providers/contract_state.dart';
import '../../theme/app_theme.dart';
import '../contract/clause_voting_screen.dart';

/// P07: البنود المؤجلة والمحيّدة. التحييد يظهر مختلفاً بوضوح عن الموافقة.
class DeferredScreen extends StatelessWidget {
  final String sessionId;
  const DeferredScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<ContractState>();
    final s = st.sessions.where((x) => x.id == sessionId).firstOrNull;
    if (s == null) return const Scaffold(body: StateView.empty(title: 'الجلسة غير موجودة', message: ''));
    final deferred = s.records.where((r) => r.status == ClauseStatus.deferred).toList();
    final neutral = s.records.where((r) => r.status == ClauseStatus.neutralized).toList();
    final readOnly = s.status == SessionStatus.completed;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المؤجلة والمحيّدة'),
          bottom: TabBar(tabs: [
            Tab(text: 'المؤجلة (${deferred.length})'),
            Tab(text: 'المحيّدة (${neutral.length})'),
          ]),
        ),
        body: ContentWidth(
          child: TabBarView(children: [
            _List(
              session: s,
              items: deferred,
              status: GovStatus.deferred,
              readOnly: readOnly,
              empty: const StateView.empty(
                icon: Icons.event_available_rounded,
                title: 'لا توجد بنود مؤجلة',
                message: 'كل البنود المؤجلة حُسمت. يمكن تأجيل أي بند لجلسة لاحقة من شاشة التصويت.',
              ),
            ),
            _List(
              session: s,
              items: neutral,
              status: GovStatus.neutralized,
              readOnly: readOnly,
              empty: const StateView.empty(
                icon: Icons.block_rounded,
                title: 'لا توجد بنود محيّدة',
                message: 'التحييد يُسقط البند من العقد باتفاق جميع الشركاء، وهو ليس موافقة على البند.',
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  final ContractSession session;
  final List<ClauseRecord> items;
  final GovStatus status;
  final Widget empty;
  final bool readOnly;
  const _List({
    required this.session,
    required this.items,
    required this.status,
    required this.empty,
    required this.readOnly,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return empty;
    final st = context.read<ContractState>();
    final fmt = DateFormat('yyyy/MM/dd');
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (status == GovStatus.neutralized)
          StateBanner(
            color: status.color,
            icon: Icons.info_outline_rounded,
            text: 'البنود المحيّدة مستبعدة من العقد باتفاق الشركاء، ولا تُعد موافقة عليها. سجلها محفوظ في التدقيق.',
          ),
        if (status == GovStatus.deferred)
          const StateBanner(
            color: AppColors.warning,
            icon: Icons.schedule_rounded,
            text: 'لا يُصدر العقد قبل حسم كل البنود المؤجلة بالتصويت أو بالتحييد.',
          ),
        ...items.map((r) {
          final q = st.question(r.questionId);
          final idx = session.records.indexOf(r);
          final partner = session.partners.where((p) => p.id == r.concernedPartnerId).firstOrNull;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.navySurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: status.color.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(q.id, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(partner == null ? q.title : '${q.title} – ${partner.name}',
                          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                    ),
                    StatusBadge(status, dense: true),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (r.deferReason != null) 'السبب: ${r.deferReason}',
                    if (r.resolvedAt != null) 'التاريخ: ${fmt.format(r.resolvedAt!)}',
                    'الجولة ${r.round}',
                    if (r.notes.isNotEmpty) '${r.notes.length} ملاحظات',
                  ].join(' · '),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                if (!readOnly) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ClauseVotingScreen(sessionId: session.id, initialIndex: idx),
                          ),
                        ),
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('فتح البند'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => st.reopen(session, r),
                        icon: const Icon(Icons.how_to_vote_rounded, size: 16),
                        label: const Text('استئناف القرار'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }
}
