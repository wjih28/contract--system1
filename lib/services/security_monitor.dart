import '../models/admin.dart';
import '../models/company.dart';
import '../models/operations.dart';

/// A20: أحداث الأمان والتكامل مشتقة من سجل التدقيق ودليل تسليم الإشعارات.
/// لا تُعرض أي أسرار أو بيانات بصمة أو مواد توقيع خاصة؛ فقط نوع الحدث ومرجعه.
class SecurityMonitor {
  SecurityMonitor._();

  static List<SecurityEvent> events(Company c, List<AuditEvent> audit, List<AppNotification> notifications) {
    final out = <SecurityEvent>[];
    for (final e in audit) {
      final ev = _fromAudit(e);
      if (ev != null) out.add(ev);
    }
    // قنوات التبليغ القانوني غير المهيأة: حدث واحد لكل يوم بدل حدث لكل إشعار
    final days = <String, int>{};
    for (final n in notifications.where((n) => n.companyId == c.id && n.category.mandatory)) {
      if (n.deliveries.any((d) => d.status == DeliveryStatus.notConfigured)) {
        final k = '${n.sentAt.year}-${n.sentAt.month}-${n.sentAt.day}';
        days[k] = (days[k] ?? 0) + 1;
      }
    }
    for (final e in days.entries) {
      final p = e.key.split('-').map(int.parse).toList();
      out.add(SecurityEvent(
        id: 'NOTIF-${e.key}',
        type: 'تسليم الإشعارات',
        component: 'قنوات الرسائل',
        severity: Severity.medium,
        at: DateTime(p[0], p[1], p[2], 23, 59),
        description: '${e.value} إشعارات إلزامية لم تُرسل برسالة SMS أو بريد لأن القناة غير مهيأة، ووصلت داخل التطبيق فقط.',
        correlationId: 'notif:${e.key}',
      ));
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return out;
  }

  static SecurityEvent? _fromAudit(AuditEvent e) {
    SecurityEvent make(String type, String component, Severity s, String text) => SecurityEvent(
          id: e.id,
          type: type,
          component: component,
          severity: s,
          at: e.at,
          description: text,
          correlationId: '${e.objectType}:${e.objectId}',
        );
    final who = e.actorName.isEmpty ? e.actorType.label : e.actorName;
    switch (e.objectType) {
      case 'security':
        return make('دخول', 'التحقق من الهوية', Severity.info, '$who: ${e.action}');
      case 'users':
        return make('تغيير وصول', 'المستخدمون', Severity.low, '$who: ${e.action} (${e.result})');
      case 'permissions':
        return make('تغيير صلاحيات', 'الصلاحيات والإفصاح', Severity.medium, '$who: ${e.action}');
      case 'settings':
        return make('تغيير إعداد', 'إعدادات المنصة', Severity.low, '$who: ${e.action} (${e.result})');
      case 'integration':
        final bad = RegExp(r'(\d+) غير صالحة').firstMatch(e.result);
        final dup = RegExp(r'(\d+) مكررة').firstMatch(e.result);
        final issues = (int.tryParse(bad?.group(1) ?? '0') ?? 0) + (int.tryParse(dup?.group(1) ?? '0') ?? 0);
        return make('مزامنة', 'التكامل المحاسبي', issues > 0 ? Severity.medium : Severity.info, '${e.action}: ${e.result}');
    }
    // التوقيع والشهادة والبصمة: حدث معلوماتي بمرجعه فقط
    if (e.objectType == 'contract' && (e.action.contains('توقيع') || e.action.contains('شهادة'))) {
      return make('توقيع', 'التوقيع والشهود', Severity.info, '$who: ${e.action}');
    }
    if (e.objectType == 'contract' && e.result.contains('لا يطابق')) {
      return make('سلامة المستند', 'العقد', Severity.high, e.action);
    }
    return null;
  }
}
