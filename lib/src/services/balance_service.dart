import 'package:vaultcard/src/data/balance/gift_card_mall_client.dart';
import 'package:vaultcard/src/data/balance/html_balance_parser.dart';
import 'package:vaultcard/src/data/config/parser_config_provider.dart';
import 'package:vaultcard/src/domain/models/balance_models.dart';
import 'package:vaultcard/src/domain/models/settings_models.dart';
import 'package:vaultcard/src/domain/repositories/card_repository.dart';
import 'package:vaultcard/src/services/connectivity_service.dart';
import 'package:vaultcard/src/services/notification_service.dart';
import 'package:vaultcard/src/services/telemetry_service.dart';

class BalanceService {
  const BalanceService({
    required CardRepository repository,
    required ParserConfigProvider parserConfigProvider,
    required GiftCardMallClient client,
    required HtmlBalanceParser parser,
    required ConnectivityService connectivityService,
    required NotificationService notificationService,
    required TelemetryService telemetryService,
  })  : _repository = repository,
        _parserConfigProvider = parserConfigProvider,
        _client = client,
        _parser = parser,
        _connectivityService = connectivityService,
        _notificationService = notificationService,
        _telemetryService = telemetryService;

  final CardRepository _repository;
  final ParserConfigProvider _parserConfigProvider;
  final GiftCardMallClient _client;
  final HtmlBalanceParser _parser;
  final ConnectivityService _connectivityService;
  final NotificationService _notificationService;
  final TelemetryService _telemetryService;

  Future<RefreshOutcome> refreshCard(
    String cardId, {
    bool ignoreCooldown = false,
    NotificationPreferences preferences = const NotificationPreferences(),
  }) async {
    final card = await _repository.getCard(cardId);
    if (card == null) {
      return const RefreshOutcome.failure(
        RefreshFailure(
          reason: RefreshFailureReason.unknown,
          message: 'Card not found',
        ),
      );
    }

    if (!ignoreCooldown &&
        card.refreshBlockedUntil != null &&
        card.refreshBlockedUntil!.isAfter(DateTime.now())) {
      return RefreshOutcome.cooldown(card.refreshBlockedUntil!);
    }

    final isOnline = await _connectivityService.isOnline();
    if (!isOnline) {
      await _repository.markRefreshFailure(cardId);
      return const RefreshOutcome.failure(
        RefreshFailure(
          reason: RefreshFailureReason.offline,
          message: 'No network connection available.',
        ),
      );
    }

    try {
      final config = await _parserConfigProvider.getConfig();
      final credentials = await _repository.getCredentials(cardId);
      final response = await _client.fetchBalance(
        config: config,
        credentials: credentials,
      );
      final result = _parser.parse(response.body, config);
      await _repository.applyBalanceResult(cardId, result);
      final updated = await _repository.getCard(cardId);
      if (updated != null) {
        await _notificationService.syncForCard(updated, preferences);
      }
      await _telemetryService.track(
        'balance_refresh_succeeded',
        <String, Object?>{'cardId': cardId},
      );
      return RefreshOutcome.success(result);
    } on GiftCardMallBotProtectionException catch (error) {
      await _repository.markRefreshFailure(cardId);
      await _repository.updateRefreshCooldown(
        cardId,
        DateTime.now().add(const Duration(days: 1)),
      );
      await _telemetryService.track(
        'balance_refresh_failed',
        <String, Object?>{'reason': 'bot_protection', 'error': error.message},
      );
      return const RefreshOutcome.failure(
        RefreshFailure(
          reason: RefreshFailureReason.botProtection,
          message:
              'GiftCardMall is blocking automated balance checks right now.',
        ),
      );
    } on FormatException catch (error) {
      await _repository.markRefreshFailure(cardId);
      await _telemetryService.track(
        'balance_refresh_failed',
        <String, Object?>{'reason': 'parse_error', 'error': error.message},
      );
      return const RefreshOutcome.failure(
        RefreshFailure(
          reason: RefreshFailureReason.parseError,
          message: 'Unable to parse balance response.',
        ),
      );
    } catch (_) {
      await _repository.markRefreshFailure(cardId);
      await _telemetryService.track(
        'balance_refresh_failed',
        <String, Object?>{'reason': 'network'},
      );
      return const RefreshOutcome.failure(
        RefreshFailure(
          reason: RefreshFailureReason.network,
          message: 'Balance refresh failed.',
        ),
      );
    }
  }
}
