import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/company.dart';
import '../../models/family.dart';
import '../../providers/company_state.dart';
import '../../providers/family_state.dart';
import '../../theme/app_theme.dart';
import 'family_decisions_screen.dart';

final _d = DateFormat('yyyy/MM/dd');

/// R11: شجرة العائلة والورثة. الأفراد بأجيالهم وصلاتهم وصفاتهم في الخلافة، ووثائق حصر الوراثة.
/// الأنصبة تُدخل كما وردت في الوثيقة الرسمية ولا يحسبها التطبيق. البيانات مقيدة بأفراد العائلة المخوّلين.
class FamilyTreeScreen extends StatefulWidget {
  const FamilyTreeScreen({super.key});

  @override
  State<FamilyTreeScreen> createState() => _FamilyTreeScreenState();
}

class _FamilyTreeScreenState extends State<FamilyTreeScreen> {
  int? _gen;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final f = context.watch<FamilyState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) context.read<FamilyState>().seedFounders(c);
    });
    final all = f.peopleFor(c.id);
    final gens = all.map((p) => p.generation).toSet().toList()..sort();
    final list = all.where((p) => (_gen == null || p.generation == _gen) && (_q.isEmpty || p.name.contains(_q))).toList();
    final founder = cs.me?.isPartner ?? false;
    final deeds = f.deedsFor(c.id);

    return Scaffold(
      appBar: AppBar(title: const Text('العائلة والورثة')),
      floatingActionButton: founder
          ? FloatingActionButton.extended(
              onPressed: () => _editPerson(context, c, null),
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.navyDark,
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('فرد'),
            )
          : null,
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
          children: [
            StateBanner.readOnly('بيانات عائلية مقيدة بالشركاء المؤسسين وأفراد العائلة المخوّلين، ولا تظهر لمستخدمي الشركة الآخرين.'),
            TextField(
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), labelText: 'بحث بالاسم', isDense: true),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('كل الأجيال'), selected: _gen == null, onSelected: (_) => setState(() => _gen = null)),
              for (final g in gens) ChoiceChip(label: Text('الجيل $g'), selected: _gen == g, onSelected: (_) => setState(() => _gen = g)),
            ]),
            const SizedBox(height: 10),
            for (final g in gens.where((g) => _gen == null || g == _gen)) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 6),
                child: Text('الجيل $g', style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800)),
              ),
              for (final p in list.where((p) => p.generation == g))
                Card(
                  margin: EdgeInsetsDirectional.only(bottom: 8, start: (g - 1) * 14.0),
                  child: ListTile(
                    onTap: founder ? () => _editPerson(context, c, p) : null,
                    leading: CircleAvatar(
                      backgroundColor: p.alive ? AppColors.navyLight : AppColors.divider,
                      child: Icon(p.alive ? Icons.person_rounded : Icons.person_off_rounded, color: AppColors.gold, size: 20),
                    ),
                    title: Text('${p.name}${p.alive ? '' : ' (متوفى)'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '${p.relation}${p.parentId == null ? '' : ' · من ${f.person(p.parentId!)?.name ?? ''}'} · ${p.role.label}'
                      '${p.memberId == null ? '' : ' · مستخدم في التطبيق'}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 14),
            GovCard(
              title: 'وثائق حصر الوراثة',
              icon: Icons.gavel_rounded,
              trailing: founder
                  ? TextButton(onPressed: () => _deed(context, c), child: const Text('إدخال وثيقة'))
                  : null,
              child: deeds.isEmpty
                  ? const Text('لا توجد وثائق. تُدخل الأنصبة كما وردت في حصر الوراثة الصادر من المحكمة، ثم يعتمدها قرار عائلي.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.6))
                  : Column(children: [
                      for (final d in deeds)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${f.person(d.deceasedId)?.name ?? ''} · ${d.reference}'),
                          subtitle: Text(
                            '${d.court} · ${_d.format(d.date)} · ${d.status.label}\n'
                            '${d.shares.entries.map((e) => '${f.person(e.key)?.name ?? e.key} ${e.value.toStringAsFixed(2)}%').join('، ')}',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.5),
                          ),
                          onTap: d.decisionRef == null
                              ? null
                              : () => Navigator.push(context, MaterialPageRoute(builder: (_) => FamilyDecisionScreen(decisionId: d.decisionRef!))),
                        ),
                    ]),
            ),
            if (founder) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _invite(context, c),
                icon: const Icon(Icons.phone_iphone_rounded),
                label: const Text('دعوة فرد من العائلة إلى التطبيق'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _editPerson(BuildContext context, Company c, FamilyPerson? p) async {
    final f = context.read<FamilyState>();
    final name = TextEditingController(text: p?.name ?? '');
    final relation = TextEditingController(text: p?.relation ?? '');
    final notes = TextEditingController(text: p?.notes ?? '');
    String? parent = p?.parentId;
    var alive = p?.alive ?? true;
    var role = p?.role ?? SuccessionRole.member;
    String? member = p?.memberId;
    final people = f.peopleFor(c.id).where((x) => x.id != p?.id).toList();
    final members = c.members.where((m) => m.isPartner || m.roles.contains(CompanyRole.familyMember)).toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: AppColors.navySurface,
          title: Text(p == null ? 'فرد جديد' : p.name),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم الكامل')),
              TextField(controller: relation, decoration: const InputDecoration(labelText: 'صلة القرابة (ابن، بنت، زوجة...)')),
              DropdownButtonFormField<String?>(
                initialValue: parent,
                isExpanded: true,
                dropdownColor: AppColors.navySurface,
                decoration: const InputDecoration(labelText: 'الأصل في الشجرة'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('بدون (الجيل الأول)')),
                  for (final x in people) DropdownMenuItem(value: x.id, child: Text(x.name)),
                ],
                onChanged: (v) => set(() => parent = v),
              ),
              DropdownButtonFormField<SuccessionRole>(
                initialValue: role,
                dropdownColor: AppColors.navySurface,
                decoration: const InputDecoration(labelText: 'الصفة في الخلافة'),
                items: [for (final r in SuccessionRole.values) DropdownMenuItem(value: r, child: Text(r.label))],
                onChanged: (v) => set(() => role = v!),
              ),
              DropdownButtonFormField<String?>(
                initialValue: members.any((m) => m.id == member) ? member : null,
                isExpanded: true,
                dropdownColor: AppColors.navySurface,
                decoration: const InputDecoration(labelText: 'حسابه في التطبيق'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('لا يستخدم التطبيق')),
                  for (final m in members) DropdownMenuItem(value: m.id, child: Text(m.name)),
                ],
                onChanged: (v) => set(() => member = v),
              ),
              SwitchListTile(value: alive, onChanged: (v) => set(() => alive = v), title: const Text('على قيد الحياة'), contentPadding: EdgeInsets.zero),
              TextField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      final gen = parent == null ? 1 : (f.person(parent!)?.generation ?? 0) + 1;
      final x = p ?? FamilyPerson(id: 'FP${DateTime.now().microsecondsSinceEpoch}', companyId: c.id, name: '', relation: '');
      x
        ..name = name.text.trim()
        ..relation = relation.text.trim()
        ..parentId = parent
        ..generation = gen
        ..alive = alive
        ..role = role
        ..memberId = member
        ..notes = notes.text.trim();
      f.savePerson(c, x);
    }
    for (final y in [name, relation, notes]) {
      y.dispose();
    }
  }

  Future<void> _deed(BuildContext context, Company c) async {
    final f = context.read<FamilyState>();
    final cs = context.read<CompanyState>();
    final ref = TextEditingController();
    final court = TextEditingController();
    final people = f.peopleFor(c.id);
    String? deceased = people.where((p) => !p.alive).firstOrNull?.id ?? people.firstOrNull?.id;
    final shares = {for (final p in people) p.id: TextEditingController()};
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: AppColors.navySurface,
          title: const Text('وثيقة حصر الوراثة'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: deceased,
                isExpanded: true,
                dropdownColor: AppColors.navySurface,
                decoration: const InputDecoration(labelText: 'المورِّث'),
                items: [for (final p in people) DropdownMenuItem(value: p.id, child: Text(p.name))],
                onChanged: (v) => set(() => deceased = v),
              ),
              TextField(controller: ref, decoration: const InputDecoration(labelText: 'رقم الوثيقة')),
              TextField(controller: court, decoration: const InputDecoration(labelText: 'المحكمة المصدرة')),
              const SizedBox(height: 8),
              const Text('الأنصبة كما وردت في الوثيقة (بالمئة من التركة):', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              for (final p in people.where((p) => p.id != deceased))
                TextField(
                  controller: shares[p.id],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: p.name, suffixText: '%', isDense: true),
                ),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: AppColors.danger))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                if (deceased == null) return;
                final err = f.submitDeed(
                    c,
                    InheritanceDeed(
                      id: 'DD${DateTime.now().microsecondsSinceEpoch}',
                      companyId: c.id,
                      deceasedId: deceased!,
                      reference: ref.text.trim(),
                      court: court.text.trim(),
                      date: DateTime.now(),
                      shares: {
                        for (final e in shares.entries)
                          if (e.key != deceased && (double.tryParse(e.value.text) ?? 0) > 0) e.key: double.parse(e.value.text),
                      },
                    ),
                    by: cs.me!.id);
                if (err != null) return set(() => error = err);
                Navigator.pop(ctx);
              },
              child: const Text('رفع للاعتماد العائلي'),
            ),
          ],
        ),
      ),
    );
    ref.dispose();
    court.dispose();
    for (final x in shares.values) {
      x.dispose();
    }
  }

  Future<void> _invite(BuildContext context, Company c) async {
    final cs = context.read<CompanyState>();
    final name = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navySurface,
        title: const Text('دعوة فرد من العائلة'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
          TextField(controller: phone, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'رقم الجوال')),
          const SizedBox(height: 8),
          const Text('يرى الحوكمة العائلية فقط، دون حصص أو صلاحيات في الشركة.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('دعوة')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      final err = cs.inviteStaff(c.id, name: name.text, phone: phone.text, role: CompanyRole.familyMember);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'أُضيف ${name.text.trim()}، ويدخل برقم جواله.')));
    }
    name.dispose();
    phone.dispose();
  }
}
