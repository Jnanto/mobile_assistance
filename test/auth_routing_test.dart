import 'package:asis_selva_check/core/router/app_router.dart';
import 'package:asis_selva_check/data/models/app_user.dart';
import 'package:asis_selva_check/features/auth/providers/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('redirectFor', () {
    test('sin sesión solo permite las rutas públicas', () {
      expect(redirectFor(AuthStatus.signedOut, Routes.login), isNull);
      expect(redirectFor(AuthStatus.signedOut, Routes.register), isNull);
      expect(redirectFor(AuthStatus.signedOut, Routes.forgotPassword), isNull);
      expect(
        redirectFor(AuthStatus.signedOut, Routes.teacherHome),
        Routes.login,
      );
    });

    test('correo sin verificar va a la verificación', () {
      expect(
        redirectFor(AuthStatus.emailNotVerified, Routes.login),
        Routes.verifyEmail,
      );
      expect(
        redirectFor(AuthStatus.emailNotVerified, Routes.verifyEmail),
        isNull,
      );
    });

    test('cada rol queda en su sección', () {
      expect(
        redirectFor(AuthStatus.teacher, Routes.studentHome),
        Routes.teacherHome,
      );
      expect(
        redirectFor(AuthStatus.student, Routes.teacherHome),
        Routes.studentHome,
      );
      expect(
        redirectFor(AuthStatus.student, '${Routes.studentHome}/x'),
        isNull,
      );
    });

    test('estudiante sin vincular va a la vinculación', () {
      expect(
        redirectFor(AuthStatus.needsLink, Routes.studentHome),
        Routes.linkAccount,
      );
    });
  });

  group('AppUser', () {
    test('lee un perfil de estudiante', () {
      final user = AppUser.fromMap('uid1', {
        'nombre': 'Laura Sofía Méndez',
        'email': 'lmendez@udla.edu.co',
        'rol': 'estudiante',
        'codigo': '20231145028',
        'vinculado': true,
      });
      expect(user.role, UserRole.student);
      expect(user.linked, isTrue);
      expect(user.firstName, 'Laura');
    });

    test('un rol desconocido se trata como estudiante', () {
      final user = AppUser.fromMap('uid2', {'rol': 'admin'});
      expect(user.role, UserRole.student);
      expect(user.linked, isFalse);
    });

    test('reconoce al docente', () {
      expect(UserRole.fromValue('docente'), UserRole.teacher);
    });
  });
}
