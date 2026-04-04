import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vaultcard/src/presentation/screens/add_card_screen.dart';
import 'package:vaultcard/src/presentation/screens/card_detail_screen.dart';
import 'package:vaultcard/src/presentation/screens/card_entry_form_screen.dart';
import 'package:vaultcard/src/presentation/screens/card_list_screen.dart';
import 'package:vaultcard/src/presentation/screens/onboarding_screen.dart';
import 'package:vaultcard/src/presentation/screens/scan_card_screen.dart';
import 'package:vaultcard/src/presentation/screens/settings_screen.dart';
import 'package:vaultcard/src/providers/providers.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final settings = ref.watch(settingsControllerProvider).valueOrNull;
  final onboardingCompleted = settings?.onboardingCompleted ?? false;
  return GoRouter(
    initialLocation: onboardingCompleted ? '/' : '/onboarding',
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const CardListScreen(),
      ),
      GoRoute(
        path: '/add',
        builder: (context, state) => const AddCardScreen(),
      ),
      GoRoute(
        path: '/add/form',
        builder: (context, state) {
          final extra = state.extra is Map<String, String>
              ? state.extra! as Map<String, String>
              : const <String, String>{};
          return CardEntryFormScreen(prefill: extra);
        },
      ),
      GoRoute(
        path: '/scan',
        builder: (context, state) => const ScanCardScreen(),
      ),
      GoRoute(
        path: '/card/:id',
        builder: (context, state) => CardDetailScreen(
          cardId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
    redirect: (context, state) {
      final goingToOnboarding = state.uri.path == '/onboarding';
      if (!onboardingCompleted && !goingToOnboarding) {
        return '/onboarding';
      }
      if (onboardingCompleted && goingToOnboarding) {
        return '/';
      }
      return null;
    },
  );
});
