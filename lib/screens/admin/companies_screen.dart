import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/company.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../providers/operations_state.dart';
import '../../theme/app_theme.dart';
import '../company/audit_log_screen.dart';
import 'integrations_screen.dart';
import 'roles_screen.dart';
import 'users_screen.dart';

final _d = DateFormat('yyyy/MM/dd');

/// A02: إدارة الشركات. سجل إداري لكل شركة وإعدادها، دون أي تعديل مباشر على محتوى عقد معتمد.
class CompaniesScreen extends StatelessWidget {
  const CompaniesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final st = context.watch<ContractState>();
    final ops = context.watch<OperationsState>();
    final list = cs.companies;
    final wide = context.screenSize != ScreenSize.phone;

    Widget actions(Company c) => Wrap(spacing: 4, children: [
          for (final (label, icon, w) in [
            ('المستخدمون', Icons.group_rounded, const UsersScreen()),
            ('الصلاحيات', Icons.admin_panel_settings_rounded, const RolesScreen()),
            ('التكامل', Icons.sync_alt_rounded, const IntegrationsScreen()),
            ('السجل', Icons.manage_search_rounded, const AuditLogScreen()),
          ])
            TextButton.icon(
              onPressed: () {
                cs.select(c.id);
                Navigator.push(context, MaterialPageRoute(builder: (_) => w));
              },
              icon: Icon(icon, size: 16),
              label: Text(label),
            ),
        ]);

    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الشركات')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            StateBanner.readOnly('لا يمكن تعديل محتوى عقد معتمد من هنا. أي تغيير في البنود أو الحصص يتم بإصدار جديد يقرّه الشركاء.'),
            if (list.isEmpty) const StateView.empty(title: 'لا توجد شركات', message: 'أنشئ شركة من رحلة التأسيس.'),
            for (final c in list)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: c.id == cs.current?.id ? AppColors.gold : AppColors.divider),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(c.legalName,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
                      ),
                      Text(c.status.label, style: const TextStyle(color: AppColors.gold, fontSize: 12)),
                    ]),
                    const SizedBox(height: 6),
                    Wrap(spacing: wide ? 18 : 10, runSpacing: 4, children: [
                      _kv('المعرّف', c.id),
                      _kv('إصدار العقد', c.contractVersion == 0 ? 'لا يوجد' : '${c.contractVersion}'),
                      _kv('الشركاء', '${c.partners.length}'),
                      _kv('المستخدمون', '${c.staffMembers.where((m) => m.active).length}'),
                      _kv('القواعد السارية', '${ops.activeRules(st, c.id).length}'),
                      _kv('التكامل', 'استيراد ملف · Xero/QB غير مربوط'),
                      _kv('أُنشئت', _d.format(c.createdAt)),
                    ]),
                    const SizedBox(height: 4),
                    actions(c),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Text.rich(TextSpan(children: [
        TextSpan(text: '$k: ', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        TextSpan(text: v, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ]));
}
