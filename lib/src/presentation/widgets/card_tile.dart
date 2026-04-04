import 'package:flutter/material.dart';
import 'package:vaultcard/src/domain/models/vault_card.dart';
import 'package:vaultcard/src/utils/card_utils.dart';

class CardTile extends StatelessWidget {
  const CardTile({
    required this.card,
    required this.onTap,
    super.key,
  });

  final VaultCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Chip(label: Text(card.network.name.toUpperCase())),
                  const Spacer(),
                  Text(card.expiry, style: theme.textTheme.bodyMedium),
                ],
              ),
              const SizedBox(height: 16),
              Text(card.displayName, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                card.balance == null
                    ? 'Balance unavailable'
                    : formatCurrency(card.balance!),
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'Last updated ${formatDateTime(card.lastFetchedAt)}',
                style: theme.textTheme.bodyMedium,
              ),
              if (card.fetchFailureCount > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'Refresh issues detected',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
