import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultcard/src/data/balance/gift_card_mall_client.dart';
import 'package:vaultcard/src/data/balance/html_balance_parser.dart';
import 'package:vaultcard/src/data/config/parser_config_provider.dart';
import 'package:vaultcard/src/data/repositories/local_settings_repository.dart';
import 'package:vaultcard/src/data/storage/app_preferences_store.dart';
import 'package:vaultcard/src/data/storage/card_metadata_store.dart';
import 'package:vaultcard/src/data/storage/secure_credential_store.dart';
import 'package:vaultcard/src/domain/models/balance_models.dart';
import 'package:vaultcard/src/domain/models/card_credentials.dart';
import 'package:vaultcard/src/domain/models/card_input.dart';
import 'package:vaultcard/src/domain/models/settings_models.dart';
import 'package:vaultcard/src/domain/models/vault_card.dart';
import 'package:vaultcard/src/domain/repositories/card_repository.dart';
import 'package:vaultcard/src/domain/repositories/settings_repository.dart';
import 'package:vaultcard/src/services/app_lock_service.dart';
import 'package:vaultcard/src/services/balance_service.dart';
import 'package:vaultcard/src/services/biometric_service.dart';
import 'package:vaultcard/src/services/connectivity_service.dart';
import 'package:vaultcard/src/services/notification_service.dart';
import 'package:vaultcard/src/services/scan_service.dart';
import 'package:vaultcard/src/services/telemetry_service.dart';
import 'package:vaultcard/src/utils/card_utils.dart';

final metadataStoreProvider = Provider<CardMetadataStore>(
  (ref) => throw UnimplementedError(),
);
final secureCredentialStoreProvider = Provider<SecureCredentialStore>(
  (ref) => throw UnimplementedError(),
);
final parserConfigProviderProvider = Provider<ParserConfigProvider>(
  (ref) => throw UnimplementedError(),
);
final balanceParserProvider = Provider<HtmlBalanceParser>(
  (ref) => throw UnimplementedError(),
);
final giftCardMallClientProvider = Provider<GiftCardMallClient>(
  (ref) => throw UnimplementedError(),
);
final connectivityServiceProvider = Provider<ConnectivityService>(
  (ref) => throw UnimplementedError(),
);
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => throw UnimplementedError(),
);
final telemetryServiceProvider = Provider<TelemetryService>(
  (ref) => throw UnimplementedError(),
);
final biometricServiceProvider = Provider<BiometricService>(
  (ref) => throw UnimplementedError(),
);
final appLockServiceProvider = Provider<AppLockService>(
  (ref) => throw UnimplementedError(),
);
final scanServiceProvider = Provider<ScanService>(
  (ref) => throw UnimplementedError(),
);
final appPreferencesStoreProvider = Provider<AppPreferencesStore>(
  (ref) => throw UnimplementedError(),
);

final cardRepositoryProvider = Provider<CardRepository>(
  (ref) => throw UnimplementedError(),
);
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => LocalSettingsRepository(ref.watch(appPreferencesStoreProvider)),
);
final balanceServiceProvider = Provider<BalanceService>(
  (ref) => throw UnimplementedError(),
);

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

final cardsControllerProvider =
    AsyncNotifierProvider<CardsController, List<VaultCard>>(
  CardsController.new,
);

final sortedCardsProvider = Provider<List<VaultCard>>((ref) {
  final cards = ref.watch(cardsControllerProvider).valueOrNull ?? const [];
  final settings = ref.watch(settingsControllerProvider).valueOrNull ??
      const AppSettings();
  return sortCards(cards, settings.sortOption);
});

final selectedCardProvider = Provider.family<VaultCard?, String>((ref, id) {
  final cards = ref.watch(cardsControllerProvider).valueOrNull ?? const [];
  for (final card in cards) {
    if (card.id == id) {
      return card;
    }
  }
  return null;
});

final revealControllerProvider =
    AutoDisposeNotifierProviderFamily<RevealController, RevealState, String>(
  RevealController.new,
);

