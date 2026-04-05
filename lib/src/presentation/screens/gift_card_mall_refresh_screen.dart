import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultcard/src/presentation/widgets/loading_placeholder.dart';
import 'package:vaultcard/src/providers/providers.dart';
import 'package:vaultcard/src/services/gift_card_mall_browser_bridge.dart';
import 'package:webview_flutter/webview_flutter.dart';

class GiftCardMallRefreshScreen extends ConsumerStatefulWidget {
  const GiftCardMallRefreshScreen({
    required this.cardId,
    super.key,
  });

  final String cardId;

  @override
  ConsumerState<GiftCardMallRefreshScreen> createState() =>
      _GiftCardMallRefreshScreenState();
}

class _GiftCardMallRefreshScreenState
    extends ConsumerState<GiftCardMallRefreshScreen> {
  final _bridge = const GiftCardMallBrowserBridge();
  late final WebViewController _controller;
  GiftCardMallSummaryCapture? _summary;
  bool _isLoading = true;
  bool _isAutofilling = false;
  bool _isSyncing = false;
  String _status =
      'Clear the anti-bot challenge if prompted, then use secure autofill and submit the form inside GiftCardMall.';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            setState(() => _isLoading = false);
            await _controller.runJavaScript(_bridge.installScript());
          },
        ),
      )
      ..addJavaScriptChannel(
        GiftCardMallBrowserBridge.channelName,
        onMessageReceived: _onBridgeMessage,
      )
      ..loadRequest(Uri.parse(GiftCardMallBrowserBridge.siteUrl));
  }

  Future<void> _onBridgeMessage(JavaScriptMessage message) async {
    if (!mounted) {
      return;
    }

    final summary = _bridge.parseSummaryCapture(message.message);
    if (summary != null) {
      setState(() {
        _summary = summary;
        _status = _bridge.formatSummaryStatus(summary);
        _isSyncing = true;
      });
      if (summary.accessToken.isNotEmpty && summary.rmsSessionId.isNotEmpty) {
        await _controller.runJavaScript(
          _bridge.buildTransactionsFetchScript(
            token: summary.accessToken,
            rmsSessionId: summary.rmsSessionId,
          ),
        );
      }
      return;
    }

    final currentSummary = _summary;
    if (currentSummary == null) {
      return;
    }
    final result = _bridge.parseTransactionsResult(
      message.message,
      summary: currentSummary,
    );
    if (result == null) {
      return;
    }
    await ref
        .read(cardsControllerProvider.notifier)
        .applyForegroundRefresh(widget.cardId, result);
    if (!mounted) {
      return;
    }
    setState(() {
      _isSyncing = false;
      _status =
          'VaultCard synced the latest balance and transactions from the active GiftCardMall session.';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('VaultCard synced the GiftCardMall session.')),
    );
  }

  Future<void> _autofill() async {
    setState(() => _isAutofilling = true);
    try {
      final authenticated = await ref
          .read(biometricServiceProvider)
          .authenticate('Autofill GiftCardMall card details');
      if (!authenticated) {
        if (!mounted) {
          return;
        }
        setState(() {
          _status = 'Authentication was cancelled. Autofill did not run.';
        });
        return;
      }
      final credentials = await ref
          .read(cardsControllerProvider.notifier)
          .getCredentials(widget.cardId);
      await _controller.runJavaScript(_bridge.buildAutofillScript(credentials));
      if (!mounted) {
        return;
      }
      setState(() {
        _status =
            'Best-effort autofill sent to the page. Review the fields and submit inside GiftCardMall.';
      });
    } finally {
      if (mounted) {
        setState(() => _isAutofilling = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = ref.watch(selectedCardProvider(widget.cardId));
    if (card == null) {
      return const Scaffold(body: LoadingPlaceholder());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('GiftCardMall Refresh')),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(_status),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: _isAutofilling ? null : _autofill,
                        icon: const Icon(Icons.lock_open_outlined),
                        label: Text(
                          _isAutofilling ? 'Unlocking...' : 'Secure Autofill',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _controller.reload(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reload Page'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_isLoading || _isSyncing)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black12,
                      child: Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 12),
                                Text(
                                  _isSyncing
                                      ? 'Syncing GiftCardMall session...'
                                      : 'Loading GiftCardMall...',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
