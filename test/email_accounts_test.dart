// الدخول بالبريد: حسابات بكلمة سر مبدئية يغيّرها الشريك عند أول دخول، ومفاتيح الهوية، والريال اليمني
import 'package:flutter_test/flutter_test.dart';
import 'package:mithaq_app/models/company.dart';
import 'package:mithaq_app/models/questionnaire.dart';
import 'package:mithaq_app/providers/company_state.dart';
import 'package:mithaq_app/services/account_service.dart';
import 'package:mithaq_app/services/phone.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('الريال اليمني عملة ثالثة', () {
    expect(AppCurrency.values, hasLength(3));
    expect(AppCurrency.yer.code, 'YER');
    expect(AppCurrency.yer.label, 'ريال يمني');
  });

  group('حسابات البريد (الوضع المحلي)', () {
    test('كلمة السر المبدئية: 10 خانات بلا أحرف ملتبسة', () {
      final p = AccountService.generatePassword();
      expect(p, hasLength(10));
      expect(p, isNot(matches(RegExp('[0O1lI]'))));
    });

    test('أول دخول يُلزم بتغيير كلمة السر، وبعد التغيير تبطل المبدئية', () async {
      expect(await AccountService.createAccount('Ali@Mail.com', 'Temp12345', createdBy: 'admin'), isNull);
      expect(await AccountService.createAccount('ali@mail.com', 'x', createdBy: 'admin'), isNotNull);
      expect(await AccountService.hasAccount('ali@mail.com'), isTrue);

      var (err, must) = await AccountService.signIn('ali@mail.com', 'wrong');
      expect(err, isNotNull);
      (err, must) = await AccountService.signIn(' ALI@mail.com ', 'Temp12345');
      expect(err, isNull);
      expect(must, isTrue);

      expect(await AccountService.changePassword('ali@mail.com', 'Temp12345', 'short'), isNotNull);
      expect(await AccountService.changePassword('ali@mail.com', 'Temp12345', 'Temp12345'), isNotNull);
      expect(await AccountService.changePassword('ali@mail.com', 'bad', 'NewPass2026'), isNotNull);
      expect(await AccountService.changePassword('ali@mail.com', 'Temp12345', 'NewPass2026'), isNull);

      (err, must) = await AccountService.signIn('ali@mail.com', 'Temp12345');
      expect(err, isNotNull);
      (err, must) = await AccountService.signIn('ali@mail.com', 'NewPass2026');
      expect(err, isNull);
      expect(must, isFalse);
    });
  });

  group('مفاتيح الهوية بالبريد', () {
    late CompanyState cs;
    late Company c;
    setUp(() async {
      cs = CompanyState();
      await cs.load();
      c = cs.createCompany(
        legalName: 'شركة',
        companyType: 'ذ.م.م',
        currency: AppCurrency.yer,
        capital: 1000000,
        members: const [
          CompanyMember(id: 'm', name: 'المدير', phone: '771000001', equity: 50, roles: {CompanyRole.managingPartner}),
          CompanyMember(id: 'a', name: 'أحمد', phone: '', email: 'Ahmed@mail.com', equity: 50, roles: {CompanyRole.partner}),
        ],
      );
    });

    test('شريك بالبريد فقط يدخل الشركة ويُعدّ شريكاً', () {
      expect(c.currency, AppCurrency.yer);
      final j = c.toJson();
      expect(j['partnerPhones'], contains(emailKey('ahmed@mail.com')));
      expect(j['memberPhones'], contains(emailKey('ahmed@mail.com')));
      expect(c.memberByPhone(emailKey('AHMED@mail.com'))?.id, 'a');
    });

    test('إضافة بريد لاحقاً لشريك برقم جوال تضيف مفتاحاً دون إزالة الرقم', () {
      expect(cs.setMemberEmail(c.id, 'm', 'boss@mail.com'), isNull);
      final j = c.toJson();
      expect(j['partnerPhones'], containsAll(['+967771000001', emailKey('boss@mail.com')]));
      expect(c.memberByPhone(emailKey('boss@mail.com'))?.id, 'm');
      expect(cs.setMemberEmail(c.id, 'm', 'ليس بريداً'), isNotNull);
    });
  });
}
