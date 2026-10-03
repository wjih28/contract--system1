import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/questionnaire.dart';
import '../../providers/app_state.dart';
import '../../models/company.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../services/phone.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import 'session_overview_screen.dart';

/// تهيئة جلسة تأسيس جديدة: بيانات الشركة والعملة وجدول الشركاء
class NewSessionScreen extends StatefulWidget {
  const NewSessionScreen({super.key});

  @override
  State<NewSessionScreen> createState() => _NewSessionScreenState();
}

class _PartnerDraft {
  final String id;
  final TextEditingController name;
  final TextEditingController nationalId;
  final TextEditingController phone;
  final TextEditingController equity;

  _PartnerDraft(this.id, {String n = '', String nid = '', String ph = '', String eq = ''})
      : name = TextEditingController(text: n),
        nationalId = TextEditingController(text: nid),
        phone = TextEditingController(text: ph),
        equity = TextEditingController(text: eq);

  void dispose() {
    name.dispose();
    nationalId.dispose();
    phone.dispose();
    equity.dispose();
  }
}

class _NewSessionScreenState extends State<NewSessionScreen> {
  static const _types = [
    'شركة ذات مسؤولية محدودة',
    'شركة تضامن',
    'شركة توصية بسيطة',
  ];

  final _formKey = GlobalKey<FormState>();
  final _company = TextEditingController();
  final _capital = TextEditingController(text: '100000');
  String _type = _types.first;
  AppCurrency _currency = AppCurrency.usd;
  final List<_PartnerDraft> _partners = [];
  int _managing = 0; // الشريك المدير (حسب ترتيبه في الجدول)

  @override
  void initState() {
    super.initState();
    final cloud = context.read<ContractState>();
    if (cloud.isCloud) {
      // وضع الخادم: يبدأ الجدول بمنشئ الجلسة برقم جواله المؤكد
      _partners.addAll([
        _PartnerDraft('p1', ph: cloud.myPhone ?? ''),
        _PartnerDraft('p2'),
      ]);
      return;
    }
    // تعبئة مبدئية من شركاء المنصة لتسريع التجربة، ويمكن تعديلها
    final existing = context.read<AppState>().partners.where((p) => p.equityPercentage > 0);
    for (final p in existing) {
      _partners.add(_PartnerDraft(
        p.id,
        n: p.fullName,
        ph: p.phoneNumber,
        eq: p.equityPercentage.toStringAsFixed(0),
      ));
    }
    if (_partners.isEmpty) {
      _partners.addAll([_PartnerDraft('p1'), _PartnerDraft('p2')]);
    }
  }

  @override
  void dispose() {
    _company.dispose();
    _capital.dispose();
    for (final p in _partners) {
      p.dispose();
    }
    super.dispose();
  }

  double get _equitySum => _partners.fold(
      0, (a, p) => a + (double.tryParse(p.equity.text.trim()) ?? 0));

