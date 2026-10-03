import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/gov_status.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/admin.dart';
import '../../models/company.dart';
import '../../providers/company_state.dart';
import '../../theme/app_theme.dart';
import 'roles_screen.dart';

final _dt = DateFormat('yyyy/MM/dd HH:mm');

/// الأدوار التي تمنحها الإدارة بالدعوة (الشريك يُضاف بإصدار عقد فقط)
const kInvitableRoles = [
  CompanyRole.executiveManager,
  CompanyRole.financialManager,
  CompanyRole.departmentManager,
  CompanyRole.accountant,
  CompanyRole.lawyer,
  CompanyRole.legalAdmin,
  CompanyRole.systemAdmin,
];

/// A03: مستخدمو النظام. دعوة موظفين بلا حصص، وتغيير أدوارهم، وإيقافهم دون حذف سجلهم.
/// الدور التقني لا يمنح سلطة تجارية، وحقوق الشريك لا تتغير من هنا.
class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final canEdit = cs.canDo(AppModule.users, PermAction.configure);

    return Scaffold(
      appBar: AppBar(title: const Text('مستخدمو النظام')),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _invite(context, c),
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.navyDark,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('دعوة مستخدم'),
            )
          : null,
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
          children: [
            const StateBanner(
              color: AppColors.info,
              icon: Icons.info_outline_rounded,
              text: 'الشركاء وحصصهم جزء من العقد ولا يتغيرون إلا بإصدار جديد. هنا تُدار حسابات الموظفين والأطراف المهنية فقط، '
                  'والموقوف يفقد الوصول فوراً مع بقاء سجله.',
            ),
            _section('الشركاء (${c.partners.length})'),
            for (final m in c.partners) _UserTile(c: c, m: m, editable: false),
            const SizedBox(height: 12),
            _section('الموظفون والأطراف المدعوون (${c.staffMembers.length})'),
            if (c.staffMembers.isEmpty)
              const StateView.empty(
                icon: Icons.group_add_rounded,
                title: 'لا يوجد موظفون بعد',
                message: 'ادعُ المدير التنفيذي أو المالي أو المحاسب برقم جواله. يدخل برمز التحقق ويرى وحدات دوره فقط.',
              ),
            for (final m in c.staffMembers) _UserTile(c: c, m: m, editable: canEdit),
          ],
        ),
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(t, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
      );

  Future<void> _invite(BuildContext context, Company c) async {
    final cs = context.read<CompanyState>();
    final name = TextEditingController();
    final phone = TextEditingController();
    var role = CompanyRole.executiveManager;
    String? error;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.navySurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('دعوة مستخدم', style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم الكامل')),
            const SizedBox(height: 10),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'رقم الجوال', hintText: '77xxxxxxx أو 9665xxxxxxxx'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<CompanyRole>(
              initialValue: role,
              isExpanded: true,
              dropdownColor: AppColors.navySurface,
              decoration: const InputDecoration(labelText: 'الدور'),
              items: [for (final r in kInvitableRoles) DropdownMenuItem(value: r, child: Text('${r.label} · ${r.portal.label}'))],
              onChanged: (v) => set(() => role = v!),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: const TextStyle(color: AppColors.danger)),
              ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: () {
                final e = cs.inviteStaff(c.id, name: name.text, phone: phone.text, role: role);
                if (e != null) return set(() => error = e);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('أُضيف ${name.text.trim()}. يدخل برقم جواله ورمز التحقق، ويرى وحدات دور ${role.label} فقط.')));
              },
              child: const Text('إرسال الدعوة'),
            ),
          ]),
        ),
      ),
    );
    name.dispose();
    phone.dispose();
  }
}

class _UserTile extends StatelessWidget {
  final Company c;
  final CompanyMember m;
  final bool editable;
  const _UserTile({required this.c, required this.m, required this.editable});

  @override
  Widget build(BuildContext context) {
    final cs = context.read<CompanyState>();
    final seen = DateTime.tryParse(c.lastSeen[m.id] ?? '');
    final (gs, label) = !m.active
        ? (GovStatus.archived, 'موقوف')
        : seen == null
            ? (GovStatus.pending, 'دعوة معلّقة')
            : (GovStatus.approved, 'نشط');
    final phoneVisible = !m.isPartner || cs.canSee('partner.phone');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.navyLight,
          child: Text(m.name.isEmpty ? '؟' : m.name.characters.first, style: const TextStyle(color: AppColors.gold)),
        ),
        title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${m.roles.map((r) => r.label).join('، ')}'
          '${m.isPartner ? ' · ${m.equity.toStringAsFixed(2)}%' : ''}\n'
          '${phoneVisible ? m.phone : 'الجوال محجوب حسب نقاط الإفصاح'} · '
          '${seen == null ? 'لم يدخل بعد' : 'آخر دخول ${_dt.format(seen.toLocal())}'}',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.6),
        ),
        isThreeLine: true,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          StatusBadge(gs, overrideLabel: label, dense: true),
          if (editable)
            PopupMenuButton<String>(
              color: AppColors.navySurface,
              onSelected: (v) {
                final err = switch (v) {
                  'suspend' => cs.updateStaff(c.id, m.id, status: MemberStatus.suspended),
                  'activate' => cs.updateStaff(c.id, m.id, status: MemberStatus.active),
                  'perm' => () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => RolesScreen(initialRole: m.roles.first)));
                      return null;
                    }(),
                  _ => cs.updateStaff(c.id, m.id, role: CompanyRole.values.byName(v)),
                };
                if (err != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
              },
              itemBuilder: (_) => [
                for (final r in kInvitableRoles.where((r) => !m.roles.contains(r)))
                  PopupMenuItem(value: r.name, child: Text('تغيير الدور إلى ${r.label}')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'perm', child: Text('صلاحيات هذا الدور')),
                m.active
                    ? const PopupMenuItem(value: 'suspend', child: Text('إيقاف الوصول'))
                    : const PopupMenuItem(value: 'activate', child: Text('إعادة التفعيل')),
              ],
            ),
        ]),
      ),
    );
  }
}
