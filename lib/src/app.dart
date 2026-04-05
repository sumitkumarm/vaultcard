import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vaultcard/src/navigation/app_router.dart';
import 'package:vaultcard/src/providers/providers.dart';
import 'package:vaultcard/src/theme/app_theme.dart';

class VaultCardApp extends ConsumerStatefulWidget {
  const VaultCardApp({super.key});

  @override
  ConsumerState<VaultCardApp> createState() => _VaultCardAppState();
}

class _VaultCardAppState extends ConsumerState<VaultCardApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(appLockServiceProvider).enableSecureDisplay();
      await ref.read(appLockControllerProvider.notifier).unlockIfNeeded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      ref.read(appLockControllerProvider.notifier).lock();
    }
    if (state == AppLifecycleState.resumed) {
      ref.read(appLockControllerProvider.notifier).unlockIfNeeded();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final appLockState = ref.watch(appLockControllerProvider);
    return MaterialApp.router(
      title: 'VaultCard',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            if (appLockState.isLocked)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.lock_outline, size: 56),
                              const SizedBox(height: 16),
                              Text(
                                'VaultCard is locked',
                                style: Theme.of(context).textTheme.titleLarge,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Authenticate with biometrics or device passcode to continue.',
                                style: Theme.of(context).textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: appLockState.isAuthenticating
                                    ? null
                                    : () => ref
                                        .read(appLockControllerProvider.notifier)
                                        .unlockIfNeeded(),
                                child: Text(
                                  appLockState.isAuthenticating
                                      ? 'Unlocking...'
                                      : 'Unlock',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
