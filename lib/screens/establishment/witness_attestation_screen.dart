import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/questionnaire.dart';
import '../../providers/contract_state.dart';
import '../../services/identity_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/signature_pad.dart';
import 'contract_preview_screen.dart';

/// R07: شهادة الشاهد. الشاهد يؤكد هويته ويقرأ إصدار العقد ويوقّع،
/// وتُربط شهادته بإصدار المسودة الحالي تحديداً.
class WitnessAttestationScreen extends StatefulWidget {
  final String sessionId;
  final int witnessIndex;
  const WitnessAttestationScreen({super.key, required this.sessionId, required this.witnessIndex});

  @override
  State<WitnessAttestationScreen> createState() => _WitnessAttestationScreenState();
}

class _WitnessAttestationScreenState extends State<WitnessAttestationScreen> {
  final _pad = GlobalKey<SignaturePadState>();
  bool _confirmed = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final st = context.watch<ContractState>();
    final s = st.sessions.where((x) => x.id == widget.sessionId).firstOrNull;
    if (s == null || widget.witnessIndex >= s.witnesses.length) {
      return const Scaffold(body: StateView.empty(title: 'الدعوة غير موجودة', message: 'ربما أُزيلت أو اعتُمد العقد.'));
    }
    final w = s.witnesses[widget.witnessIndex];
    final hash = st.draftHash(s);
    final done = st.witnessValid(s, w);

    return Scaffold(
      appBar: AppBar(title: const Text('شهادة على العقد')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            if (done)
              const StateBanner(
                color: AppColors.success,
                icon: Icons.verified_user_rounded,
                text: 'سُجّلت شهادتك على هذا الإصدار. شكراً لك.',
              ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.navySurface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(w.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
                  Text('هوية ${w.nationalId} · ${w.internal ? 'من داخل الشركة' : 'من خارج الشركة'}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  const Divider(height: 22),
                  Text('عقد تأسيس ${s.companyName}',
                      style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800)),
                  Text('الإصدار: ${hash.substring(0, 16)}…',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ContractPreviewScreen(sessionId: s.id)),
                    ),
                    icon: const Icon(Icons.visibility_rounded),
                    label: const Text('قراءة نص العقد'),
                  ),
                ],
              ),
            ),
            if (!done) ...[
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _confirmed,
                onChanged: (v) => setState(() => _confirmed = v ?? false),
                activeColor: AppColors.gold,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'أشهد أنا ${w.name} بأن الشركاء المذكورين في هذا الإصدار من العقد وقّعوا عليه بحضوري، وأن هويتي وبياناتي صحيحة.',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.6),
                ),
              ),
              const SizedBox(height: 8),
              SignaturePad(key: _pad, height: 200),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(onPressed: () => _pad.currentState?.clear(), child: const Text('مسح التوقيع')),
              ),
              ElevatedButton.icon(
                onPressed: _busy ? null : () => _submit(s, w),
                icon: const Icon(Icons.fingerprint_rounded),
                label: const Text('تأكيد الهوية وتقديم الشهادة'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _submit(ContractSession s, Witness w) async {
    final pad = _pad.currentState;
    if (!_confirmed || pad == null || pad.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يلزم الإقرار والتوقيع')));
      return;
    }
    setState(() => _busy = true);
    final png = await pad.exportBase64();
    if (!mounted || png == null) return;
    final m = await IdentityService.confirm(context, partnerName: w.name, action: 'الشهادة على عقد ${s.companyName}');
    if (!mounted) return;
    setState(() => _busy = false);
    if (m == null) return;
    context.read<ContractState>().attestWitness(s, widget.witnessIndex, signature: png, method: m);
  }
}
