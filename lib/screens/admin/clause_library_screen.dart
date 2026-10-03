import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/governance_config.dart';
import '../../models/questionnaire.dart';
import '../../providers/contract_state.dart';
import '../../theme/app_theme.dart';

/// A08: مكتبة البنود القانونية. لكل بند إصدارات؛ التعديل ينشئ مسودة، والنشر يسري على الجلسات الجديدة فقط.
class ClauseLibraryScreen extends StatefulWidget {
  const ClauseLibraryScreen({super.key});

  @override
  State<ClauseLibraryScreen> createState() => _ClauseLibraryScreenState();
}

class _ClauseLibraryScreenState extends State<ClauseLibraryScreen> {
  ClauseCategory? _cat;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final st = context.watch<ContractState>();
    final ids = st.bank.where((q) => _cat == null || q.category == _cat).map((q) => q.id).toList();
    final items = ids
        .map((id) => st.latestClause(id))
        .whereType<LegalClause>()
        .where((c) => _q.isEmpty || c.title.contains(_q) || c.text.contains(_q))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('مكتبة البنود القانونية')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            const StateBanner(
              color: AppColors.info,
              icon: Icons.info_outline_rounded,
              text: 'البند القانوني نص مقروء، والقاعدة المنطقية تنفيذه التشغيلي. '
                  'تعديل البند ينشئ إصداراً جديداً يسري على جلسات التأسيس الجديدة فقط، ولا يغيّر عقداً قائماً أو موقّعاً.',
            ),
            TextField(
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: const InputDecoration(hintText: 'بحث في العناوين والنصوص', prefixIcon: Icon(Icons.search_rounded)),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('الكل'), selected: _cat == null, onSelected: (_) => setState(() => _cat = null)),
              for (final c in ClauseCategory.values)
                ChoiceChip(label: Text(c.label), selected: _cat == c, onSelected: (_) => setState(() => _cat = c)),
            ]),
            const SizedBox(height: 14),
            if (items.isEmpty) const StateView.empty(title: 'لا نتائج', message: 'جرّب تعديل البحث أو التصفية.'),
            ...items.map((c) {
              final pub = st.publishedClause(c.questionId);
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => ClauseEditorScreen(questionId: c.questionId))),
                  leading: Icon(c.category.icon, color: c.category.color),
                  title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    '${c.id} · الإصدار المنشور ${pub?.version ?? '—'}'
                    '${c.status == ConfigStatus.draft ? ' · مسودة الإصدار ${c.version} قيد التحرير' : ''}'
                    '${st.publishedRule(c.questionId) == null ? '' : ' · مرتبط بقاعدة منطقية'}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                  ),
                  trailing: _StatusTag(c.status),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  final ConfigStatus status;
  const _StatusTag(this.status);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: status.color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(status.label, style: TextStyle(color: status.color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

/// محرر البند: النص مع رقائق المتغيرات ومعاينة فورية، وسجل الإصدارات
class ClauseEditorScreen extends StatefulWidget {
  final String questionId;
  const ClauseEditorScreen({super.key, required this.questionId});

  @override
  State<ClauseEditorScreen> createState() => _ClauseEditorScreenState();
}

class _ClauseEditorScreenState extends State<ClauseEditorScreen> {
  late final ContractState st = context.read<ContractState>();
  late final LegalClause _start = st.latestClause(widget.questionId)!;
  late final _title = TextEditingController(text: _start.title);
  late final _text = TextEditingController(text: _start.text);

  static const _vars = {
    'value': 'القيمة المتفق عليها',
    'capital': 'رأس المال',
    'partner': 'اسم الشريك',
    'currency': 'العملة',
  };

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  void _insert(String v) {
    final sel = _text.selection;
    final t = _text.text;
    final at = sel.isValid ? sel.start : t.length;
    final ins = '{$v}';
    _text.value = TextEditingValue(
      text: t.replaceRange(at, sel.isValid ? sel.end : at, ins),
      selection: TextSelection.collapsed(offset: at + ins.length),
    );
    setState(() {});
  }

  String _preview() => _text.text
      .replaceAll('{value}', '2,000')
      .replaceAll('{capital}', '\$100,000')
      .replaceAll('{partner}', 'خالد العولقي')
      .replaceAll('{currency}', 'دولار أمريكي');

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<ContractState>();
    final versions = cs.clauseVersions.where((c) => c.questionId == widget.questionId).toList()
      ..sort((a, b) => b.version.compareTo(a.version));
    final latest = versions.first;
    final fmt = DateFormat('yyyy/MM/dd HH:mm');
    final changed = _title.text.trim() != latest.title || _text.text.trim() != latest.text;

    return Scaffold(
      appBar: AppBar(title: Text('البند ${latest.id}')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            TextField(
              controller: _title,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'عنوان البند'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              onChanged: (_) => setState(() {}),
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(labelText: 'نص البند القانوني', alignLabelWithHint: true),
            ),
            const SizedBox(height: 8),
            const Text('إدراج متغير:', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final e in _vars.entries)
                ActionChip(avatar: const Icon(Icons.add_rounded, size: 16), label: Text(e.value), onPressed: () => _insert(e.key)),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.navySurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('معاينة بقيم نموذجية', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 12.5)),
                const SizedBox(height: 6),
                Text(_preview(), style: const TextStyle(color: AppColors.textPrimary, height: 1.8)),
              ]),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: changed
                      ? () {
                          cs.saveClauseDraft(widget.questionId, title: _title.text.trim(), text: _text.text.trim());
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حُفظت المسودة')));
                        }
                      : null,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('حفظ كمسودة'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: latest.status == ConfigStatus.draft && !changed ? () => _publish(context, cs) : null,
                  icon: const Icon(Icons.publish_rounded),
                  label: const Text('نشر الإصدار'),
                ),
              ),
            ]),
            if (changed)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('احفظ التعديلات كمسودة أولاً، ثم انشرها.', style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
              ),
            const SizedBox(height: 22),
            const Text('سجل الإصدارات', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ...versions.map((v) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 15,
                    backgroundColor: v.status.color.withValues(alpha: 0.15),
                    child: Text('${v.version}', style: TextStyle(color: v.status.color, fontSize: 12)),
                  ),
                  title: Text(v.title),
                  subtitle: Text('${v.status.label} · ${fmt.format(v.updatedAt)}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _publish(BuildContext context, ContractState cs) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('نشر الإصدار الجديد؟'),
        content: const Text(
          'يسري الإصدار على جلسات التأسيس الجديدة فقط. الجلسات القائمة والعقود الموقّعة تحتفظ بالنص الذي اعتُمدت عليه.',
          style: TextStyle(height: 1.7),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('نشر')),
        ],
      ),
    );
    if (ok == true) {
      cs.publishClause(widget.questionId);
      setState(() {});
    }
  }
}
