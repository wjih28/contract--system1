import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/gov_status.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/governance_config.dart';
import '../../providers/contract_state.dart';
import '../../providers/operations_state.dart';
import '../../theme/app_theme.dart';

final _dt = DateFormat('yyyy/MM/dd');

/// A19: إدارة إصدارات عناصر الإعداد (البنود، القواعد، القوالب).
/// الإصدارات التاريخية لا تُستبدل ولا تُحذف؛ المسودة تُنشر فتسري على الجلسات الجديدة فقط،
/// والجلسات القائمة تحتفظ بلقطتها. تظهر الاعتماديات قبل النشر.
class VersionManagerScreen extends StatelessWidget {
  const VersionManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: _Bar(),
        body: ContentWidth(child: TabBarView(children: [_ClausesTab(), _RulesTab(), _TemplatesTab()])),
      ),
    );
  }
}

class _Bar extends StatelessWidget implements PreferredSizeWidget {
  const _Bar();
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 48);
  @override
  Widget build(BuildContext context) => AppBar(
        title: const Text('إدارة الإصدارات'),
        bottom: const TabBar(tabs: [Tab(text: 'البنود القانونية'), Tab(text: 'القواعد المنطقية'), Tab(text: 'قوالب الرسائل')]),
      );
}

/// حالة الإصدار في دورة حياته: مسودة، ساري، مؤرشف (حلّ محله أحدث)، موقوف
(GovStatus, String) _state(ConfigStatus s, bool current) => switch (s) {
      ConfigStatus.draft => (GovStatus.draft, 'مسودة'),
      ConfigStatus.retired => (GovStatus.archived, 'موقوف'),
      ConfigStatus.published => current ? (GovStatus.approved, 'الساري') : (GovStatus.archived, 'مؤرشف'),
    };

class _ClausesTab extends StatelessWidget {
  const _ClausesTab();

  @override
  Widget build(BuildContext context) {
    final st = context.watch<ContractState>();
    final ids = st.clauseVersions.map((c) => c.questionId).toSet().toList()
      ..sort((a, b) => st.clauseVersions.where((c) => c.questionId == b).length
          .compareTo(st.clauseVersions.where((c) => c.questionId == a).length));
    return ListView(padding: const EdgeInsets.all(20), children: [
      const _Note(),
      for (final id in ids) _ClauseGroup(questionId: id),
    ]);
  }
}

class _ClauseGroup extends StatelessWidget {
  final String questionId;
  const _ClauseGroup({required this.questionId});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<ContractState>();
    final versions = st.clauseVersions.where((c) => c.questionId == questionId).toList()
      ..sort((a, b) => b.version.compareTo(a.version));
    final current = st.publishedClause(questionId);
    final draft = versions.where((v) => v.status == ConfigStatus.draft).firstOrNull;
    // الاعتماديات: الجلسات التي تحتفظ بلقطة من كل إصدار، والأسئلة المشروطة بهذا السؤال
    int usedBy(int v) => st.sessions.where((s) => s.records.any((r) => r.questionId == questionId && r.clauseVersion == v)).length;
    final dependents = st.conditions.entries.where((e) => e.value.sourceQuestionId == questionId).map((e) => e.key).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        title: Text(versions.first.title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('$questionId · ${versions.length} إصدارات${draft == null ? '' : ' · مسودة جاهزة للنشر'}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          if (dependents.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('اعتماديات: الأسئلة ${dependents.join('، ')} مشروطة بهذا السؤال.',
                  style: const TextStyle(color: AppColors.warning, fontSize: 12)),
            ),
          for (final v in versions)
            _VersionRow(
              version: v.version,
              state: _state(v.status, v.version == current?.version),
              date: v.updatedAt,
              usage: usedBy(v.version),
              onCompare: () {
                final prev = versions.where((x) => x.version < v.version).firstOrNull;
                _showDiff(context, 'البند ${v.title}', prev == null ? null : 'الإصدار ${prev.version}', prev?.text,
                    'الإصدار ${v.version}', v.text);
              },
            ),
          if (draft != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: ElevatedButton.icon(
                onPressed: () => _confirmPublish(context, 'البند "${draft.title}" الإصدار ${draft.version}',
                    () => st.publishClause(questionId)),
                icon: const Icon(Icons.publish_rounded),
                label: Text('نشر الإصدار ${draft.version}'),
              ),
            ),
        ],
      ),
    );
  }
}

class _RulesTab extends StatelessWidget {
  const _RulesTab();

