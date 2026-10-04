import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/company.dart';
import '../../models/professional.dart';
import '../../models/questionnaire.dart';
import '../../providers/company_state.dart';
import '../../providers/professional_state.dart';
import '../../services/identity_service.dart';
import '../../services/phone.dart';
import '../../theme/app_theme.dart';
import 'pro_comments_screen.dart';
import 'pro_dashboard_screen.dart';

/// من جهة الشركة: المراجعات المهنية. يكلّف الشريك المدير أو مسؤول النظام المحامي والمحاسب
/// بنطاق ومدة، ويرى كل الشركاء التعليقات ويردّون عليها. إنهاء التكليف بعد بدء العمل يحتاج موافقة الشركاء.
class ProfessionalReviewsScreen extends StatelessWidget {
  const ProfessionalReviewsScreen({super.key});

  static bool canAppoint(Set<CompanyRole> roles) =>
      roles.contains(CompanyRole.managingPartner) || roles.contains(CompanyRole.systemAdmin);

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final pro = context.watch<ProfessionalState>();
    final c = cs.current;
    final me = cs.me;
    if (c == null || me == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final list = pro.engagementsFor(c.id);
    final open = pro.commentsFor(c.id).where((x) => x.status.isOpen).length;
    final changeReq = pro.commentsFor(c.id).where((x) => x.kind == CommentKind.changeRequest && x.status.isOpen).length;

    return Scaffold(
      appBar: AppBar(title: const Text('المراجعات المهنية')),
      floatingActionButton: canAppoint(cs.myRoles)
          ? FloatingActionButton.extended(
              onPressed: () => _appoint(context, c),
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.navyDark,
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('تكليف محامٍ أو محاسب'),
            )
          : null,
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.forum_rounded, color: AppColors.gold),
                title: Text('التعليقات المهنية: $open مفتوحة${changeReq == 0 ? '' : ' · $changeReq طلبات تعديل'}'),
                subtitle: const Text('ردّوا على المحامي والمحاسب، وحوّلوا طلب التعديل إلى مقترح إصدار جديد عند الحاجة.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProCommentsScreen())),
              ),
            ),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const StateView.empty(
                icon: Icons.work_history_rounded,
                title: 'لا توجد تكليفات',
                message: 'كلّف محامياً لمراجعة صياغة العقد، أو محاسباً لمراجعة البنود المالية وحدودها. يدخل كل منهما برقم جواله.',
              ),
            for (final e in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: EngagementCard(
                  c: c,
                  e: e,
                  trailing: _actions(context, c, e, me, pro),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget? _actions(BuildContext context, Company c, Engagement e, CompanyMember me, ProfessionalState pro) {
    final st = e.statusAt(pro.now());
    if (st != EngagementStatus.active && st != EngagementStatus.pending) return null;
    final reviews = pro.reviewsFor(c.id).where((r) => r.engagementId == e.id).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (reviews.isNotEmpty)
        Text(reviews.map((r) => 'الإصدار ${r.version}: ${r.status.label}').join(' · '),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      if (e.terminationReason != null) ...[
        Text('موافقة الشركاء على الإنهاء: ${pro.approvalShare(c, e).toStringAsFixed(1)}% من الحصص (المطلوب أكثر من 50%)',
            style: const TextStyle(color: AppColors.warning, fontSize: 12)),
        if (me.isPartner && !e.terminationApprovals.containsKey(me.id))
          TextButton.icon(
            onPressed: () async {
              final m = await IdentityService.confirm(context, partnerName: me.name, action: 'الموافقة على إنهاء تكليف ${e.name}');
              if (m != null) pro.approveTermination(c, e, me, method: m.label);
            },
            icon: const Icon(Icons.fingerprint_rounded, size: 18),
            label: const Text('أوافق على الإنهاء'),
          ),
      ] else if (canAppoint(context.read<CompanyState>().myRoles))
        TextButton.icon(
          onPressed: () => _terminate(context, c, e, me),
          icon: const Icon(Icons.cancel_rounded, size: 18),
          label: Text(pro.workStarted(e) ? 'طلب إنهاء التكليف (يحتاج موافقة الشركاء)' : 'إلغاء التكليف'),
        ),
    ]);
  }

  Future<void> _terminate(BuildContext context, Company c, Engagement e, CompanyMember me) async {
    final t = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navySurface,
        title: Text('إنهاء تكليف ${e.name}'),
        content: TextField(controller: t, decoration: const InputDecoration(labelText: 'السبب')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('متابعة')),
        ],
      ),
    );
    if (ok == true && t.text.trim().isNotEmpty && context.mounted) {
      context.read<ProfessionalState>().requestTermination(c, e, reason: t.text, byId: me.id, byName: me.name);
    }
    t.dispose();
  }

  Future<void> _appoint(BuildContext context, Company c) async {
    final cs = context.read<CompanyState>();
    final pro = context.read<ProfessionalState>();
    final name = TextEditingController();
    final phone = TextEditingController();
    final org = TextEditingController();
    final contact = TextEditingController();
    var role = CompanyRole.lawyer;
    var months = 3;
    final scope = <EngagementScope>{EngagementScope.contract};
    String? error;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.navySurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('تكليف طرف مهني', style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              SegmentedButton<CompanyRole>(
                segments: const [
                  ButtonSegment(value: CompanyRole.lawyer, label: Text('محامٍ')),
                  ButtonSegment(value: CompanyRole.accountant, label: Text('محاسب')),
                ],
                selected: {role},
                onSelectionChanged: (s) => set(() {
                  role = s.first;
                  scope
                    ..clear()
                    ..add(role == CompanyRole.lawyer ? EngagementScope.contract : EngagementScope.financialRules);
                }),
              ),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
              TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'رقم الجوال (يدخل به برمز التحقق)')),
              TextField(controller: org, decoration: const InputDecoration(labelText: 'المكتب أو الجهة')),
              TextField(controller: contact, decoration: const InputDecoration(labelText: 'بريد أو هاتف المكتب (اختياري)')),
              const SizedBox(height: 10),
              const Text('النطاق', style: TextStyle(color: AppColors.textMuted)),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final s in EngagementScope.values)
                  FilterChip(
                    label: Text(s.label),
                    selected: scope.contains(s),
                    onSelected: (v) => set(() => v ? scope.add(s) : scope.remove(s)),
                  ),
              ]),
              DropdownButtonFormField<int>(
                initialValue: months,
                dropdownColor: AppColors.navySurface,
                decoration: const InputDecoration(labelText: 'مدة التكليف'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('شهر')),
                  DropdownMenuItem(value: 3, child: Text('3 أشهر')),
                  DropdownMenuItem(value: 6, child: Text('6 أشهر')),
                  DropdownMenuItem(value: 12, child: Text('سنة')),
                ],
                onChanged: (v) => set(() => months = v!),
              ),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: AppColors.danger))),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () {
                  // الطرف المدعو سابقاً بنفس الدور يُعاد تكليفه دون دعوة جديدة
                  final p = normalizePhone(phone.text);
                  var m = c.members.where((x) => x.phone == p).firstOrNull;
                  if (m == null) {
                    final inv = cs.inviteStaff(c.id, name: name.text, phone: phone.text, role: role);
                    if (inv != null) return set(() => error = inv);
                    m = c.members.where((x) => x.phone == p).firstOrNull;
                  }
                  if (m == null || !m.roles.contains(role)) return set(() => error = 'هذا الرقم عضو في الشركة بدور آخر');
                  final now = DateTime.now();
                  final err = pro.createEngagement(c, m,
                      scope: scope,
                      start: now,
                      end: DateTime(now.year, now.month + months, now.day),
                      organization: org.text,
                      contact: contact.text,
                      byName: cs.me?.name ?? '',
                      byId: cs.me?.id ?? '');
                  if (err != null) return set(() => error = err);
                  Navigator.pop(ctx);
                },
                child: const Text('إرسال الدعوة'),
              ),
            ]),
          ),
        ),
      ),
    );
    for (final x in [name, phone, org, contact]) {
      x.dispose();
    }
  }
}
