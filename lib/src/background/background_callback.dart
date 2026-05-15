import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:vaultcard/src/data/balance/gift_card_mall_client.dart';
import 'package:vaultcard/src/data/balance/html_balance_parser.dart';
import 'package:vaultcard/src/data/config/asset_parser_config_provider.dart';
import 'package:vaultcard/src/data/repositories/local_card_repository.dart';
import 'package:vaultcard/src/data/storage/hive_card_metadata_store.dart';
import 'package:vaultcard/src/data/storage/shared_preferences_app_preferences_store.dart';
import 'package:vaultcard/src/data/storage/simple_secure_credential_store.dart';
import 'package:vaultcard/src/services/background_refresh_service.dart';
import 'package:vaultcard/src/services/balance_service.dart';
import 'package:vaultcard/src/services/connectivity_service.dart';
import 'package:vaultcard/src/services/notification_service.dart';
import 'package:vaultcard/src/services/telemetry_service.dart';
import 'package:workmanager/workmanager.dart';

@pragma('vm:entry-point')
void backgroundRefreshCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await Hive.initFlutter();
    tz.initializeTimeZones();
    final timezoneInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));

    final metadataStore = await HiveCardMetadataStore.create();
    final preferences = await SharedPreferences.getInstance();
    final appPreferencesStore = SharedPreferencesAppPreferencesStore(preferences);
    final settings = await appPreferencesStore.load();
    final notificationService = await NotificationService.create();
    final repository = LocalCardRepository(
      metadataStore: metadataStore,
      secureStore: const SimpleSecureCredentialStore(),
    );
    final balanceService = BalanceService(
      repository: repository,
      parserConfigProvider: AssetParserConfigProvider(rootBundle),
      client: const GiftCardMallClient(),
      parser: const HtmlBalanceParser(),
      connectivityService: const ConnectivityService(),
      notificationService: notificationService,
      telemetryService: const NoOpTelemetryService(),
    );

    if (task == BackgroundRefreshService.taskPrefix) {
      final cardId = inputData?['cardId'] as String?;
      if (cardId == null) {
        return false;
      }
      final outcome = await balanceService.refreshCard(
        cardId,
        ignoreCooldown: true,
        preferences: settings.notificationPreferences,
      );
      return outcome.isSuccess;
    }

    return false;
  });
}
