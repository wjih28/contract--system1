
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