class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() {
    return ref.watch(settingsRepositoryProvider).getSettings();
  }

  Future<void> completeOnboarding() async {
    await ref.watch(settingsRepositoryProvider).setOnboardingCompleted();
    state = AsyncData((await future).copyWith(onboardingCompleted: true));
  }

  Future<void> setAppLockEnabled(bool enabled) async {
    await ref.watch(settingsRepositoryProvider).setAppLockEnabled(enabled);
    final current = await future;
    state = AsyncData(current.copyWith(appLockEnabled: enabled));
  }

  Future<void> setAnalyticsEnabled(bool enabled) async {
    await ref.watch(settingsRepositoryProvider).setAnalyticsEnabled(enabled);
    final current = await future;
    state = AsyncData(current.copyWith(analyticsEnabled: enabled));
  }

  Future<void> setSortOption(CardSortOption option) async {
    await ref.watch(settingsRepositoryProvider).setSortOption(option);
    final current = await future;
    state = AsyncData(current.copyWith(sortOption: option));
  }

  Future<void> updateNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    await ref
        .watch(settingsRepositoryProvider)
        .setNotificationPreferences(preferences);
    final current = await future;
    state = AsyncData(current.copyWith(notificationPreferences: preferences));
  }
}

class CardsController extends AsyncNotifier<List<VaultCard>> {
  StreamSubscription<List<VaultCard>>? _subscription;

  @override
  Future<List<VaultCard>> build() async {
    final repository = ref.watch(cardRepositoryProvider);
    _subscription?.cancel();
    _subscription = repository.watchCards().listen((cards) {
      state = AsyncData(cards);
    });
    ref.onDispose(() => _subscription?.cancel());
    return repository.getCards();
  }

  Future<String> addCard(CardInput input) async {
    final repository = ref.watch(cardRepositoryProvider);
    final id = await repository.addCard(input);
    state = AsyncData(await repository.getCards());
    return id;
  }

  Future<void> updateNickname(String id, String nickname) async {
    final repository = ref.watch(cardRepositoryProvider);
    await repository.updateNickname(id, nickname);
    state = AsyncData(await repository.getCards());
  }

  Future<void> deleteCard(String id) async {
    final repository = ref.watch(cardRepositoryProvider);
    await repository.deleteCard(id);
    state = AsyncData(await repository.getCards());
  }

  Future<RefreshOutcome> refreshCard(String id) async {
    final service = ref.watch(balanceServiceProvider);
    final settings =
        ref.watch(settingsControllerProvider).valueOrNull ?? const AppSettings();
    final outcome = await service.refreshCard(
      id,
      preferences: settings.notificationPreferences,
    );
    state = AsyncData(await ref.watch(cardRepositoryProvider).getCards());
    return outcome;
  }

  Future<CardCredentials> getCredentials(String id) {
    return ref.watch(cardRepositoryProvider).getCredentials(id);
  }
}

class RevealState {
  const RevealState({
    this.revealedNumber,
    this.revealedPin,
    this.isAuthenticating = false,
  });

  final String? revealedNumber;
  final String? revealedPin;
  final bool isAuthenticating;

  RevealState copyWith({
    String? revealedNumber,
    String? revealedPin,
    bool? isAuthenticating,
  }) {
    return RevealState(
      revealedNumber: revealedNumber ?? this.revealedNumber,
      revealedPin: revealedPin ?? this.revealedPin,
      isAuthenticating: isAuthenticating ?? this.isAuthenticating,
    );
  }
}

class RevealController extends AutoDisposeFamilyNotifier<RevealState, String> {
  Timer? _timer;
  late final String _cardId;

  @override
  RevealState build(String arg) {
    _cardId = arg;
    ref.onDispose(() => _timer?.cancel());
    return const RevealState();
  }

  Future<void> revealCardNumber() async {
    await _reveal(showNumber: true);
  }

  Future<void> revealPin() async {
    await _reveal(showPin: true);
  }

  Future<void> _reveal({bool showNumber = false, bool showPin = false}) async {
    state = state.copyWith(isAuthenticating: true);
    final authenticated = await ref
        .watch(biometricServiceProvider)
        .authenticate('Reveal sensitive card details');
    if (!authenticated) {
      state = state.copyWith(isAuthenticating: false);
      return;
    }
    final credentials =
        await ref.watch(cardRepositoryProvider).getCredentials(_cardId);
    state = RevealState(
      revealedNumber: showNumber ? credentials.cardNumber : state.revealedNumber,
      revealedPin: showPin ? credentials.pin : state.revealedPin,
      isAuthenticating: false,
    );
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 30), () {
      state = const RevealState();
    });
  }
}
