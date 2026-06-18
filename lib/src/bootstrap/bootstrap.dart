import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vaultcard/src/data/balance/gift_card_mall_client.dart';
import 'package:vaultcard/src/data/balance/html_balance_parser.dart';
import 'package:vaultcard/src/data/config/asset_parser_config_provider.dart';
import 'package:vaultcard/src/data/repositories/local_card_repository.dart';
import 'package:vaultcard/src/data/storage/app_preferences_store.dart';
import 'package:vaultcard/src/data/storage/card_metadata_store.dart';
import 'package:vaultcard/src/data/storage/hive_card_metadata_store.dart';
import 'package:vaultcard/src/data/storage/in_memory_app_preferences_store.dart';
import 'package:vaultcard/src/data/storage/in_memory_card_metadata_store.dart';
import 'package:vaultcard/src/data/storage/in_memory_secure_credential_store.dart';
import 'package:vaultcard/src/data/storage/secure_credential_store.dart';
import 'package:vaultcard/src/data/storage/shared_preferences_app_preferences_store.dart';
import 'package:vaultcard/src/data/storage/simple_secure_credential_store.dart';
import 'package:vaultcard/src/domain/models/settings_models.dart';
import 'package:vaultcard/src/providers/providers.dart';
import 'package:vaultcard/src/services/app_lock_service.dart';
import 'package:vaultcard/src/services/background_refresh_service.dart';
import 'package:vaultcard/src/services/balance_service.dart';
import 'package:vaultcard/src/services/biometric_service.dart';
import 'package:vaultcard/src/services/connectivity_service.dart';
import 'package:vaultcard/src/services/notification_service.dart';
import 'package:vaultcard/src/services/scan_service.dart';
import 'package:vaultcard/src/services/telemetry_service.dart';

class Bootstrap {
  const Bootstrap(this.overrides, this.backgroundRefreshService);

  final List<Override> overrides;
  final BackgroundRefreshService backgroundRefreshService;

  static const bool isQaMode = bool.fromEnvironment('VAULTCARD_QA');

  static Future<Bootstrap> create(SharedPreferences preferences) async {
    final CardMetadataStore metadataStore = isQaMode
        ? InMemoryCardMetadataStore()
        : await HiveCardMetadataStore.create();
    final SecureCredentialStore secureStore = isQaMode
        ? InMemorySecureCredentialStore()
        : const SimpleSecureCredentialStore();
    final AppPreferencesStore appPreferencesStore = isQaMode
        ? InMemoryAppPreferencesStore(
            const AppSettings(onboardingCompleted: true),
          )
        : SharedPreferencesAppPreferencesStore(preferences);
    final notificationService = await NotificationService.create();
    const backgroundRefreshService = BackgroundRefreshService();
    return Bootstrap(
      [
        metadataStoreProvider.overrideWithValue(metadataStore),
        secureCredentialStoreProvider.overrideWithValue(secureStore),
        parserConfigProviderProvider.overrideWithValue(
          AssetParserConfigProvider(rootBundle),
        ),
        balanceParserProvider.overrideWithValue(const HtmlBalanceParser()),
        giftCardMallClientProvider
            .overrideWithValue(const GiftCardMallClient()),
        connectivityServiceProvider.overrideWithValue(
          const ConnectivityService(),
        ),
        telemetryServiceProvider.overrideWithValue(
          const NoOpTelemetryService(),
        ),
        notificationServiceProvider.overrideWithValue(notificationService),
        backgroundRefreshServiceProvider.overrideWithValue(
          backgroundRefreshService,
        ),
        biometricServiceProvider.overrideWithValue(
          const BiometricService(),
        ),
        appLockServiceProvider.overrideWithValue(AppLockService()),
        scanServiceProvider.overrideWithValue(
          const ScanService(),
        ),
        appPreferencesStoreProvider.overrideWithValue(appPreferencesStore),
        cardRepositoryProvider.overrideWith(
          (ref) => LocalCardRepository(
            metadataStore: ref.watch(metadataStoreProvider),
            secureStore: ref.watch(secureCredentialStoreProvider),
          ),
        ),
        balanceServiceProvider.overrideWith(
          (ref) => BalanceService(
            repository: ref.watch(cardRepositoryProvider),
            parserConfigProvider: ref.watch(parserConfigProviderProvider),
            client: ref.watch(giftCardMallClientProvider),
            parser: ref.watch(balanceParserProvider),
            connectivityService: ref.watch(connectivityServiceProvider),
            notificationService: ref.watch(notificationServiceProvider),
            telemetryService: ref.watch(telemetryServiceProvider),
          ),
        ),
      ],
      backgroundRefreshService,
    );
  }
}
