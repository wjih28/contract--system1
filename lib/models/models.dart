import 'package:flutter/material.dart';

/// نوع الدور الوظيفي للمستخدم داخل المنظومة
enum UserRole { executivePartner, investorPartner, lawyer, admin }

extension UserRoleX on UserRole {
  String get label {
    switch (this) {
      case UserRole.executivePartner:
        return 'الشريك المدير';
      case UserRole.investorPartner:
        return 'الشريك المستثمر';
      case UserRole.lawyer:
        return 'المستشار القانوني';
      case UserRole.admin:
        return 'مسؤول النظام';
    }
  }
}

/// نموذج الشريك
class Partner {
  final String id;
  final String fullName;
  final String officialEmail;
  final String phoneNumber;
  final double equityPercentage;
  final UserRole role;
  final String avatarInitial;

  const Partner({
    required this.id,
    required this.fullName,
    required this.officialEmail,
    required this.phoneNumber,
    required this.equityPercentage,
    required this.role,
    required this.avatarInitial,
  });
}

/// حالة المعاملة المالية
enum TransactionStatus { approved, frozen, rejectedBreach, pendingApproval }

extension TransactionStatusX on TransactionStatus {
  String get label {
    switch (this) {
      case TransactionStatus.approved:
        return 'مطابق ومرحّل';
      case TransactionStatus.frozen:
        return 'مجمّدة';
      case TransactionStatus.rejectedBreach:
        return 'خرق مسجّل';
      case TransactionStatus.pendingApproval:
        return 'بانتظار الاعتماد';
    }
  }

  Color get color {
    switch (this) {
      case TransactionStatus.approved:
        return const Color(0xFF2ECC71);
      case TransactionStatus.frozen:
        return const Color(0xFFF39C12);
      case TransactionStatus.rejectedBreach:
        return const Color(0xFFE74C3C);
      case TransactionStatus.pendingApproval:
        return const Color(0xFF3498DB);
    }
  }

  IconData get icon {
    switch (this) {
      case TransactionStatus.approved:
        return Icons.check_circle_rounded;
      case TransactionStatus.frozen:
        return Icons.ac_unit_rounded;
      case TransactionStatus.rejectedBreach:
        return Icons.gpp_bad_rounded;
      case TransactionStatus.pendingApproval:
        return Icons.hourglass_top_rounded;
    }
  }
}

/// نموذج المعاملة المالية المعترضة
class LedgerTransaction {
  final String id;
  final String description;
  final double amount;
  final DateTime date;
  final TransactionStatus status;
  final String? clauseReference;
  final String? triggeredRule;

  const LedgerTransaction({
    required this.id,
    required this.description,
    required this.amount,
    required this.date,
    required this.status,
    this.clauseReference,
    this.triggeredRule,
  });
}

/// خيار التصويت على بند تعاقدي
enum VoteChoice { agree, disagree, neutral, defer }

extension VoteChoiceX on VoteChoice {
  String get label {
    switch (this) {
      case VoteChoice.agree:
        return 'موافق';
      case VoteChoice.disagree:
        return 'غير موافق';
      case VoteChoice.neutral:
        return 'محايد';
      case VoteChoice.defer:
        return 'تأجيل';
    }
  }
}

/// بند تعاقدي من بنك الأسئلة
class ContractClause {
  final int id;
  final String category;
  final String text;
  final String requiredQuorumLabel;
  final double requiredQuorumValue;

  const ContractClause({
    required this.id,
    required this.category,
    required this.text,
    required this.requiredQuorumLabel,
    required this.requiredQuorumValue,
  });
}

/// قناة الإشعار
enum NotifyChannel { email, sms, whatsapp }

extension NotifyChannelX on NotifyChannel {
  String get label {
    switch (this) {
      case NotifyChannel.email:
        return 'البريد الرسمي';
      case NotifyChannel.sms:
        return 'رسالة SMS';
      case NotifyChannel.whatsapp:
        return 'واتساب';
    }
  }

  IconData get icon {
    switch (this) {
      case NotifyChannel.email:
        return Icons.mark_email_read_rounded;
      case NotifyChannel.sms:
        return Icons.sms_rounded;
      case NotifyChannel.whatsapp:
        return Icons.chat_rounded;
    }
  }
}

/// سجل إشعار قانوني
class AuditNotification {
  final String id;
  final String title;
  final String body;
  final NotifyChannel channel;
  final DateTime sentAt;
  final DateTime? deliveredAt;
  final bool actionRequired;
  final String? relatedTransactionId;

  const AuditNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.channel,
    required this.sentAt,
    this.deliveredAt,
    this.actionRequired = false,
    this.relatedTransactionId,
  });
}

/// قضية في غرفة التقاضي الرقمية
class DisputeCase {
  final String id;
  final String title;
  final String clauseText;
  final String status; // مفتوحة / قيد الترافع / مغلقة
  final double disputedAmount;
  final DateTime openedAt;

  const DisputeCase({
    required this.id,
    required this.title,
    required this.clauseText,
    required this.status,
    required this.disputedAmount,
    required this.openedAt,
  });
}
