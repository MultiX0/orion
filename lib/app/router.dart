import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/motion/route_transitions.dart';
import '../core/platform/platform_info.dart';
import '../core/storage/storage_providers.dart';
import '../features/camera/presentation/camera_screen.dart';
import '../features/conversation/presentation/conversation_screen.dart';
import '../features/harness/presentation/confirm_screen.dart';
import '../features/harness/presentation/harness_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/onboarding/presentation/bluetooth/bluetooth_pair_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/onboarding/presentation/pair_screen.dart';
import '../features/providers/presentation/provider_detail_screen.dart';
import '../features/providers/presentation/providers_screen.dart';
import '../features/settings/presentation/change_wifi_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/talk/presentation/talk_screen.dart';
import 'shell/app_shell.dart';

part 'router.g.dart';

/// Every route in the app. Screens keep their class names, so this table
/// only changes when a route is added or removed.
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final platform = ref.watch(platformInfoProvider);
  final refresh = ValueNotifier(0);
  ref.onDispose(refresh.dispose);
  ref.listen(isPairedProvider, (_, _) => refresh.value++);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final isPaired = ref.read(isPairedProvider);
      final onOnboarding = state.matchedLocation.startsWith('/onboarding');
      if (!isPaired && !onOnboarding) return '/onboarding';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) =>
            orionPage(state: state, child: const OnboardingScreen()),
        routes: [
          GoRoute(
            path: 'pair/:deviceId',
            pageBuilder: (context, state) => orionPage(
              state: state,
              child: PairScreen(deviceId: state.pathParameters['deviceId']!),
            ),
          ),
          GoRoute(
            path: 'bluetooth',
            pageBuilder: (context, state) =>
                orionPage(state: state, child: const BluetoothPairScreen()),
          ),
        ],
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) =>
                orionTabPage(state: state, child: const HomeScreen()),
          ),
          GoRoute(
            path: '/conversation',
            pageBuilder: (context, state) =>
                orionTabPage(state: state, child: const ConversationScreen()),
          ),
          GoRoute(
            path: '/camera',
            pageBuilder: (context, state) =>
                orionTabPage(state: state, child: const CameraScreen()),
          ),
          GoRoute(
            path: '/talk',
            pageBuilder: (context, state) =>
                orionTabPage(state: state, child: const TalkScreen()),
          ),
          GoRoute(
            path: '/providers',
            pageBuilder: (context, state) =>
                orionTabPage(state: state, child: const ProvidersScreen()),
            routes: [
              GoRoute(
                path: ':id',
                pageBuilder: (context, state) => orionTabPage(
                  state: state,
                  child: ProviderDetailScreen(
                    providerId: state.pathParameters['id']!,
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) =>
                orionTabPage(state: state, child: const SettingsScreen()),
            routes: [
              GoRoute(
                path: 'wifi',
                pageBuilder: (context, state) =>
                    orionTabPage(state: state, child: const ChangeWifiScreen()),
              ),
            ],
          ),
          if (platform.canHostHarness)
            GoRoute(
              path: '/harness',
              pageBuilder: (context, state) =>
                  orionTabPage(state: state, child: const HarnessScreen()),
              routes: [
                GoRoute(
                  path: 'confirm/:id',
                  pageBuilder: (context, state) => orionModalPage(
                    state: state,
                    child: ConfirmScreen(
                      confirmId: state.pathParameters['id']!,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    ],
  );
}
