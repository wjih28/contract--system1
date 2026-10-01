import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/questionnaire.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../services/identity_service.dart';
import '../../services/phone.dart';
import '../../theme/app_theme.dart';
import '../../widgets/signature_pad.dart';
import '../establishment/final_contract_screen.dart';
import '../establishment/witness_attestation_screen.dart';

/// الحد الأدنى للشهود على العقد
const int kMinWitnesses = 2;

/// P12: التوقيع الإلكتروني والبصمة. كل توقيع مرتبط بإصدار المسودة المعروض وبصمته،
/// وأي تعديل لاحق على البنود يُبطل التواقيع ويتطلب توقيعاً جديداً.
class FinalizeScreen extends StatelessWidget {
  final String sessionId;
  const FinalizeScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<ContractState>();
    final s = st.sessions.where((x) => x.id == sessionId).firstOrNull;
    if (s == null) return const Scaffold(body: StateView.empty(title: 'الجلسة غير موجودة', message: ''));
    final hash = st.draftHash(s);
    final completed = s.status == SessionStatus.completed;
    final notReady = st.signingBlockers(s);
    final blockers = st.finalizeBlockers(s, minWitnesses: kMinWitnesses);
    final fmt = DateFormat('yyyy/MM/dd HH:mm');
    final validSigned = s.partners.where((p) {
      final so = s.signOffs[p.id];
      return so != null && st.signOffValid(s, so);
    }).length;
    final validWitnesses = s.witnesses.where((w) => st.witnessValid(s, w)).length;

