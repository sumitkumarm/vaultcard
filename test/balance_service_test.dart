import 'package:flutter_test/flutter_test.dart';
import 'package:vaultcard/src/data/balance/gift_card_mall_client.dart';
import 'package:vaultcard/src/data/balance/html_balance_parser.dart';
import 'package:vaultcard/src/data/config/parser_config_provider.dart';
import 'package:vaultcard/src/domain/models/balance_models.dart';
import 'package:vaultcard/src/domain/models/card_credentials.dart';
import 'package:vaultcard/src/domain/models/card_input.dart';
import 'package:vaultcard/src/domain/models/parser_config.dart';
import 'package:vaultcard/src/domain/models/settings_models.dart';
import 'package:vaultcard/src/domain/models/vault_card.dart';
import 'package:vaultcard/src/domain/repositories/card_repository.dart';
import 'package:vaultcard/src/services/balance_service.dart';
import 'package:vaultcard/src/services/connectivity_service.dart';
import 'package:vaultcard/src/services/notification_service.dart';
import 'package:vaultcard/src/services/telemetry_service.dart';

import 'test_assets.dart';

void main() {
  test('returns cooldown without making request', () async {
    final repository = _FakeCardRepository(
      card: VaultCard(
        id: '1',
        network: CardNetwork.visa,
        last4: '1111',
        expiry: '06/27',
        addedAt: DateTime(2026),
        refreshBlockedUntil: DateTime.now().add(const Duration(minutes: 5)),
      ),
      credentials: const CardCredentials(
        cardNumber: '4111111111111111',
        expiry: '06/27',
        cvv: '123',
        pin: '4567',
      ),
    );

    final service = BalanceService(
      repository: repository,
      parserConfigProvider: _FakeParserConfigProvider(),
      client: _FakeGiftCardMallClient(sampleBalanceHtml),
      parser: const HtmlBalanceParser(),
      connectivityService: const _AlwaysOnlineConnectivityService(),
      notificationService: NotificationService.noop(),
      telemetryService: const NoOpTelemetryService(),
    );

    final outcome = await service.refreshCard('1');
    expect(outcome.isCooldown, isTrue);
  });

  test('persists successful parse result', () async {
    final repository = _FakeCardRepository(
      card: VaultCard(
        id: '1',
        network: CardNetwork.visa,
        last4: '1111',
        expiry: '06/27',
        addedAt: DateTime(2026),
      ),
      credentials: const CardCredentials(
        cardNumber: '4111111111111111',
        expiry: '06/27',
        cvv: '123',
        pin: '4567',
      ),
    );

    final service = BalanceService(
      repository: repository,
      parserConfigProvider: _FakeParserConfigProvider(),
      client: _FakeGiftCardMallClient(sampleBalanceHtml),
      parser: const HtmlBalanceParser(),
      connectivityService: const _AlwaysOnlineConnectivityService(),
      notificationService: NotificationService.noop(),
      telemetryService: const NoOpTelemetryService(),
    );

    final outcome = await service.refreshCard(
      '1',
      preferences: const NotificationPreferences(),
    );

    expect(outcome.isSuccess, isTrue);
    expect(repository.card.balance, 42.15);
    expect(repository.card.transactions, hasLength(2));
  });

  test('marks failure when offline', () async {
    final repository = _FakeCardRepository(
      card: VaultCard(
        id: '1',
        network: CardNetwork.visa,
        last4: '1111',
        expiry: '06/27',
        addedAt: DateTime(2026),
      ),
      credentials: const CardCredentials(
        cardNumber: '4111111111111111',
        expiry: '06/27',
        cvv: '123',
        pin: '4567',
      ),
    );

    final service = BalanceService(
      repository: repository,
      parserConfigProvider: _FakeParserConfigProvider(),
      client: _FakeGiftCardMallClient(sampleBalanceHtml),
      parser: const HtmlBalanceParser(),
      connectivityService: const _AlwaysOfflineConnectivityService(),
      notificationService: NotificationService.noop(),
      telemetryService: const NoOpTelemetryService(),
    );

    final outcome = await service.refreshCard('1');

    expect(outcome.isFailure, isTrue);
    expect(outcome.failure!.reason, RefreshFailureReason.offline);
    expect(repository.markFailureCalled, isTrue);
  });
}

class _FakeParserConfigProvider implements ParserConfigProvider {
  @override
  Future<ParserConfig> getConfig() async {
    return const ParserConfig(
      version: 1,
      endpointUrl: 'https://example.com',
      formFields: ParserFormFields(
        cardNumber: 'cardNumber',
        expiryMonth: 'expMonth',
        expiryYear: 'expYear',
        cvv: 'cvv',
        pin: 'pin',
      ),
      balanceSelector: '.balance-amount',
      transactionSelector: 'table.transactions tbody tr',
      transactionFields: ParserTransactionFields(
        date: '.date',
        description: '.description',
        amount: '.amount',
      ),
    );
  }
}

class _FakeGiftCardMallClient extends GiftCardMallClient {
  _FakeGiftCardMallClient(this.html);

  final String html;

  @override
  Future<GiftCardMallResponse> fetchBalance({
    required ParserConfig config,
    required CardCredentials credentials,
  }) async {
    return GiftCardMallResponse(body: html, statusCode: 200);
  }
}

class _AlwaysOnlineConnectivityService extends ConnectivityService {
  const _AlwaysOnlineConnectivityService();

  @override
  Future<bool> isOnline() async => true;
}

class _AlwaysOfflineConnectivityService extends ConnectivityService {
  const _AlwaysOfflineConnectivityService();

  @override
  Future<bool> isOnline() async => false;
}

class _FakeCardRepository implements CardRepository {
  _FakeCardRepository({
    required this.card,
    required this.credentials,
  });

  VaultCard card;
  final CardCredentials credentials;
  bool markFailureCalled = false;

  @override
  Future<String> addCard(CardInput input) {
    throw UnimplementedError();
  }

  @override
  Future<void> applyBalanceResult(String id, BalanceResult result) async {
    card = card.copyWith(
      balance: result.balance,
      transactions: result.transactions,
      lastFetchedAt: result.fetchedAt,
      fetchFailureCount: 0,
      refreshBlockedUntil: result.fetchedAt.add(const Duration(minutes: 15)),
    );
  }

  @override
  Future<void> deleteCard(String id) {
    throw UnimplementedError();
  }

  @override
  Future<VaultCard?> getCard(String id) async => card.id == id ? card : null;

  @override
  Future<List<VaultCard>> getCards() async => [card];

  @override
  Future<CardCredentials> getCredentials(String id) async => credentials;

  @override
  Future<void> markRefreshFailure(String id) async {
    markFailureCalled = true;
  }

  @override
  Future<void> updateNickname(String id, String nickname) {
    throw UnimplementedError();
  }

  @override
  Future<void> updateRefreshCooldown(String id, DateTime blockedUntil) async {
    card = card.copyWith(refreshBlockedUntil: blockedUntil);
  }

  @override
  Stream<List<VaultCard>> watchCards() async* {
    yield [card];
  }
}
