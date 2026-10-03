import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/gov_status.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/company.dart';
import '../../models/dispute.dart';
import '../../providers/company_state.dart';
import '../../providers/dispute_state.dart';
import '../../services/identity_service.dart';
import '../../theme/app_theme.dart';
import 'dispute_detail_screen.dart';

final _d = DateFormat('yyyy/MM/dd');

/// الخطوة التالية في التذكرة بلغة واضحة
String nextAction(Company c, Dispute d) {
  String name(String id) => c.members.where((m) => m.id == id).firstOrNull?.name ?? id;
  if (d.status == DisputeStatus.closed) return 'مغلقة · للقراءة فقط';
  if (d.status == DisputeStatus.resolved) {
    return d.needsAmendment ? 'إنشاء الإصدار الجديد للعقد لتنفيذ الحسم' : 'تنفيذ النتيجة ثم إغلاق التذكرة';
  }
  return switch (d.stage) {
    DisputeStage.negotiation || DisputeStage.mediation => d.settlement != null
        ? 'بانتظار موافقة الأطراف على محضر الصلح (${d.settlement!.approvals.length} من ${d.parties.length})'
        : 'ردود الأطراف وأدلتهم، أو اقتراح محضر صلح',
    DisputeStage.deadlockBreak => d.buyOut != null && !d.buyOut!.decided
        ? 'بانتظار اختيار ${name(d.buyOut!.targetId)}: البيع أو الشراء'
        : 'تقديم عرض شراء مغلق وملزم',
    DisputeStage.arbitration => d.caseFileHash == null ? 'تصدير ملف القضية لمركز التحكيم' : 'بانتظار حكم التحكيم',
    DisputeStage.liquidation => 'جرد الأصول والديون ثم إغلاق التصفية',
  };
}

GovStatus disputeGov(Dispute d) => switch (d.status) {
      DisputeStatus.resolved => GovStatus.approved,
      DisputeStatus.closed => GovStatus.archived,
      DisputeStatus.awaitingParty => GovStatus.pending,
      _ => GovStatus.dispute,
    };

/// P18: قائمة تذاكر النزاع ومراحلها. التذكرة دائمة ولا تُلغى.
class DisputesScreen extends StatefulWidget {
  const DisputesScreen({super.key});

  @override
  State<DisputesScreen> createState() => _DisputesScreenState();
}

class _DisputesScreenState extends State<DisputesScreen> {
  int _tab = 0; // 0 مفتوحة، 1 محسومة ومغلقة، 2 الكل
  DisputeTrigger? _type;

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final ds = context.watch<DisputeState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final all = ds.disputesFor(c.id);
    final list = all
        .where((d) => _tab == 2 || (_tab == 0 ? d.isOpen : !d.isOpen))
        .where((d) => _type == null || d.trigger == _type)
        .toList();
    final isPartner = cs.me?.isPartner ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('النزاعات')),
      floatingActionButton: isPartner
          ? FloatingActionButton.extended(
              onPressed: () => _openNew(context, c),
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.navyDark,
              icon: const Icon(Icons.add_rounded),
              label: const Text('فتح نزاع'),
            )
          : null,
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
          children: [
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text('مفتوحة (${all.where((d) => d.isOpen).length})')),
                ButtonSegment(value: 1, label: Text('محسومة (${all.where((d) => !d.isOpen).length})')),
                const ButtonSegment(value: 2, label: Text('الكل')),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                ChoiceChip(label: const Text('كل الأنواع'), selected: _type == null, onSelected: (_) => setState(() => _type = null)),
                for (final t in DisputeTrigger.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: ChoiceChip(
                      avatar: Icon(t.icon, size: 15),
                      label: Text(t.label),
                      selected: _type == t,
                      onSelected: (_) => setState(() => _type = t),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            if (list.isEmpty)
              StateView.empty(
                icon: Icons.gavel_rounded,
                title: _tab == 0 ? 'لا توجد نزاعات مفتوحة' : 'لا توجد تذاكر هنا',
                message: 'تُفتح التذكرة آلياً عند جمود التصويت أو تصعيد مخالفة، أو يفتحها شريك يدوياً لخلاف أو طلب تخارج.',
              ),
            for (final d in list) _DisputeCard(c: c, d: d),
          ],
        ),
      ),
    );
  }

  Future<void> _openNew(BuildContext context, Company c) async {
    final cs = context.read<CompanyState>();
    final ds = context.read<DisputeState>();
    final issue = TextEditingController();
    var trigger = DisputeTrigger.other;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.navySurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('فتح تذكرة نزاع',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text(
              'التذكرة لا تُلغى بعد فتحها، وتُقفل تعديلات العقد وجدول الحصص مؤقتاً، ويصل إشعار قانوني لكل الشركاء.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.6),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<DisputeTrigger>(
              initialValue: trigger,
              dropdownColor: AppColors.navySurface,
              decoration: const InputDecoration(labelText: 'نوع النزاع'),
              items: [
                for (final t in [DisputeTrigger.other, DisputeTrigger.exitRequest, DisputeTrigger.losses, DisputeTrigger.violation])
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (v) => set(() => trigger = v!),
            ),
            const SizedBox(height: 10),
            TextField(
                controller: issue,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'موضوع النزاع بوضوح', alignLabelWithHint: true)),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: () {
                if (issue.text.trim().length >= 5) Navigator.pop(ctx, true);
              },
              child: const Text('فتح التذكرة'),
            ),
          ]),
        ),
      ),
    );
    if (ok != true || !context.mounted) {
      issue.dispose();
      return;
    }
    final me = cs.me!;
    final m = await IdentityService.confirm(context, partnerName: me.name, action: 'فتح تذكرة نزاع: ${trigger.label}');
    if (m != null && context.mounted) {
      final d = ds.open(c, trigger: trigger, issue: issue.text, openedBy: me.id, openedByName: me.name);
      Navigator.push(context, MaterialPageRoute(builder: (_) => DisputeDetailScreen(disputeId: d.id)));
    }
    issue.dispose();
  }
}

class _DisputeCard extends StatelessWidget {
  final Company c;
  final Dispute d;
  const _DisputeCard({required this.c, required this.d});

  @override
  Widget build(BuildContext context) {
    final left = d.deadline.difference(DateTime.now());
    final urgent = d.isOpen && d.stage.index < DisputeStage.arbitration.index && left.inDays < 3;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.navySurface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: d.isOpen ? d.status.color.withValues(alpha: 0.5) : AppColors.divider),
        ),
        child: InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DisputeDetailScreen(disputeId: d.id))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(d.trigger.icon, color: AppColors.gold, size: 20),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(d.trigger.label,
                        style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800))),
                StatusBadge(disputeGov(d), overrideLabel: d.status.label, dense: true),
              ]),
              const SizedBox(height: 6),
              Text(d.issue, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 4, children: [
                Text('المرحلة: ${d.stage.label}', style: const TextStyle(color: AppColors.gold, fontSize: 12)),
                Text('فُتحت ${_d.format(d.openedAt)}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                if (d.isOpen && d.stage.index < DisputeStage.arbitration.index)
                  Text(
                    'المهلة ${_d.format(d.deadline)} (${left.isNegative ? 'انقضت' : 'باقٍ ${left.inDays} يوماً'})',
                    style: TextStyle(color: urgent ? AppColors.danger : AppColors.textMuted, fontSize: 12, fontWeight: urgent ? FontWeight.w800 : FontWeight.w400),
                  ),
              ]),
              const SizedBox(height: 6),
              Text('التالي: ${nextAction(c, d)}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }
}
