import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/company.dart';
import '../../providers/company_state.dart';
import '../../theme/app_theme.dart';

/// سجل التدقيق (P15/A18 بصورتهما الأولية): أحداث للإضافة فقط، مع تصفية حسب نوع الفاعل
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  ActorType? _filter;

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final events = cs.audit.where((e) => _filter == null || e.actorType == _filter).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('سجل التدقيق')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            StateBanner.readOnly('سجل التدقيق للإضافة فقط: لا يمكن تعديل أي حدث أو حذفه.'),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('الكل'),
                  selected: _filter == null,
                  onSelected: (_) => setState(() => _filter = null),
                ),
                for (final t in ActorType.values)
                  ChoiceChip(
                    avatar: Icon(t.icon, size: 15),
                    label: Text(t.label),
                    selected: _filter == t,
                    onSelected: (_) => setState(() => _filter = t),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (cs.current == null)
              const StateView.empty(title: 'لا توجد شركة', message: 'أنشئ شركة لتبدأ أحداثها بالظهور هنا.')
            else if (events.isEmpty)
              StateView.empty(
                title: _filter == null ? 'لا توجد أحداث بعد' : 'لا نتائج لهذا التصفية',
                message: 'كل تصويت أو تأجيل أو توقيع أو اعتماد يُسجَّل هنا تلقائياً.',
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.navySurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.divider),
                ),
                child: AuditTimeline(events: events),
              ),
          ],
        ),
      ),
    );
  }
}
