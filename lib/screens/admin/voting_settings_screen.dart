import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/questionnaire.dart';
import '../../providers/company_state.dart';
import '../../theme/app_theme.dart';

/// A11: إعدادات التصويت والنصاب للشركة، مع حاسبة معاينة بحصص الشركاء الفعلية.
/// تسري على جلسات التأسيس الجديدة فقط، والجلسة القائمة تحتفظ بإعداداتها.
class VotingSettingsScreen extends StatefulWidget {
  const VotingSettingsScreen({super.key});

  @override
  State<VotingSettingsScreen> createState() => _VotingSettingsScreenState();
}

class _VotingSettingsScreenState extends State<VotingSettingsScreen> {
  double? _quorum;
  int? _days;
  int? _deadlock;
  final Map<String, String> _sample = {}; // partnerId -> agree/disagree/neutral/none
  double _threshold = 66.67;

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final v = c.votingSettings;
    final quorum = _quorum ?? v.quorum;
    final days = _days ?? v.deadlineDays;
    final deadlock = _deadlock ?? v.deadlockAfter;
    final canGovern = cs.canGovern;
    final changed = canGovern && quorum != v.quorum || days != v.deadlineDays || deadlock != v.deadlockAfter;

    final partners = c.partners;
    final total = partners.fold<double>(0, (a, p) => a + p.equity);
    double share(String b) =>
        total == 0 ? 0 : partners.where((p) => (_sample[p.id] ?? 'none') == b).fold<double>(0, (a, p) => a + p.equity) / total * 100;
    final agree = share('agree');
    final participation = agree + share('disagree') + share('neutral');
    final quorumMet = participation + 1e-6 >= quorum;
    final passed = quorumMet && agree + 1e-6 >= _threshold;
    String pct(double x) => '${x.toStringAsFixed(x % 1 == 0 ? 0 : 2)}%';

    return Scaffold(
      appBar: AppBar(title: const Text('التصويت والنصاب')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            const StateBanner(
              color: AppColors.info,
              icon: Icons.info_outline_rounded,
              text: 'التصويت مرجّح بنسبة الملكية، وعدم التصويت ليس موافقة. '
                  'التعديل يسري على جلسات التأسيس الجديدة فقط.',
            ),
            if (!canGovern)
              const StateBanner(
                color: AppColors.warning,
                icon: Icons.gavel_rounded,
                text: 'النصاب والمهل من شروط الشركاء: يعدّلها شريك من بوابته، ومسؤول النظام يطّلع عليها فقط.',
              ),
            _Field(
              title: 'الحد الأدنى للمشاركة (النصاب)',
              hint: 'نسبة الحصص التي يجب أن تصوّت حتى يُعتد بالقرار بعد انتهاء المهلة',
              value: pct(quorum),
              child: Slider(
                value: quorum,
                min: 0,
                max: 100,
                divisions: 100,
                label: pct(quorum),
                onChanged: !canGovern ? null : (x) => setState(() => _quorum = x.roundToDouble()),
              ),
            ),
            _Field(
              title: 'مهلة التصويت على البند',
              hint: 'تبدأ من أول صوت، وبعدها يُحسم البند بالأصوات المسجلة أو يتعذّر النصاب',
              value: '$days أيام',
              child: Slider(
                value: days.toDouble(),
                min: 1,
                max: 30,
                divisions: 29,
                label: '$days',
                onChanged: !canGovern ? null : (x) => setState(() => _days = x.round()),
              ),
            ),
            _Field(
              title: 'الجمود بعد',
              hint: 'عدد الجولات الفاشلة المتتالية الذي يُعد جموداً',
              value: '$deadlock جولات',
              child: Slider(
                value: deadlock.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                label: '$deadlock',
                onChanged: !canGovern ? null : (x) => setState(() => _deadlock = x.round()),
              ),
            ),
            const SizedBox(height: 4),
            ElevatedButton.icon(
              onPressed: changed
                  ? () {
                      cs.updateVotingSettings(c.id, VotingSettings(quorum: quorum, deadlineDays: days, deadlockAfter: deadlock));
                      setState(() {
                        _quorum = null;
                        _days = null;
                        _deadlock = null;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('حُفظت الإعدادات وسُجّلت في التدقيق')));
                    }
                  : null,
              icon: const Icon(Icons.save_rounded),
              label: const Text('حفظ ونشر الإعدادات'),
            ),
            const SizedBox(height: 26),
            const Text('حاسبة المعاينة بحصص الشركاء الفعلية',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Text('العتبة: ', style: TextStyle(color: AppColors.textSecondary)),
              for (final t in const [50.01, 66.67, 75.0, 100.0])
                ChoiceChip(label: Text(pct(t)), selected: _threshold == t, onSelected: (_) => setState(() => _threshold = t)),
            ]),
            const SizedBox(height: 10),
            ...partners.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Expanded(child: Text('${p.name} (${pct(p.equity)})')),
                    DropdownButton<String>(
                      value: _sample[p.id] ?? 'none',
                      dropdownColor: AppColors.navySurface,
                      items: const [
                        DropdownMenuItem(value: 'none', child: Text('لم يصوّت')),
                        DropdownMenuItem(value: 'agree', child: Text('موافق')),
                        DropdownMenuItem(value: 'disagree', child: Text('غير موافق')),
                        DropdownMenuItem(value: 'neutral', child: Text('محايد')),
                      ],
                      onChanged: (x) => setState(() => _sample[p.id] = x!),
                    ),
                  ]),
                )),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (passed ? AppColors.success : AppColors.warning).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'المشاركة ${pct(participation)} ${quorumMet ? '(النصاب مكتمل)' : '(أقل من النصاب ${pct(quorum)})'} · '
                'الموافقة ${pct(agree)} من ${pct(_threshold)} مطلوبة ⟵ '
                '${!quorumMet ? 'تعذّر النصاب بعد المهلة' : passed ? 'يُعتمد البند' : 'لا يُعتمد'}',
                style: TextStyle(color: passed ? AppColors.success : AppColors.warning, fontWeight: FontWeight.w700, height: 1.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String title, hint, value;
  final Widget child;
  const _Field({required this.title, required this.hint, required this.value, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.navySurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700))),
            Text(value, style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w900, fontSize: 16)),
          ]),
          Text(hint, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
          child,
        ]),
      );
}
