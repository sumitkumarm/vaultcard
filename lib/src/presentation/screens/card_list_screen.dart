import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vaultcard/src/domain/models/vault_card.dart';
import 'package:vaultcard/src/presentation/widgets/card_tile.dart';
import 'package:vaultcard/src/presentation/widgets/empty_state.dart';
import 'package:vaultcard/src/presentation/widgets/loading_placeholder.dart';
import 'package:vaultcard/src/presentation/widgets/section_header.dart';
import 'package:vaultcard/src/providers/providers.dart';

class CardListScreen extends ConsumerWidget {
  const CardListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsState = ref.watch(cardsControllerProvider);
    final cards = ref.watch(sortedCardsProvider);
    final settings = ref.watch(settingsControllerProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('VaultCard'),
        actions: [
          PopupMenuButton<CardSortOption>(
            tooltip: 'Sort cards',
            onSelected: (value) {
              ref.read(settingsControllerProvider.notifier).setSortOption(value);
            },
            itemBuilder: (context) => CardSortOption.values
                .map(
                  (option) => PopupMenuItem(
                    value: option,
                    child: Text(_sortLabel(option)),
                  ),
                )
                .toList(),
            icon: const Icon(Icons.sort),
          ),
          IconButton(
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/add'),
        label: const Text('Add Card'),
        icon: const Icon(Icons.add),
      ),
      body: cardsState.when(
        data: (_) {
          if (cards.isEmpty) {
            return EmptyState(
              title: 'No cards yet',
              body:
                  'Add your first prepaid gift card to start tracking balances and expiry dates.',
              actionLabel: 'Add Your First Card',
              onAction: () => context.push('/add'),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              for (final card in cards) {
                await ref.read(cardsControllerProvider.notifier).refreshCard(card.id);
              }
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(24),
              itemCount: cards.length + 1,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return SectionHeader(
                    'Your Cards',
                    trailing: Text(
                      _sortLabel(
                        settings?.sortOption ?? CardSortOption.dateAddedNewest,
                      ),
                    ),
                  );
                }
                final card = cards[index - 1];
                return CardTile(
                  card: card,
                  onTap: () => context.push('/card/${card.id}'),
                );
              },
            ),
          );
        },
        error: (error, stackTrace) =>
            Center(child: Text('Failed to load cards: $error')),
        loading: LoadingPlaceholder.new,
      ),
    );
  }

  static String _sortLabel(CardSortOption option) {
    switch (option) {
      case CardSortOption.dateAddedNewest:
        return 'Newest';
      case CardSortOption.balanceLowToHigh:
        return 'Balance Low-High';
      case CardSortOption.balanceHighToLow:
        return 'Balance High-Low';
      case CardSortOption.expirySoonest:
        return 'Expiry Soonest';
    }
  }
}
