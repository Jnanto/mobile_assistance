import 'package:asis_selva_check/core/utils/formatters.dart';
import 'package:asis_selva_check/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Validators.institutionalEmail', () {
    test('acepta el dominio institucional sin importar mayúsculas', () {
      expect(Validators.institutionalEmail(' LMendez@UDLA.edu.co '), isNull);
    });

    test('rechaza otros dominios y correos mal formados', () {
      expect(Validators.institutionalEmail('lmendez@gmail.com'), isNotNull);
      expect(
        Validators.institutionalEmail('lmendez@udla.edu.co.fake.com'),
        isNotNull,
      );
      expect(Validators.institutionalEmail('lmendez'), isNotNull);
      expect(Validators.institutionalEmail(''), isNotNull);
    });
  });

  group('Validators.newPassword', () {
    test('exige 8 caracteres, una mayúscula y un número', () {
      expect(Validators.newPassword('Corta1'), isNotNull);
      expect(Validators.newPassword('sinmayuscula1'), isNotNull);
      expect(Validators.newPassword('SinNumeroAqui'), isNotNull);
      expect(Validators.newPassword('Valida123'), isNull);
    });

    test('passwordScore cuenta los requisitos cumplidos', () {
      expect(Validators.passwordScore(''), 0);
      expect(Validators.passwordScore('abcdefgh'), 1);
      expect(Validators.passwordScore('Abcdefgh'), 2);
      expect(Validators.passwordScore('Abcdefg1'), 3);
    });
  });

  test('Validators.confirmPassword', () {
    expect(Validators.confirmPassword('Valida123', 'Valida123'), isNull);
    expect(Validators.confirmPassword('Otra1234', 'Valida123'), isNotNull);
    expect(Validators.confirmPassword('', 'Valida123'), isNotNull);
  });

  test('Validators.studentCode solo admite de 6 a 12 dígitos', () {
    expect(Validators.studentCode('20231145028'), isNull);
    expect(Validators.studentCode('2023A'), isNotNull);
    expect(Validators.studentCode('12345'), isNotNull);
    expect(Validators.studentCode('1234567890123'), isNotNull);
  });

  test('Validators.fullName exige nombre y apellido', () {
    expect(Validators.fullName('Laura Méndez'), isNull);
    expect(Validators.fullName('Laura'), isNotNull);
    expect(Validators.fullName('   '), isNotNull);
  });

  test('Formatters', () {
    expect(Formatters.maskEmail('lmendez@udla.edu.co'), 'l•••@udla.edu.co');
    expect(Formatters.mmss(65), '01:05');
    expect(Formatters.mmss(-3), '00:00');
  });
}
