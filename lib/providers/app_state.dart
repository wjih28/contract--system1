import 'package:flutter/material.dart';
import '../models/models.dart';

/// حالة التطبيق العامة - يحتوي على البيانات التجريبية للعرض التقديمي
class AppState extends ChangeNotifier {
  bool isLoggedIn = false;
  Partner? currentUser;

  // بيانات لوحة المراقبة
  final double complianceScore = 92;
  final double cashBalance = 210000;
  final double monthlyExpense = 85000;
  final double monthlyExpenseCap = 100000;
  final double realizedProfits = 1250000;
  final double capitalAmount = 2500000;
  final double accumulatedLosses = 180000; // نسبة من رأس المال لرادار الإنذار

  double get lossRatio => accumulatedLosses / capitalAmount;

  final List<Partner> partners = const [
    Partner(
      id: 'p1',
      fullName: 'خالد العولقي',
      officialEmail: 'khaled@mithaq-ye.com',
      phoneNumber: '+967 771 234 567',
      equityPercentage: 45,
      role: UserRole.executivePartner,
      avatarInitial: 'خ',
    ),
    Partner(
      id: 'p2',
      fullName: 'سارة الحضرمي',
      officialEmail: 'sara@mithaq-ye.com',
      phoneNumber: '+967 733 567 890',
      equityPercentage: 35,
      role: UserRole.investorPartner,
      avatarInitial: 'س',
    ),
    Partner(
      id: 'p3',
      fullName: 'أ. فيصل الشرعبي',
      officialEmail: 'faisal.lawyer@mithaq-legal.ye',
      phoneNumber: '+967 777 901 234',
      equityPercentage: 0,
      role: UserRole.lawyer,
      avatarInitial: 'ف',
    ),
    Partner(
      id: 'p4',
      fullName: 'منى الصنعاني',
      officialEmail: 'mona@mithaq-ye.com',
      phoneNumber: '+967 711 345 678',
      equityPercentage: 20,
      role: UserRole.investorPartner,
      avatarInitial: 'م',
    ),
  ];

  late List<LedgerTransaction> transactions = [
    LedgerTransaction(
      id: 't1001',
      description: 'تحويل وارد - دفعة عميل (مشروع البرج التجاري)',
      amount: 45000,
      date: DateTime.now().subtract(const Duration(hours: 2)),
      status: TransactionStatus.approved,
    ),
    LedgerTransaction(
      id: 't1002',
      description: 'أتعاب قانونية - صياغة عقد توريد',
      amount: 3200,
      date: DateTime.now().subtract(const Duration(hours: 5)),
      status: TransactionStatus.approved,
    ),
    LedgerTransaction(
      id: 't1003',
      description: 'سند صرف - مستلزمات مكتبية لمورد خارجي',
      amount: 3500,
      date: DateTime.now().subtract(const Duration(hours: 8)),
      status: TransactionStatus.frozen,
      clauseReference: 'البند 14 - سقف الصرف اللحظي للمدير التنفيذي',
      triggeredRule: 'MAX_SINGLE_EXPENSE (الحد: \$2,000)',
    ),
    LedgerTransaction(
      id: 't1004',
      description: 'سلفة شخصية للشريك المدير',
      amount: 8000,
      date: DateTime.now().subtract(const Duration(days: 1)),
      status: TransactionStatus.rejectedBreach,
      clauseReference: 'البند 22 - حظر السحب الشخصي دون موافقة مسبقة',
      triggeredRule: 'PERSONAL_WITHDRAWAL_BLOCK',
    ),
    LedgerTransaction(
      id: 't1005',
      description: 'دفعة مورد - عقد صيانة سنوي',
      amount: 12500,
      date: DateTime.now().subtract(const Duration(days: 2)),
      status: TransactionStatus.pendingApproval,
      clauseReference: 'البند 9 - شرط الاعتماد الثنائي للعقود > \$10,000',
    ),
    LedgerTransaction(
      id: 't1006',
      description: 'إيراد مبيعات - نقطة بيع الفرع الرئيسي',
      amount: 21300,
      date: DateTime.now().subtract(const Duration(days: 3)),
      status: TransactionStatus.approved,
    ),
  ];

  final List<double> revenueTrend = const [
    38, 42, 40, 55, 60, 58, 66, 70, 68, 75, 82, 85,
  ];

  final List<AuditNotification> notifications = [
    AuditNotification(
      id: 'n1',
      title: 'تنبيه حوكمة: تجاوز سقف الصرف',
      body:
          'حاول الشريك المدير تمرير عملية صرف بقيمة \$3,500 (تتجاوز السقف المحدد بـ \$2,000). يرجى اتخاذ إجراء.',
      channel: NotifyChannel.whatsapp,
      sentAt: DateTime.now().subtract(const Duration(hours: 8, minutes: 2)),
      deliveredAt: DateTime.now().subtract(const Duration(hours: 8, minutes: 1)),
      actionRequired: true,
      relatedTransactionId: 't1003',
    ),
    AuditNotification(
      id: 'n2',
      title: 'إنذار خرق تعاقدي صريح',
      body: 'تم تسجيل مخالفة صريحة لبند حظر السحب الشخصي دون إذن مسبق.',
      channel: NotifyChannel.email,
      sentAt: DateTime.now().subtract(const Duration(days: 1, hours: 1)),
      deliveredAt: DateTime.now().subtract(const Duration(days: 1)),
      actionRequired: false,
      relatedTransactionId: 't1004',
    ),
    AuditNotification(
      id: 'n3',
      title: 'طلب اعتماد ثنائي',
      body: 'عقد صيانة سنوي بقيمة \$12,500 يتطلب توقيعك كشريك غير تنفيذي.',
      channel: NotifyChannel.sms,
      sentAt: DateTime.now().subtract(const Duration(days: 2, hours: 3)),
      deliveredAt: DateTime.now().subtract(const Duration(days: 2, hours: 3)),
      actionRequired: true,
      relatedTransactionId: 't1005',
    ),
  ];

  final List<DisputeCase> disputes = [
    DisputeCase(
      id: 'd1',
      title: 'مخالفة سقف الصرف - سند \$3,500',
      clauseText: 'البند 14 - سقف الصرف اللحظي للمدير التنفيذي',
      status: 'قيد الترافع',
      disputedAmount: 3500,
      openedAt: DateTime.now().subtract(const Duration(hours: 6)),
    ),
    DisputeCase(
      id: 'd2',
      title: 'سحب شخصي غير مصرح به',
      clauseText: 'البند 22 - حظر السحب الشخصي دون موافقة مسبقة',
      status: 'مفتوحة',
      disputedAmount: 8000,
      openedAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
  ];

  void login(Partner partner) {
    currentUser = partner;
    isLoggedIn = true;
    notifyListeners();
  }

  void logout() {
    isLoggedIn = false;
    currentUser = null;
    notifyListeners();
  }

  void resolveTransaction(String id, {required bool approve}) {
    transactions = transactions.map((t) {
      if (t.id == id) {
        return LedgerTransaction(
          id: t.id,
          description: t.description,
          amount: t.amount,
          date: t.date,
          status: approve
              ? TransactionStatus.approved
              : TransactionStatus.rejectedBreach,
          clauseReference: t.clauseReference,
          triggeredRule: t.triggeredRule,
        );
      }
      return t;
    }).toList();
    notifyListeners();
  }
}
