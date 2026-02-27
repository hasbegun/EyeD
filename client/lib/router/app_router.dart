import 'package:go_router/go_router.dart';

import '../screens/admin_screen.dart';
import '../screens/analysis_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/devices_screen.dart';
import '../screens/enrollment_screen.dart';
import '../screens/history_screen.dart';
import '../screens/not_found_screen.dart';
import '../widgets/shell_scaffold.dart';

final appRouter = GoRouter(
  initialLocation: '/dashboard',
  errorBuilder: (context, state) => const ShellScaffold(
    child: NotFoundScreen(),
  ),
  routes: [
    ShellRoute(
      builder: (context, state, child) => ShellScaffold(child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (_, __) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/devices',
          builder: (_, __) => const DevicesScreen(),
        ),
        GoRoute(
          path: '/enrollment',
          builder: (_, __) => const EnrollmentScreen(),
        ),
        GoRoute(
          path: '/analysis',
          builder: (_, __) => const AnalysisScreen(),
        ),
        GoRoute(
          path: '/history',
          builder: (_, __) => const HistoryScreen(),
        ),
        GoRoute(
          path: '/admin',
          builder: (_, __) => const AdminScreen(),
        ),
      ],
    ),
  ],
);
