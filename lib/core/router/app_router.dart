import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/link_account_screen.dart';
import '../../features/auth/screens/loading_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/verify_email_screen.dart';
import '../../features/student/screens/attendance_result_screen.dart';
import '../../features/student/screens/mark_attendance_screen.dart';
import '../../features/student/screens/student_home_screen.dart';
import '../../features/teacher/screens/course_detail_screen.dart';
import '../../features/teacher/screens/course_form_screen.dart';
import '../../features/teacher/screens/course_report_screen.dart';
import '../../features/teacher/screens/course_students_screen.dart';
import '../../features/teacher/screens/live_class_screen.dart';
import '../../features/teacher/screens/start_class_screen.dart';
import '../../features/teacher/screens/student_file_screen.dart';
import '../../features/teacher/screens/teacher_home_screen.dart';

abstract final class Routes {
  static const loading = '/cargando';
  static const login = '/login';
  static const register = '/registro';
  static const forgotPassword = '/recuperar';
  static const verifyEmail = '/verificar-correo';
  static const linkAccount = '/vincular';
  static const teacherHome = '/docente';
  static const studentHome = '/estudiante';

  static const newCourse = '$teacherHome/cursos/nuevo';
  static String courseDetail(String id) => '$teacherHome/cursos/$id';
  static String editCourse(String id) => '${courseDetail(id)}/editar';
  static String courseStudents(String id) => '${courseDetail(id)}/estudiantes';
  static String startClass(String id) => '${courseDetail(id)}/iniciar';
  static String courseReport(String id) => '${courseDetail(id)}/reporte';
  static String studentFile(String courseId, String email) =>
      '${courseStudents(courseId)}/${Uri.encodeComponent(email)}';
  static String liveClass(String sessionId) => '$teacherHome/clase/$sessionId';
  static String markAttendance(String sessionId) =>
      '$studentHome/clase/$sessionId';
  static String attendanceResult(String sessionId) =>
      '${markAttendance(sessionId)}/resultado';

  static const publicRoutes = {login, register, forgotPassword};
}

/// Decide a dónde redirigir según el estado de autenticación.
/// Devuelve `null` si la ubicación actual es válida.
String? redirectFor(AuthStatus status, String location) {
  String? goTo(String target) => location == target ? null : target;

  switch (status) {
    case AuthStatus.loading:
      return goTo(Routes.loading);
    case AuthStatus.signedOut:
      return Routes.publicRoutes.contains(location) ? null : Routes.login;
    case AuthStatus.emailNotVerified:
      return goTo(Routes.verifyEmail);
    case AuthStatus.needsLink:
      return goTo(Routes.linkAccount);
    case AuthStatus.teacher:
      return location.startsWith(Routes.teacherHome)
          ? null
          : Routes.teacherHome;
    case AuthStatus.student:
      return location.startsWith(Routes.studentHome)
          ? null
          : Routes.studentHome;
  }
}

GoRouter createRouter(AuthProvider auth) => GoRouter(
  initialLocation: Routes.loading,
  refreshListenable: auth,
  redirect: (context, state) => redirectFor(auth.status, state.matchedLocation),
  routes: [
    GoRoute(
      path: Routes.loading,
      builder: (context, state) => const LoadingScreen(),
    ),
    GoRoute(
      path: Routes.login,
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: Routes.register,
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: Routes.forgotPassword,
      builder: (context, state) => const ForgotPasswordScreen(),
    ),
    GoRoute(
      path: Routes.verifyEmail,
      builder: (context, state) => const VerifyEmailScreen(),
    ),
    GoRoute(
      path: Routes.linkAccount,
      builder: (context, state) => const LinkAccountScreen(),
    ),
    GoRoute(
      path: Routes.teacherHome,
      builder: (context, state) => const TeacherHomeScreen(),
      routes: [
        GoRoute(
          path: 'cursos/nuevo',
          builder: (context, state) => const CourseFormScreen(),
        ),
        GoRoute(
          path: 'cursos/:courseId',
          builder: (context, state) =>
              CourseDetailScreen(courseId: state.pathParameters['courseId']!),
          routes: [
            GoRoute(
              path: 'editar',
              builder: (context, state) =>
                  CourseFormScreen(courseId: state.pathParameters['courseId']!),
            ),
            GoRoute(
              path: 'estudiantes',
              builder: (context, state) => CourseStudentsScreen(
                courseId: state.pathParameters['courseId']!,
              ),
              routes: [
                GoRoute(
                  path: ':email',
                  builder: (context, state) => StudentFileScreen(
                    courseId: state.pathParameters['courseId']!,
                    email: state.pathParameters['email']!,
                  ),
                ),
              ],
            ),
            GoRoute(
              path: 'reporte',
              builder: (context, state) => CourseReportScreen(
                courseId: state.pathParameters['courseId']!,
              ),
            ),
            GoRoute(
              path: 'iniciar',
              builder: (context, state) =>
                  StartClassScreen(courseId: state.pathParameters['courseId']!),
            ),
          ],
        ),
        GoRoute(
          path: 'clase/:sessionId',
          builder: (context, state) =>
              LiveClassScreen(sessionId: state.pathParameters['sessionId']!),
        ),
      ],
    ),
    GoRoute(
      path: Routes.studentHome,
      builder: (context, state) => const StudentHomeScreen(),
      routes: [
        GoRoute(
          path: 'clase/:sessionId',
          builder: (context, state) => MarkAttendanceScreen(
            sessionId: state.pathParameters['sessionId']!,
          ),
          routes: [
            GoRoute(
              path: 'resultado',
              builder: (context, state) => AttendanceResultScreen(
                sessionId: state.pathParameters['sessionId']!,
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);