  @override
  Widget build(BuildContext context) {
    final st = context.watch<ContractState>();
    final ids = st.ruleVersions.map((r) => r.questionId).toSet().toList();
    return ListView(padding: const EdgeInsets.all(20), children: [
      const _Note(),
      for (final id in ids)
        Builder(builder: (context) {
          final versions = st.ruleVersions.where((r) => r.questionId == id).toList()
            ..sort((a, b) => b.version.compareTo(a.version));
          final current = st.publishedRule(id);
          final draft = versions.where((v) => v.status == ConfigStatus.draft).firstOrNull;
          int usedBy(int v) => st.sessions
              .where((s) => s.records.any((r) => r.questionId == id && (r.rule?['version'] as num?)?.toInt() == v))
              .length;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ExpansionTile(
              title: Text(versions.first.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${versions.first.id} · ${versions.length} إصدارات · مرتبطة بالبند $id',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                for (final v in versions)
                  _VersionRow(
                    version: v.version,
                    state: _state(v.status, v.version == current?.version),
                    usage: usedBy(v.version),
                    onCompare: () {
                      final prev = versions.where((x) => x.version < v.version).firstOrNull;
                      _showDiff(context, 'القاعدة ${v.name}', prev == null ? null : 'الإصدار ${prev.version}',
                          prev?.describe(), 'الإصدار ${v.version}', v.describe());
                    },
                  ),
                if (draft != null)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: ElevatedButton.icon(
                      onPressed: () => _confirmPublish(context, 'القاعدة "${draft.name}" الإصدار ${draft.version}', () {
                        final errors = st.publishRule(id);
                        if (errors.isNotEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errors.join('، '))));
                        }
                      }),
                      icon: const Icon(Icons.publish_rounded),
                      label: Text('نشر الإصدار ${draft.version}'),
                    ),
                  ),
              ],
            ),
          );
        }),
    ]);
  }
}

class _TemplatesTab extends StatelessWidget {
  const _TemplatesTab();

  @override
  Widget build(BuildContext context) {
    final ops = context.watch<OperationsState>();
    return ListView(padding: const EdgeInsets.all(20), children: [
      const StateBanner(
        color: AppColors.info,
        icon: Icons.info_outline_rounded,
        text: 'تعديل القالب من "القنوات والقوالب" يرفع رقم إصداره. الإشعارات المرسلة سابقاً تحتفظ بنصها ومرجع إصدار قالبها.',
      ),
      for (final t in ops.templates)
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            title: Text(t.event, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${t.id} · ${t.subject}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            trailing: StatusBadge(GovStatus.approved, overrideLabel: 'الإصدار ${t.version}', dense: true),
          ),
        ),
    ]);
  }
}

class _VersionRow extends StatelessWidget {
  final int version;
  final (GovStatus, String) state;
  final DateTime? date;
  final int usage;
  final VoidCallback onCompare;
  const _VersionRow({required this.version, required this.state, this.date, required this.usage, required this.onCompare});

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(radius: 14, backgroundColor: AppColors.navyLight, child: Text('$version', style: const TextStyle(fontSize: 12))),
        title: Row(children: [StatusBadge(state.$1, overrideLabel: state.$2, dense: true)]),
        subtitle: Text(
          '${date == null ? '' : 'آخر تحديث ${_dt.format(date!)} · '}${usage == 0 ? 'لا تستخدمه جلسات' : 'تحتفظ بلقطته $usage جلسات'}',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
        ),
        trailing: TextButton(onPressed: onCompare, child: const Text('الفرق')),
      );
}

class _Note extends StatelessWidget {
  const _Note();
  @override
  Widget build(BuildContext context) => StateBanner.readOnly(
      'الإصدارات التاريخية محفوظة للتدقيق ولا تُستبدل. النشر يسري على الجلسات الجديدة فقط، وعقود الشركات القائمة لا تتغير إلا بإصدار عقد جديد يقرّه الشركاء.');
}

void _showDiff(BuildContext context, String title, String? aLabel, String? a, String bLabel, String b) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.navySurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (a == null)
                const Text('الإصدار الأول: لا يوجد إصدار سابق للمقارنة.', style: TextStyle(color: AppColors.textMuted))
              else
                GovCard(title: aLabel!, icon: Icons.remove_circle_outline_rounded, child: Text(a, style: const TextStyle(height: 1.7))),
              const SizedBox(height: 10),
              GovCard(title: bLabel, icon: Icons.add_circle_outline_rounded, child: Text(b, style: const TextStyle(height: 1.7))),
              if (a != null && a == b)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('لا فرق في النص.', style: TextStyle(color: AppColors.textMuted)),
                ),
            ]),
          ),
        ),
      ),
    );

Future<void> _confirmPublish(BuildContext context, String what, VoidCallback publish) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.navySurface,
      title: const Text('نشر إصدار'),
      content: Text('نشر $what؟\nيسري على الجلسات الجديدة فقط، ولا يغيّر الجلسات والعقود القائمة.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('نشر')),
      ],
    ),
  );
  if (ok == true) publish();
}