  void _start() {
    if (!_formKey.currentState!.validate()) return;
    if (_partners.length < 2) {
      _snack('يجب أن يكون عدد الشركاء اثنين على الأقل');
      return;
    }
    if ((_equitySum - 100).abs() > 0.01) {
      _snack('مجموع الحصص يجب أن يساوي 100% (الحالي ${_equitySum.toStringAsFixed(1)}%)');
      return;
    }
    final state = context.read<ContractState>();
    final phones = _partners.map((p) => normalizePhone(p.phone.text)).toList();
    if (state.isCloud) {
      // كل شريك يدخل برقم جواله، لذا الرقم إلزامي وغير مكرر، ويجب أن يكون منشئ الجلسة أحدهم
      if (phones.any((p) => p.length < 10)) {
        _snack('أدخل رقم جوال صحيح لكل شريك، فكل شريك يصوّت من جواله');
        return;
      }
      if (phones.toSet().length != phones.length) {
        _snack('لا يجوز تكرار رقم الجوال لأكثر من شريك');
        return;
      }
      if (!phones.contains(state.myPhone)) {
        _snack('يجب أن تكون أحد الشركاء: أضف رقم جوالك ${state.myPhone} في الجدول');
        return;
      }
    }
    // رحلة التأسيس: إنشاء الشركة بشركائها وحصصها ثم فتح جلسة التأسيس لها
    final company = context.read<CompanyState>().createCompany(
      legalName: _company.text.trim(),
      companyType: _type,
      currency: _currency,
      capital: double.parse(_capital.text.trim()),
      members: [
        for (var i = 0; i < _partners.length; i++)
          CompanyMember(
            id: _partners[i].id,
            name: _partners[i].name.text.trim(),
            nationalId: _partners[i].nationalId.text.trim(),
            phone: normalizePhone(_partners[i].phone.text),
            equity: double.parse(_partners[i].equity.text.trim()),
            roles: {i == _managing ? CompanyRole.managingPartner : CompanyRole.partner},
          ),
      ],
    );
    final s = state.createSession(
      companyId: company.id,
      companyName: company.legalName,
      companyType: company.companyType,
      currency: company.currency,
      capital: company.capital,
      partners: company.partners.map((m) => m.toSessionPartner()).toList(),
    );
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => SessionOverviewScreen(sessionId: s.id)),
    );
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'حقل مطلوب' : null;

  @override
  Widget build(BuildContext context) {
    final sum = _equitySum;
    final sumOk = (sum - 100).abs() <= 0.01;

    return Scaffold(
      appBar: AppBar(title: const Text('تأسيس شركة جديدة')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const _StepLabel(n: 1, text: 'بيانات الشركة'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _company,
              validator: _required,
              decoration: const InputDecoration(
                labelText: 'اسم الشركة',
                prefixIcon: Icon(Icons.business_rounded),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              dropdownColor: AppColors.navySurface,
              decoration: const InputDecoration(
                labelText: 'الشكل القانوني',
                prefixIcon: Icon(Icons.account_balance_rounded),
              ),
              items: _types
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 18),
            const Text('عملة العقد',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SegmentedButton<AppCurrency>(
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AppColors.gold,
                selectedForegroundColor: AppColors.navyDark,
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.divider),
              ),
              segments: AppCurrency.values
                  .map((c) => ButtonSegment(
                        value: c,
                        label: Text('${c.label} (${c.code})'),
                      ))
                  .toList(),
              selected: {_currency},
              onSelectionChanged: (v) => setState(() => _currency = v.first),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _capital,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              validator: (v) =>
                  (double.tryParse(v ?? '') ?? 0) <= 0 ? 'أدخل رأس مال صحيح' : null,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'رأس المال',
                prefixIcon: const Icon(Icons.savings_rounded),
                suffixText: _currency.code,
                helperText: formatCurrency(
                    double.tryParse(_capital.text) ?? 0, _currency),
              ),
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                const Expanded(child: _StepLabel(n: 2, text: 'جدول الشركاء والحصص')),
                StatusChip(
                  label: 'المجموع ${sum.toStringAsFixed(sum % 1 == 0 ? 0 : 1)}%',
                  color: sumOk ? AppColors.success : AppColors.warning,
                  icon: sumOk ? Icons.check_rounded : Icons.warning_amber_rounded,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._partners.asMap().entries.map((e) => _PartnerForm(
                  index: e.key,
                  draft: e.value,
                  required: _required,
                  onChanged: () => setState(() {}),
                  managing: e.key == _managing,
                  onSetManaging: () => setState(() => _managing = e.key),
                  onRemove: _partners.length <= 2
                      ? null
                      : () => setState(() {
                            _partners.removeAt(e.key).dispose();
                            if (_managing >= _partners.length) _managing = 0;
                          }),
                )),
            OutlinedButton.icon(
              onPressed: () => setState(() => _partners.add(
                  _PartnerDraft('p${DateTime.now().microsecondsSinceEpoch}'))),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('إضافة شريك'),
            ),
            const SizedBox(height: 26),
            ElevatedButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('إنشاء الشركة وبدء جلسة التأسيس'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepLabel extends StatelessWidget {
  final int n;
  final String text;
  const _StepLabel({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.goldGradient,
          ),
          child: Text('$n',
              style: const TextStyle(
                  color: AppColors.navyDark, fontWeight: FontWeight.w900, fontSize: 13)),
        ),
        const SizedBox(width: 10),
        Text(text,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _PartnerForm extends StatelessWidget {
  final int index;
  final _PartnerDraft draft;
  final String? Function(String?) required;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;
  final bool managing;
  final VoidCallback onSetManaging;

  const _PartnerForm({
    required this.index,
    required this.draft,
    required this.required,
    required this.onChanged,
    required this.onRemove,
    required this.managing,
    required this.onSetManaging,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GoldBorderCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.gold.withValues(alpha: 0.15),
                  child: Text('${index + 1}',
                      style: const TextStyle(color: AppColors.gold, fontSize: 12)),
                ),
                const SizedBox(width: 8),
                Text('الشريك ${index + 1}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
                const Spacer(),
                ChoiceChip(
                  label: const Text('الشريك المدير'),
                  selected: managing,
                  onSelected: (_) => onSetManaging(),
                  selectedColor: AppColors.gold,
                  backgroundColor: AppColors.navyLight,
                  labelStyle: TextStyle(
                    color: managing ? AppColors.navyDark : AppColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                  side: const BorderSide(color: AppColors.divider),
                  visualDensity: VisualDensity.compact,
                ),
                if (onRemove != null)
                  IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: draft.name,
              validator: required,
              decoration: const InputDecoration(labelText: 'الاسم الكامل', isDense: true),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: draft.nationalId,
                    decoration:
                        const InputDecoration(labelText: 'رقم الهوية', isDense: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: draft.equity,
                    validator: (v) =>
                        (double.tryParse(v ?? '') ?? -1) < 0 ? 'نسبة غير صحيحة' : null,
                    onChanged: (_) => onChanged(),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'الحصة', suffixText: '%', isDense: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: draft.phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'رقم الجوال (للتبليغ الرسمي SMS)',
                hintText: '+967 7XX XXX XXX',
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
