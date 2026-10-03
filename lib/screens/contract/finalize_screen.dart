import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/questionnaire.dart';
import '../../providers/contract_state.dart';
import '../../services/contract_pdf.dart';
import '../../services/identity_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/signature_pad.dart';

/// الحد الأدنى للشهود على العقد
const int kMinWitnesses = 2;

/// التوثيق النهائي: إقرار الأهلية وتوقيع كل شريك، ثم الشهود، ثم توليد العقد PDF
class FinalizeScreen extends StatelessWidget {
  final String sessionId;
  const FinalizeScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ContractState>();
    final s = state.sessions.where((x) => x.id == sessionId).firstOrNull;
    if (s == null) return const Scaffold();
    final signed = s.partners.where((p) => s.signOffs.containsKey(p.id)).length;
    final allSigned = signed == s.partners.length;
    final witnessesOk = s.witnesses.length >= kMinWitnesses;
    final completed = s.status == SessionStatus.completed;

    return Scaffold(
      appBar: AppBar(title: const Text('التوقيع وتوليد العقد')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        children: [
          _Step(
            n: 1,
            title: 'إقرار الأهلية وتوقيع الشركاء',
            subtitle: '$signed من ${s.partners.length} وقّعوا',
            done: allSigned,
          ),
          const SizedBox(height: 10),
          ...s.partners.map((p) {
            final so = s.signOffs[p.id];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.navySurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: so != null ? AppColors.success.withValues(alpha: 0.5) : AppColors.divider),
              ),
              child: Row(
                children: [
                  Icon(so != null ? Icons.verified_rounded : Icons.draw_outlined,
                      color: so != null ? AppColors.success : AppColors.textMuted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name,
                            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                        Text(
                          so == null
                              ? 'الحصة ${p.equity.toStringAsFixed(0)}% · لم يوقّع بعد'
                              : 'وقّع ${DateFormat('d/M/yyyy HH:mm').format(so.at)} · ${so.method.label}',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  if (so == null && !completed && state.canActAs(p))
                    TextButton(
                      onPressed: () => _signPartner(context, s, p),
                      child: const Text('توقيع'),
                    )
                  else if (so == null && !completed)
                    const Text('يوقّع من جواله',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                ],
              ),
            );
          }),
          const SizedBox(height: 18),
          _Step(
            n: 2,
            title: 'الشهود',
            subtitle: 'الحد الأدنى $kMinWitnesses · المضاف ${s.witnesses.length}',
            done: witnessesOk,
          ),
          const SizedBox(height: 10),
          ...s.witnesses.asMap().entries.map((e) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.navySurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_pin_rounded, color: AppColors.gold),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.value.name,
                              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                          Text(
                            '${e.value.internal ? 'من داخل الشركة' : 'من خارج الشركة'} · هوية ${e.value.nationalId}',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                    if (!completed)
                      IconButton(
                        onPressed: () {
                          final list = [...s.witnesses]..removeAt(e.key);
                          state.setWitnesses(s, list);
                        },
                        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                      ),
                  ],
                ),
              )),
          if (!completed)
            OutlinedButton.icon(
              onPressed: () => _addWitness(context, s),
              icon: const Icon(Icons.person_add_alt_rounded),
              label: const Text('إضافة شاهد'),
            ),
          const SizedBox(height: 22),
          _Step(
            n: 3,
            title: 'توليد العقد النهائي',
            subtitle: 'ملف PDF يضم البنود والتواقيع والطوابع الزمنية',
            done: completed,
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: (allSigned && witnessesOk) || completed
                ? () async {
                    if (!completed) state.complete(s);
                    await ContractPdf.share(state, s, interim: false);
                  }
                : null,
            icon: const Icon(Icons.picture_as_pdf_rounded),
            label: Text(completed ? 'عرض العقد النهائي' : 'اعتماد وتوليد العقد'),
          ),
          if (!allSigned || !witnessesOk)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('يتفعّل التوليد بعد توقيع جميع الشركاء وإضافة الشهود',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
            ),
        ],
      ),
    );
  }

  Future<void> _signPartner(BuildContext context, ContractSession s, SessionPartner p) async {
    final state = context.read<ContractState>();
    final padKey = GlobalKey<SignaturePadState>();
    var declared = false;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.navySurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('توقيع ${p.name}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: declared,
                onChanged: (v) => setSheet(() => declared = v ?? false),
                activeColor: AppColors.gold,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'أقر بأنني كامل الأهلية القانونية، وأن موافقتي على جميع بنود هذا العقد تمت بإرادتي الحرة ودون إكراه.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.6),
                ),
              ),
              const SizedBox(height: 8),
              SignaturePad(key: padKey),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => padKey.currentState?.clear(),
                  child: const Text('مسح التوقيع'),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final pad = padKey.currentState;
                  if (!declared || pad == null || pad.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('يلزم إقرار الأهلية والتوقيع')));
                    return;
                  }
                  final png = await pad.exportBase64();
                  if (!ctx.mounted || png == null) return;
                  final m = await IdentityService.confirm(ctx,
                      partnerName: p.name, action: 'التوقيع النهائي على العقد');
                  if (m == null) return;
                  state.signOff(s, PartnerSignOff(partnerId: p.id, signaturePng: png, at: DateTime.now(), method: m));
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                icon: const Icon(Icons.fingerprint_rounded),
                label: const Text('تأكيد بالبصمة واعتماد التوقيع'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addWitness(BuildContext context, ContractSession s) async {
    final state = context.read<ContractState>();
    final name = TextEditingController();
    final nid = TextEditingController();
    final padKey = GlobalKey<SignaturePadState>();
    var internal = false;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.navySurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('إضافة شاهد',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الشاهد', isDense: true)),
                const SizedBox(height: 10),
                TextField(controller: nid, decoration: const InputDecoration(labelText: 'رقم الهوية', isDense: true)),
                SwitchListTile(
                  value: internal,
                  onChanged: (v) => setSheet(() => internal = v),
                  activeThumbColor: AppColors.gold,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('من داخل الشركة', style: TextStyle(color: AppColors.textSecondary)),
                ),
                SignaturePad(key: padKey, height: 150),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () async {
                    final pad = padKey.currentState;
                    if (name.text.trim().isEmpty || nid.text.trim().isEmpty || pad == null || pad.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('أكمل بيانات الشاهد وتوقيعه')));
                      return;
                    }
                    final png = await pad.exportBase64();
                    state.setWitnesses(s, [
                      ...s.witnesses,
                      Witness(name: name.text.trim(), nationalId: nid.text.trim(), internal: internal, signaturePng: png),
                    ]);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('حفظ الشاهد'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    name.dispose();
    nid.dispose();
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String title;
  final String subtitle;
  final bool done;
  const _Step({required this.n, required this.title, required this.subtitle, required this.done});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: done ? null : AppColors.goldGradient,
            color: done ? AppColors.success : null,
          ),
          child: done
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
              : Text('$n', style: const TextStyle(color: AppColors.navyDark, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
              Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
            ],
          ),
        ),
        if (done) const StatusChip(label: 'مكتمل', color: AppColors.success, icon: Icons.check_rounded),
      ],
    );
  }
}
