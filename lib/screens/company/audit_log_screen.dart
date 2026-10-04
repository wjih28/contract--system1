import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/admin.dart';
import '../../models/company.dart';
import '../../providers/company_state.dart';
import '../../services/report_pdf.dart';
import '../../theme/app_theme.dart';

final _dt = DateFormat('yyyy/MM/dd HH:mm:ss');

/// أنواع الكائنات في السجل بأسمائها العربية
const _objectTypes = {
  'contract': 'العقد والإصدارات',
  'clause': 'البنود والتصويت',
  'session': 'جلسة التأسيس',
  'dispute': 'النزاعات',
  'transaction': 'العمليات المالية',
  'exception': 'الاستثناءات',
  'violation': 'المخالفات',
  'company': 'الشركة والحصص',
  'settings': 'الإعدادات',
  'integration': 'التكامل',
  'users': 'المستخدمون',
  'permissions': 'الصلاحيات والإفصاح',
  'security': 'الأمان',
};

/// P15 + A18: سجل التدقيق. خط زمني للأدلة مع تصفية حسب الفاعل والكائن والإصدار والفترة والبحث،
/// ونافذة تفاصيل لكل حدث، وتصدير تقرير. السجل للإضافة فقط، ويُميَّز حدث النظام عن فعل المستخدم.
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  ActorType? _actor;
  String? _object;
  int? _version;
  int _days = 0; // 0 = الكل
  String _q = '';
  int _shown = 50;

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final c = cs.current;
    final all = cs.audit;
    final versions = all.map((e) => e.contractVersion).whereType<int>().toSet().toList()..sort();
    final since = _days == 0 ? null : DateTime.now().subtract(Duration(days: _days));
    final q = _q.trim();
    final events = all
        .where((e) => _actor == null || e.actorType == _actor)
        .where((e) => _object == null || e.objectType == _object)
        .where((e) => _version == null || e.contractVersion == _version)
        .where((e) => since == null || e.at.isAfter(since))
        .where((e) =>
            q.isEmpty ||
            e.action.contains(q) ||
            e.result.contains(q) ||
            e.actorName.contains(q) ||
            e.objectId.contains(q) ||
            (e.evidenceRef ?? '').contains(q))
        .toList();
    final filtered = _actor != null || _object != null || _version != null || _days != 0 || q.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل التدقيق'),
        actions: [
          if (c != null && cs.canSee('audit.export', PermAction.print))
            IconButton(
              tooltip: 'تصدير تقرير PDF',
              icon: const Icon(Icons.picture_as_pdf_rounded),
              onPressed: events.isEmpty
                  ? null
                  : () => ReportPdf.shareAudit(c, events, filter: filtered ? 'نتائج التصفية' : 'كل الأحداث'),
            ),
        ],
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            StateBanner.readOnly('سجل التدقيق للإضافة فقط: لا يمكن تعديل أي حدث أو حذفه.'),
            TextField(
              onChanged: (v) => setState(() {
                _q = v;
                _shown = 50;
              }),
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded), labelText: 'بحث في الإجراء أو النتيجة أو الفاعل أو المرجع', isDense: true),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(label: const Text('كل الفاعلين'), selected: _actor == null, onSelected: (_) => setState(() => _actor = null)),
              for (final t in ActorType.values)
                ChoiceChip(
                  avatar: Icon(t.icon, size: 15),
                  label: Text(t.label),
                  selected: _actor == t,
                  onSelected: (_) => setState(() => _actor = t),
                ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _drop<String?>('الكائن', _object, {null: 'كل الكائنات', ..._objectTypes}, (v) => _object = v),
              _drop<int?>('الإصدار', _version, {null: 'كل الإصدارات', for (final v in versions) v: 'الإصدار $v'},
                  (v) => _version = v),
              _drop<int>('الفترة', _days, const {0: 'كل الفترات', 1: 'آخر يوم', 7: 'آخر 7 أيام', 30: 'آخر 30 يوماً'},
                  (v) => _days = v),
            ]),
            const SizedBox(height: 12),
            if (c == null)
              const StateView.empty(title: 'لا توجد شركة', message: 'أنشئ شركة لتبدأ أحداثها بالظهور هنا.')
            else if (events.isEmpty)
              StateView.empty(
                title: filtered ? 'لا نتائج لهذه التصفية' : 'لا توجد أحداث بعد',
                message: filtered
                    ? 'غيّر عوامل التصفية أو امسح البحث.'
                    : 'كل تصويت أو تأجيل أو توقيع أو اعتماد يُسجَّل هنا تلقائياً.',
              )
            else ...[
              Text('${events.length} حدث${events.length > _shown ? ' · يُعرض أول $_shown' : ''}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(height: 8),
              for (final e in events.take(_shown)) _EventTile(e: e),
              if (events.length > _shown)
                TextButton(onPressed: () => setState(() => _shown += 50), child: const Text('عرض المزيد')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _drop<T>(String label, T value, Map<T, String> items, void Function(T) on) => SizedBox(
        width: 190,
        child: DropdownButtonFormField<T>(
          initialValue: value,
          isExpanded: true,
          dropdownColor: AppColors.navySurface,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() {
            on(v as T);
            _shown = 50;
          }),
        ),
      );
}

class _EventTile extends StatelessWidget {
  final AuditEvent e;
  const _EventTile({required this.e});

  @override
  Widget build(BuildContext context) {
    final c = e.isSystem ? AppColors.info : AppColors.gold;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.navySurface,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: () => _detail(context),
          leading: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(e.actorType.icon, size: 16, color: c),
          ),
          title: Text(e.action, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          subtitle: Text(
            '${e.isSystem ? 'حدث نظام · ${e.actorType.label}' : e.actorName} · ${_dt.format(e.at.toLocal())}'
            '${e.contractVersion == null ? '' : ' · الإصدار ${e.contractVersion}'}'
            '${e.result.isEmpty ? '' : '\n${e.result}'}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.5),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: e.evidenceRef == null ? null : const Icon(Icons.verified_outlined, size: 18, color: AppColors.textMuted),
        ),
      ),
    );
  }

  /// P15_Audit_EventDetail: كل بيانات الحدث ومرجع الدليل
  void _detail(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.navySurface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(e.action, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(e.isSystem ? 'حدث آلي من ${e.actorType.label}' : 'فعل مستخدم',
                  style: TextStyle(color: e.isSystem ? AppColors.info : AppColors.gold, fontSize: 12)),
              const Divider(height: 24),
              _kv('الوقت', _dt.format(e.at.toLocal())),
              _kv('الفاعل', e.actorName.isEmpty ? e.actorType.label : e.actorName),
              _kv('الكائن', '${_objectTypes[e.objectType] ?? e.objectType} · ${e.objectId}'),
              _kv('النتيجة', e.result.isEmpty ? '—' : e.result),
              _kv('إصدار العقد', e.contractVersion?.toString() ?? '—'),
              _kv('معرّف الحدث', e.id),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _kv('مرجع الدليل', e.evidenceRef ?? 'لا يوجد دليل مرفق')),
                if (e.evidenceRef != null)
                  IconButton(
                    tooltip: 'نسخ',
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () => Clipboard.setData(ClipboardData(text: e.evidenceRef!)),
                  ),
              ]),
              const SizedBox(height: 8),
              const Text('لا يمكن تعديل هذا الحدث أو حذفه.', style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
            ]),
          ),
        ),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
          SelectableText(v, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
        ]),
      );
}
