/// توحيد أرقام الجوال بصيغة E.164 (مثل +967771234567) لمطابقتها مع رقم الدخول في Firebase.
/// الرقم بدون مفتاح دولة يُعامل كرقم يمني.
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
