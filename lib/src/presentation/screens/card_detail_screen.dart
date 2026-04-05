import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vaultcard/src/presentation/widgets/loading_placeholder.dart';
import 'package:vaultcard/src/providers/providers.dart';
import 'package:vaultcard/src/utils/card_utils.dart';

class CardDetailScreen extends ConsumerWidget {
  const CardDetailScreen({
    required this.cardId,
    super.key,
  });

  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = ref.watch(selectedCardProvider(cardId));
    final revealState = ref.watch(revealControllerProvider(cardId));
    if (card == null) {
      return const Scaffold(body: LoadingPlaceholder());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(card.displayName),
        actions: [
          IconButton(
            tooltip: 'Refresh balance',
            onPressed: () async {
              final outcome = await ref
                  .read(cardsControllerProvider.notifier)
                  .refreshCard(cardId);
              if (!context.mounted) {
                return;
              }
              final text = outcome.isCooldown
                  ? 'Refresh available again at ${formatDateTime(outcome.cooldownUntil)}'
                  : outcome.isFailure
                      ? outcome.failure!.message
                      : 'Balance refreshed';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(text)),
              );
            },
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: 'Card actions',
            onSelected: (value) async {
              if (value != 'delete') {
                return;
              }
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Remove card?'),
                  content: const Text(
                    'Are you sure you want to remove this card? This cannot be undone.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) {
                await ref
                    .read(cardsControllerProvider.notifier)
                    .deleteCard(cardId);
                if (context.mounted) {
                  context.go('/');
                }
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete Card')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (card.fetchFailureCount > 0) ...[
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  card.lastFetchedAt == null
                      ? 'Balance refresh has failed ${card.fetchFailureCount} time(s). The card has not been synced yet.'
                      : 'Balance data may be stale. Refresh has failed ${card.fetchFailureCount} time(s) since the last successful sync.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(card.network.name.toUpperCase()),
                  const SizedBox(height: 12),
                  Text(
                    card.balance == null
                        ? 'Balance unavailable'
                        : formatCurrency(card.balance!),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  Text('Expires ${card.expiry}'),
                  Text('Last updated ${formatDateTime(card.lastFetchedAt)}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sensitive Details',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _SensitiveRow(
                    label: 'Card Number',
                    value: revealState.revealedNumber ??
                        '**** **** **** ${card.last4}',
                    actionLabel: 'Reveal',
                    isBusy: revealState.isAuthenticating,
                    onPressed: () => ref
                        .read(revealControllerProvider(cardId).notifier)
                        .revealCardNumber(),
                  ),
                  const SizedBox(height: 12),
                  _SensitiveRow(
                    label: 'PIN',
                    value: revealState.revealedPin ?? '****',
                    actionLabel: 'Reveal',
                    isBusy: revealState.isAuthenticating,
                    onPressed: () => ref
                        .read(revealControllerProvider(cardId).notifier)
                        .revealPin(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Transactions',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  if (card.transactions.isEmpty)
                    const Text('No transaction history available.')
                  else
                    ...card.transactions.map(
                      (tx) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(tx.description),
                        subtitle:
                            Text(tx.date.toIso8601String().split('T').first),
                        trailing: Text(formatCurrency(tx.amount)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SensitiveRow extends StatelessWidget {
  const _SensitiveRow({
    required this.label,
    required this.value,
    required this.actionLabel,
    required this.onPressed,
    required this.isBusy,
  });

  final String label;
  final String value;
  final String actionLabel;
  final VoidCallback onPressed;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const SizedBox(height: 4),
              SelectableText(value),
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: isBusy ? null : onPressed,
          child: Text(isBusy ? 'Checking...' : actionLabel),
        ),
      ],
    );
  }
}
