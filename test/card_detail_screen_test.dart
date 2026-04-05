import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultcard/src/domain/models/vault_card.dart';
import 'package:vaultcard/src/presentation/screens/card_detail_screen.dart';
import 'package:vaultcard/src/providers/providers.dart';

void main() {
  testWidgets('shows stale balance banner after refresh failures', (
    tester,
  ) async {
    final card = VaultCard(
      id: 'card-1',
      network: CardNetwork.visa,
      last4: '1111',
      expiry: '06/27',
      balance: 42.15,
      lastFetchedAt: DateTime(2026, 4, 4, 10),
      fetchFailureCount: 2,
      addedAt: DateTime(2026, 4, 1),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardsControllerProvider.overrideWith(
            () => _FakeCardsController(<VaultCard>[card]),
          ),
        ],
        child: const MaterialApp(
          home: CardDetailScreen(cardId: 'card-1'),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Balance data may be stale.'), findsOneWidget);
    expect(find.byTooltip('Refresh balance'), findsOneWidget);
  });
}

class _FakeCardsController extends CardsController {
  _FakeCardsController(this._cards);

  final List<VaultCard> _cards;

  @override
  Future<List<VaultCard>> build() async => _cards;
}
