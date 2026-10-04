import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/company.dart';
import '../../models/professional.dart';
import '../../providers/company_state.dart';
import '../../providers/professional_state.dart';
import '../../services/identity_service.dart';
import '../../theme/app_theme.dart';
import 'pro_common.dart';

/// R01: دخول الطرف المهني. بعد التحقق برقم الجوال تُعرض الدعوة: الشركة والدور والنطاق والمدة،
/// فيقبلها أو يعتذر ويُسجَّل رده. الوصول محدود ولا يمنح حق تصويت أو ملكية.
class ProfessionalGate extends StatelessWidget {
  final Widget child;
  const ProfessionalGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final me = cs.me;
    final isPro = me != null && !me.isPartner && me.roles.any((r) => r == CompanyRole.lawyer || r == CompanyRole.accountant);
    if (!isPro) return child;
    final e = myEngagement(context);
    final pro = context.watch<ProfessionalState>();
    final status = e?.statusAt(pro.now());
    if (e == null) {
      return const Scaffold(
        body: StateView.empty(
          icon: Icons.hourglass_empty_rounded,
          title: 'لم يُفعَّل تكليفك بعد',
          message: 'أُضيف رقمك إلى الشركة، وسيظهر تكليفك هنا عندما يحدد الشريك المدير نطاقه ومدته.',
        ),
      );
    }
    if (status == EngagementStatus.pending) return InvitationScreen(engagementId: e.id);
    if (status != EngagementStatus.active) {
      return Scaffold(
        body: StateView.denied(
          message: status == EngagementStatus.expired
              ? 'انتهت مدة تكليفك في ${cs.current?.legalName}. يبقى سجل مراجعاتك محفوظاً، ويمكن للشركة تجديد التكليف.'
              : status == EngagementStatus.declined
                  ? 'اعتذرت عن هذا التكليف، وسُجّل ردك.'
                  : 'أُنهي تكليفك في هذه الشركة، وأُغلق الوصول.',
        ),
      );
    }
    return child;
  }
}

class InvitationScreen extends StatelessWidget {
  final String engagementId;
  const InvitationScreen({super.key, required this.engagementId});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final pro = context.watch<ProfessionalState>();
    final c = cs.current;
    final e = c == null ? null : pro.engagement(engagementId, c.id);
    if (c == null || e == null) return const Scaffold(body: StateView.empty(title: 'الدعوة غير متاحة', message: ''));
    return Scaffold(
      appBar: AppBar(title: const Text('دعوة تكليف مهني')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            GovCard(
              title: '${c.legalName} تدعوك بصفتك ${e.role.label}',
              icon: Icons.mark_email_unread_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('النطاق: ${e.scope.map((s) => s.label).join('، ')}', style: const TextStyle(height: 1.7)),
                Text('المدة: من ${_d(e.start)} إلى ${_d(e.end)}', style: const TextStyle(height: 1.7)),
                if (e.organization.isNotEmpty) Text('الجهة: ${e.organization}', style: const TextStyle(height: 1.7)),
                const SizedBox(height: 8),
                const Text(
                  'تشمل صلاحيتك الاطلاع على ما يدخل في النطاق والتعليق عليه فقط. لا تمنحك حق تصويت ولا ملكية، '
                  'وتعليقاتك تُحفظ أدلةً ولا تغيّر نص العقد.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.6),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                final m = await IdentityService.confirm(context, partnerName: e.name, action: 'قبول تكليف ${e.role.label}');
                if (m != null) pro.respond(c, e, accept: true);
              },
              icon: const Icon(Icons.check_rounded),
              label: const Text('قبول التكليف'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _decline(context, pro, e),
              icon: const Icon(Icons.close_rounded),
              label: const Text('الاعتذار'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _decline(BuildContext context, ProfessionalState pro, Engagement e) async {
    final c = context.read<CompanyState>().current!;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navySurface,
        title: const Text('الاعتذار عن التكليف'),
        content: TextField(controller: reason, decoration: const InputDecoration(labelText: 'السبب (اختياري)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد الاعتذار')),
        ],
      ),
    );
    if (ok == true) pro.respond(c, e, accept: false, reason: reason.text);
    reason.dispose();
  }

  static String _d(DateTime d) => '${d.year}/${d.month}/${d.day}';
}
