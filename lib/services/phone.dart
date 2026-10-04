/// توحيد أرقام الجوال بصيغة E.164 (مثل +967771234567) لمطابقتها مع رقم الدخول في Firebase.
/// الرقم بدون مفتاح دولة يُعامل كرقم يمني.
/// هوية الدخول بالبريد الإلكتروني: تُخزَّن في قوائم الوصول بجانب أرقام الجوال (memberPhones وغيرها)
/// بصيغة "email:العنوان" حتى تتحقق منها قواعد الأمان كما تتحقق من رقم الجوال.
String emailKey(String email) => 'email:${email.trim().toLowerCase()}';

bool isValidEmail(String e) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e.trim());

String normalizePhone(String raw) {
  var p = raw.replaceAll(RegExp(r'[\s\-()]'), '');
  if (p.isEmpty) return p;
  if (p.startsWith('00')) p = '+${p.substring(2)}';
  if (!p.startsWith('+')) {
    if (p.startsWith('0')) p = p.substring(1);
    p = '+967$p';
  }
  return p;
}
