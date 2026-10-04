import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/yemen_law.dart';
import '../../models/questionnaire.dart';
import '../../providers/app_state.dart';
import '../../models/company.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../services/phone.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../admin/account_dialogs.dart';
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
  final TextEditingController email = TextEditingController();
  final TextEditingController guardian = TextEditingController();
  final TextEditingController guardianRef = TextEditingController();
  PartnerClass partnerClass = PartnerClass.general;
  bool yemeni = true;
  bool minor = false;

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
    guardian.dispose();
    guardianRef.dispose();
    email.dispose();
  }
}

class _NewSessionScreenState extends State<NewSessionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _company = TextEditingController();
  final _purpose = TextEditingController();
  final _capital = TextEditingController(text: '100000');
  final _rate = TextEditingController();
  CompanyFormSpec _form = formSpec(CompanyForm.llc);
  bool _capitalAck = false;

  /// إنشاء حسابات دخول بالبريد بكلمات سر مبدئية للشركاء الذين لهم بريد
  bool _createAccounts = true;
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
    _purpose.dispose();
    _capital.dispose();
    _rate.dispose();
    for (final p in _partners) {
      p.dispose();
    }
    super.dispose();
  }

  double get _equitySum => _partners.fold(
      0, (a, p) => a + (double.tryParse(p.equity.text.trim()) ?? 0));

  Future<void> _start() async {
    if (!_formKey.currentState!.validate()) return;
    if (_partners.length < 2) {
      _snack('يجب أن يكون عدد الشركاء اثنين على الأقل');
      return;
    }
    if ((_equitySum - 100).abs() > 0.01) {
      _snack('مجموع الحصص يجب أن يساوي 100% (الحالي ${_equitySum.toStringAsFixed(1)}%)');
      return;
    }
    // شروط الشكل القانوني (قانون الشركات التجارية اليمني)
    bool general(_PartnerDraft p) => !_form.twoClasses || p.partnerClass == PartnerClass.general;
    // العقد بالريال اليمني: لا حاجة لسعر صرف
    final rate = _currency == AppCurrency.yer ? 1.0 : double.tryParse(_rate.text.trim());
    final violations = formViolations(
      _form,
      partners: _partners.length,
      generalPartners: _partners.where(general).length,
      limitedPartners: _partners.where((p) => !general(p)).length,
      nonYemeniGeneral: _form.generalPartnerYemeni ? _partners.where((p) => general(p) && !p.yemeni).length : 0,
      minorGeneral: _form.generalPartnerYemeni ? _partners.where((p) => general(p) && p.minor).length : 0,
      capital: double.tryParse(_capital.text.trim()) ?? 0,
      yerRate: rate,
    );
    if (violations.isNotEmpty) {
      _snack(violations.join('، '));
      return;
    }
    if (_form.minCapitalYer != null && rate == null && !_capitalAck) {
      _snack('أدخل سعر الصرف المعتمد للتحقق من الحد الأدنى لرأس المال، أو أقرّ بأن رأس المال يستوفيه');
      return;
    }
    final emails = _partners.map((p) => p.email.text.trim().toLowerCase()).where((e) => e.isNotEmpty).toList();
    if (emails.any((e) => !isValidEmail(e))) {
      _snack('بريد إلكتروني غير صحيح لأحد الشركاء');
      return;
    }
    if (emails.toSet().length != emails.length) {
      _snack('لا يجوز تكرار البريد الإلكتروني لأكثر من شريك');
      return;
    }
    if (_partners.any((p) => p.minor && (p.guardian.text.trim().isEmpty || p.guardianRef.text.trim().isEmpty))) {
      _snack('الشريك القاصر يلزمه اسم الولي أو الوصي ورقم حكم الوصاية');
      return;
    }
    final state = context.read<ContractState>();
    final phones = _partners.map((p) => normalizePhone(p.phone.text)).toList();
    if (state.isCloud) {
      // كل شريك يدخل برقم جواله، لذا الرقم إلزامي وغير مكرر، ويجب أن يكون منشئ الجلسة أحدهم
      // كل شريك يدخل برقم جواله أو ببريده وكلمة سر مبدئية
      if (_partners.any((p) => normalizePhone(p.phone.text).length < 10 && p.email.text.trim().isEmpty)) {
        _snack('أدخل لكل شريك رقم جوال صحيحاً أو بريداً إلكترونياً للدخول');
        return;
      }
      if (phones.where((p) => p.length >= 10).toSet().length != phones.where((p) => p.length >= 10).length) {
        _snack('لا يجوز تكرار رقم الجوال لأكثر من شريك');
        return;
      }
      if (!phones.contains(state.myPhone) && !emails.map(emailKey).contains(state.myPhone)) {
        _snack('يجب أن تكون أحد الشركاء: أضف رقم جوالك ${state.myPhone} في الجدول');
        return;
      }
    }
    // رحلة التأسيس: إنشاء الشركة بشركائها وحصصها ثم فتح جلسة التأسيس لها
    final company = context.read<CompanyState>().createCompany(
      legalName: _company.text.trim(),
      companyType: _form.label,
      currency: _currency,
      capital: double.parse(_capital.text.trim()),
      purpose: _purpose.text,
      yerRate: _currency == AppCurrency.yer ? 1.0 : double.tryParse(_rate.text.trim()),
      members: [
        for (var i = 0; i < _partners.length; i++)
          CompanyMember(
            id: _partners[i].id,
            name: _partners[i].name.text.trim(),
            nationalId: _partners[i].nationalId.text.trim(),
            phone: normalizePhone(_partners[i].phone.text),
            equity: double.parse(_partners[i].equity.text.trim()),
            roles: {i == _managing ? CompanyRole.managingPartner : CompanyRole.partner},
            partnerClass: _form.twoClasses ? _partners[i].partnerClass.name : null,
            yemeni: _partners[i].yemeni,
            guardianName: _partners[i].minor ? _partners[i].guardian.text.trim() : null,
            guardianshipRef: _partners[i].minor ? _partners[i].guardianRef.text.trim() : null,
            email: _partners[i].email.text.trim().toLowerCase(),
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
      settings: company.votingSettings,
      purpose: company.purpose,
    );
    // حسابات الدخول بالبريد: كلمات سر مبدئية يسلّمها مدير النظام (منشئ الشركة)
    if (_createAccounts && company.partners.any((m) => m.email.isNotEmpty)) {
      await provisionAccounts(context, company, company.partners.where((m) => m.email.isNotEmpty).toList());
    }
    if (!mounted) return;
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
            DropdownButtonFormField<CompanyForm>(
              initialValue: _form.form,
              isExpanded: true,
              dropdownColor: AppColors.navySurface,
              decoration: const InputDecoration(
                labelText: 'الشكل القانوني (القانون اليمني)',
                prefixIcon: Icon(Icons.account_balance_rounded),
              ),
              items: [
                for (final f in kCompanyForms)
                  DropdownMenuItem(value: f.form, child: Text('${f.label} · ${f.category}')),
              ],
              onChanged: (v) => setState(() => _form = formSpec(v!)),
            ),
            const SizedBox(height: 10),
            _FormSpecCard(spec: _form),
            const SizedBox(height: 12),
            TextFormField(
              controller: _purpose,
              validator: _required,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'أغراض الشركة (بند جوهري)',
                prefixIcon: Icon(Icons.flag_rounded),
              ),
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
              segments: context.watch<ContractState>().enabledCurrencies
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
            if (_form.minCapitalYer != null && _currency == AppCurrency.yer)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('الحد الأدنى لرأس المال ${_form.minCapitalYer!.toStringAsFixed(0)} ريال يمني',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
            if (_form.minCapitalYer != null && _currency != AppCurrency.yer) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _rate,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'سعر الصرف المعتمد: ريال يمني لكل 1 ${_currency.code}',
                  prefixIcon: const Icon(Icons.currency_exchange_rounded),
                  helperText: double.tryParse(_rate.text) == null
                      ? 'الحد الأدنى لرأس المال ${_form.minCapitalYer!.toStringAsFixed(0)} ريال يمني'
                      : 'يعادل ${((double.tryParse(_capital.text) ?? 0) * double.parse(_rate.text)).toStringAsFixed(0)} ريالاً يمنياً · الحد الأدنى ${_form.minCapitalYer!.toStringAsFixed(0)}',
                ),
              ),
              if (double.tryParse(_rate.text) == null)
                CheckboxListTile(
                  value: _capitalAck,
                  onChanged: (v) => setState(() => _capitalAck = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppColors.gold,
                  title: Text('نقرّ بأن رأس المال يعادل ${_form.minCapitalYer!.toStringAsFixed(0)} ريال يمني على الأقل',
                      style: const TextStyle(fontSize: 12.5)),
                ),
            ],
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
                  spec: _form,
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
            if (_partners.any((p) => p.email.text.trim().isNotEmpty))
              CheckboxListTile(
                value: _createAccounts,
                onChanged: (v) => setState(() => _createAccounts = v ?? true),
                contentPadding: EdgeInsets.zero,
                activeColor: AppColors.gold,
                title: const Text('إنشاء حسابات دخول بالبريد بكلمات سر مبدئية', style: TextStyle(fontSize: 13)),
                subtitle: const Text('تظهر لك كلمات السر مرة واحدة لتسلّمها للشركاء، ويغيّرها كل شريك عند أول دخول.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
              ),
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
        Flexible(
          child: Text(text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

class _PartnerForm extends StatelessWidget {
  final int index;
  final _PartnerDraft draft;
  final CompanyFormSpec spec;
  final String? Function(String?) required;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;
  final bool managing;
  final VoidCallback onSetManaging;

  const _PartnerForm({
    required this.index,
    required this.draft,
    required this.spec,
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
                Expanded(
                  child: Text('الشريك ${index + 1}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
                ),
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
            const SizedBox(height: 10),
            TextFormField(
              controller: draft.email,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              onChanged: (_) => onChanged(),
              validator: (v) => v == null || v.trim().isEmpty || isValidEmail(v) ? null : 'بريد غير صحيح',
              decoration: const InputDecoration(
                labelText: 'البريد الإلكتروني (للدخول بكلمة سر)',
                hintText: 'name@example.com',
                isDense: true,
              ),
            ),
            if (spec.twoClasses) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [
                for (final pc in PartnerClass.values)
                  ChoiceChip(
                    label: Text(pc == PartnerClass.limited && spec.form == CompanyForm.partnershipLimitedByShares ? 'شريك مساهم' : pc.label),
                    selected: draft.partnerClass == pc,
                    onSelected: (_) {
                      draft.partnerClass = pc;
                      onChanged();
                    },
                  ),
              ]),
            ],
            Row(children: [
              if (spec.generalPartnerYemeni)
                Expanded(
                  child: CheckboxListTile(
                    value: draft.yemeni,
                    onChanged: (v) {
                      draft.yemeni = v ?? true;
                      onChanged();
                    },
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppColors.gold,
                    title: const Text('يمني الجنسية', style: TextStyle(fontSize: 12.5)),
                  ),
                ),
              Expanded(
                child: CheckboxListTile(
                  value: draft.minor,
                  onChanged: (v) {
                    draft.minor = v ?? false;
                    onChanged();
                  },
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppColors.gold,
                  title: const Text('قاصر أو ناقص أهلية', style: TextStyle(fontSize: 12.5)),
                ),
              ),
            ]),
            if (draft.minor) ...[
              TextFormField(
                controller: draft.guardian,
                decoration: const InputDecoration(labelText: 'اسم الولي الشرعي أو الوصي', isDense: true),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: draft.guardianRef,
                decoration: const InputDecoration(labelText: 'رقم حكم الوصاية أو الولاية', isDense: true),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('يوقّع الولي أو الوصي المأذون قضائياً عن القاصر وفق القانون المدني اليمني.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// بطاقة شروط الشكل القانوني المختار (من وثائق القانون اليمني)
class _FormSpecCard extends StatelessWidget {
  final CompanyFormSpec spec;
  const _FormSpecCard({required this.spec});

  @override
  Widget build(BuildContext context) {
    String n(double v) => v.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    final lines = <String>[
      spec.liability,
      'الشركاء: ${spec.minPartners} على الأقل${spec.maxPartners == null ? '' : ' وحتى ${spec.maxPartners}'}',
      if (spec.minCapitalYer != null) 'الحد الأدنى لرأس المال: ${n(spec.minCapitalYer!)} ريال يمني',
      if (spec.minShareValueYer != null) 'أقل قيمة للحصة أو السهم: ${n(spec.minShareValueYer!)} ريال يمني',
      'الترخيص: ${spec.licensing}',
      ...spec.notes,
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (spec.legalPersonality ? AppColors.info : AppColors.warning).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (spec.legalPersonality ? AppColors.info : AppColors.warning).withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${spec.label} · ${spec.category}', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(spec.definition, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.6)),
        for (final l in lines) Text('• $l', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.6)),
        if (!spec.legalPersonality)
          const Text('تنبيه: لا تتمتع بالشخصية الاعتبارية ولا تُشهر بالسجل التجاري.',
              style: TextStyle(color: AppColors.warning, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
