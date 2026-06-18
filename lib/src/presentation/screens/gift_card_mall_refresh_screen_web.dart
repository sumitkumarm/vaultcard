import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultcard/src/presentation/widgets/loading_placeholder.dart';
import 'package:vaultcard/src/providers/providers.dart';
import 'package:vaultcard/src/services/gift_card_mall_browser_bridge.dart';

class GiftCardMallRefreshScreen extends ConsumerWidget {
  const GiftCardMallRefreshScreen({
    required this.cardId,
    super.key,
  });

  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = ref.watch(selectedCardProvider(cardId));
    if (card == null) {
      return const Scaffold(body: LoadingPlaceholder());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('GiftCardMall Refresh')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(card.displayName, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          const Text(
            'Web QA mode does not embed GiftCardMall because Flutter Web cannot use the native WebView bridge.',
          ),
          const SizedBox(height: 16),
          const SelectableText(GiftCardMallBrowserBridge.siteUrl),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'QA coverage here',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                      'Card creation, validation, storage, reveal, and detail navigation are covered in web.'),
                  const Text(
                      'GiftCardMall WebView/autofill remains an Android/iOS/Appetize test.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