    return Scaffold(
      appBar: AppBar(title: const Text('التوقيع والشهود')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            if (completed)
              StateBanner.readOnly('اعتُمد العقد نهائياً، والتوقيعات مقفلة.')
            else if (notReady.isNotEmpty)
              StateBanner(
                color: AppColors.warning,
                icon: Icons.block_rounded,
                text: 'لا يمكن التوقيع بعد: ${notReady.join('، ')}.',
              ),
            // الإصدار الذي يُوقَّع عليه
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.navySurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.fingerprint_rounded, color: AppColors.gold),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('الإصدار المعروض للتوقيع',
                            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
                        Row(children: [
                          const Text('مرجع سلامة المسودة: ',
                              style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                          Text('${hash.substring(0, 16)}…',
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _Step(n: 1, title: 'إقرار الأهلية وتوقيع الشركاء',
                subtitle: '$validSigned من ${s.partners.length} وقّعوا على هذا الإصدار', done: validSigned == s.partners.length),
            const SizedBox(height: 10),
            ...s.partners.map((p) {
              final so = s.signOffs[p.id];
              final valid = so != null && st.signOffValid(s, so);
              final invalidated = so != null && !valid;
              final canSign = !completed && notReady.isEmpty && !valid && st.canActAs(p);
              return _Row(
                icon: valid ? Icons.verified_rounded : (invalidated ? Icons.history_toggle_off_rounded : Icons.draw_outlined),
                color: valid ? AppColors.success : (invalidated ? AppColors.warning : AppColors.textMuted),
                title: p.name,
                subtitle: valid
                    ? 'وقّع ${fmt.format(so.at.toLocal())} · ${so.method.label}'
                    : invalidated
                        ? 'أُلغي توقيعه لأن العقد تغيّر بعد التوقيع، ويلزم توقيع جديد'
                        : 'الحصة ${p.equity.toStringAsFixed(p.equity % 1 == 0 ? 0 : 2)}% · لم يوقّع بعد',
                trailing: canSign
                    ? TextButton(onPressed: () => _signPartner(context, s, p), child: const Text('توقيع'))
                    : (!valid && !completed && !st.canActAs(p))
                        ? const Text('يوقّع من جواله', style: TextStyle(color: AppColors.textMuted, fontSize: 11.5))
                        : null,
              );
            }),
            const SizedBox(height: 18),
            _Step(n: 2, title: 'الشهود',
                subtitle: '$validWitnesses من $kMinWitnesses شهدوا على هذا الإصدار', done: validWitnesses >= kMinWitnesses),
            const SizedBox(height: 10),
            ...s.witnesses.asMap().entries.map((e) {
              final w = e.value;
              final valid = st.witnessValid(s, w);
              final canAttest = !completed && notReady.isEmpty && !valid && st.canAttestAs(w);
              return _Row(
                icon: valid ? Icons.verified_user_rounded : Icons.person_pin_rounded,
                color: valid ? AppColors.success : AppColors.gold,
                title: w.name,
                subtitle: [
                  w.internal ? 'من داخل الشركة' : 'من خارج الشركة',
                  'هوية ${w.nationalId}',
                  if (valid) 'شهد ${fmt.format(w.attestedAt!.toLocal())}'
                  else if (w.attested) 'أُلغيت شهادته لتغيّر العقد'
                  else 'لم يشهد بعد',
                ].join(' · '),
                trailing: completed
                    ? null
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        if (canAttest)
                          TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => WitnessAttestationScreen(sessionId: s.id, witnessIndex: e.key),
                              ),
                            ),
                            child: const Text('الشهادة'),
                          )
                        else if (!valid)
                          const Text('يشهد من جواله', style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                        if (!w.attested)
                          IconButton(
                            tooltip: 'إزالة',
                            onPressed: () => st.setWitnesses(s, [...s.witnesses]..removeAt(e.key)),
                            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 20),
                          ),
                      ]),
              );
            }),
            if (!completed)
              OutlinedButton.icon(
                onPressed: () => _inviteWitness(context, s),
                icon: const Icon(Icons.person_add_alt_rounded),
                label: const Text('دعوة شاهد'),
              ),
            const SizedBox(height: 22),
            _Step(n: 3, title: 'الاعتماد النهائي', subtitle: 'يُقفل العقد ويُصدر PDF مع مرجع سلامة', done: completed),
            const SizedBox(height: 10),
            if (!completed && blockers.isNotEmpty)
              ...blockers.map((b) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      const Icon(Icons.close_rounded, size: 16, color: AppColors.danger),
                      const SizedBox(width: 6),
                      Expanded(child: Text(b, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5))),
                    ]),
                  )),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: completed
                  ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => FinalContractScreen(sessionId: s.id)))
                  : blockers.isEmpty
                      ? () => _finalize(context, s)
                      : null,
              icon: Icon(completed ? Icons.description_rounded : Icons.verified_rounded),
              label: Text(completed ? 'عرض العقد النهائي' : 'اعتماد العقد نهائياً'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finalize(BuildContext context, ContractSession s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اعتماد العقد نهائياً؟'),
        content: const Text(
          'بعد الاعتماد يُقفل العقد للقراءة فقط، ويُحسب مرجع سلامته، ولا يُعدَّل إلا بإصدار جديد بقرار الشركاء.',
          style: TextStyle(height: 1.7),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('اعتماد')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final st = context.read<ContractState>();
    st.complete(s);
    if (s.companyId != null) context.read<CompanyState>().setContractVersion(s.companyId!, 1);
    Navigator.push(context, MaterialPageRoute(builder: (_) => FinalContractScreen(sessionId: s.id)));
  }

  Future<void> _signPartner(BuildContext context, ContractSession s, SessionPartner p) async {
    final state = context.read<ContractState>();
    final padKey = GlobalKey<SignaturePadState>();
    var declared = false;
    final hash = state.draftHash(s);
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
                Text('توقيع ${p.name}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('على الإصدار ${hash.substring(0, 16)}…',
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: declared,
                  onChanged: (v) => setSheet(() => declared = v ?? false),
                  activeColor: AppColors.gold,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'أقر بأنني كامل الأهلية القانونية، وأنني اطلعت على هذا الإصدار من العقد ووافقت على بنوده بإرادتي الحرة ودون إكراه.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.6),
                  ),
                ),
                const SizedBox(height: 8),
                SignaturePad(key: padKey, height: 200),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(onPressed: () => padKey.currentState?.clear(), child: const Text('مسح التوقيع')),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final pad = padKey.currentState;
                    if (!declared || pad == null || pad.isEmpty) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('يلزم إقرار الأهلية والتوقيع')));
                      return;
                    }
                    final png = await pad.exportBase64();
                    if (!ctx.mounted || png == null) return;
                    final m = await IdentityService.confirm(ctx, partnerName: p.name, action: 'التوقيع النهائي على العقد');
                    if (m == null) return;
                    state.signOff(s, PartnerSignOff(partnerId: p.id, signaturePng: png, at: DateTime.now(), method: m));
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: const Text('تأكيد الهوية واعتماد التوقيع'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// دعوة شاهد برقم جواله: يشهد من جواله في وضع الخادم، أو على هذا الجهاز محلياً
  Future<void> _inviteWitness(BuildContext context, ContractSession s) async {
    final state = context.read<ContractState>();
    final name = TextEditingController();
    final nid = TextEditingController();
    final phone = TextEditingController();
    var internal = false;
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
              const Text('دعوة شاهد',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الشاهد', isDense: true)),
              const SizedBox(height: 10),
              TextField(controller: nid, decoration: const InputDecoration(labelText: 'رقم الهوية', isDense: true)),
              const SizedBox(height: 10),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'رقم جوال الشاهد (يشهد منه)',
                  hintText: '+967 7XX XXX XXX',
                  isDense: true,
                ),
              ),
              SwitchListTile(
                value: internal,
                onChanged: (v) => setSheet(() => internal = v),
                activeThumbColor: AppColors.gold,
                contentPadding: EdgeInsets.zero,
                title: const Text('من داخل الشركة', style: TextStyle(color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () {
                  if (name.text.trim().isEmpty || nid.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('أكمل اسم الشاهد ورقم هويته')));
                    return;
                  }
                  final ph = phone.text.trim().isEmpty ? '' : normalizePhone(phone.text);
                  if (state.isCloud && ph.length < 10) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('أدخل رقم جوال الشاهد ليشهد منه')));
                    return;
                  }
                  state.setWitnesses(s, [
                    ...s.witnesses,
                    Witness(name: name.text.trim(), nationalId: nid.text.trim(), internal: internal, phone: ph),
                  ]);
                  Navigator.pop(ctx);
                },
                child: const Text('إضافة الشاهد'),
              ),
            ],
          ),
        ),
      ),
    );
    name.dispose();
    nid.dispose();
    phone.dispose();
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final Widget? trailing;
  const _Row({required this.icon, required this.color, required this.title, required this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.navySurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                  Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      );
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
              Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
              Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
            ],
          ),
        ),
      ],
    );
  }
}
