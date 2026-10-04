import 'package:flutter/material.dart';
import '../models/models.dart';

/// حالة الدخول العامة. في الوضع المحلي تُعرض حسابات تجريبية لاختيار المستخدم،
/// وفي وضع الخادم يُسجَّل الدخول برقم الجوال المؤكد.
class AppState extends ChangeNotifier {
  bool isLoggedIn = false;
  Partner? currentUser;

  /// حسابات الوضع المحلي التجريبي فقط
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
}
