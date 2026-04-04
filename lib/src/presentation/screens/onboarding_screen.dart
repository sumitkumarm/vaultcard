import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vaultcard/src/providers/providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _pageIndex = 0;

  static const _pages = [
    (
      title: 'Track every gift card in one place',
      body:
          'VaultCard keeps prepaid Visa and Mastercard gift cards organized on-device only.',
    ),
    (
      title: 'Balances stay easy to check',
      body:
          'Refresh card balances and recent transactions without calling support lines or juggling receipts.',
    ),
    (
      title: 'Sensitive details stay protected',
      body:
          'Card credentials remain encrypted on-device and require biometrics before reveal.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isLast = _pageIndex == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (value) => setState(() => _pageIndex = value),
                  itemCount: _pages.length,
                  itemBuilder: (context, index) {
                    final page = _pages[index];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_person_outlined,
                          size: 84,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          page.title,
                          style: Theme.of(context).textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          page.body,
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    );
                  },
                ),
              ),
              Row(
                children: List.generate(
                  _pages.length,
                  (index) => Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 4,
                      decoration: BoxDecoration(
                        color: index == _pageIndex
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    if (!isLast) {
                      await _pageController.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      );
                      return;
                    }
                    await ref
                        .read(settingsControllerProvider.notifier)
                        .completeOnboarding();
                    if (context.mounted) {
                      context.go('/');
                    }
                  },
                  child: Text(isLast ? 'Get Started' : 'Next'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
