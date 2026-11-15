import 'package:asis_selva_check/core/theme/app_theme.dart';
import 'package:asis_selva_check/features/auth/providers/auth_provider.dart';
import 'package:asis_selva_check/features/auth/screens/verify_email_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class VerifyAuthFake extends ChangeNotifier implements AuthProvider {
  VerifyAuthFake({required this.alreadyRequested});

  final bool alreadyRequested;
  int sends = 0;

  @override
  bool get verificationEmailRequested => alreadyRequested || sends > 0;

  @override
  String? get email => 'oscar@udla.edu.co';

  @override
  Future<String?> resendVerificationEmail() async {
    sends++;
    return null;
  }

  @override
  Future<bool> checkEmailVerified() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpVerify(WidgetTester tester, VerifyAuthFake auth) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const VerifyEmailScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('envía el correo si nadie lo había pedido (docente)', (
    tester,
  ) async {
    final auth = VerifyAuthFake(alreadyRequested: false);
    await _pumpVerify(tester, auth);
    expect(auth.sends, 1);
    expect(find.text('Te enviamos el enlace de verificación.'), findsOneWidget);
  });

  testWidgets('no lo repite tras el registro (estudiante)', (tester) async {
    final auth = VerifyAuthFake(alreadyRequested: true);
    await _pumpVerify(tester, auth);
    expect(auth.sends, 0);
  });
}
