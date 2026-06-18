import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vaultcard/src/domain/models/scan_result.dart';
import 'package:vaultcard/src/providers/providers.dart';

class ScanCardScreen extends ConsumerStatefulWidget {
  const ScanCardScreen({super.key});

  @override
  ConsumerState<ScanCardScreen> createState() => _ScanCardScreenState();
}

class _ScanCardScreenState extends ConsumerState<ScanCardScreen> {
  final _textController = TextEditingController(
    text: 'Card 4511292112977068 Exp 05/35 CVV 996',
  );
  ScanResult? _lastResult;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _useManualText() {
    final result =
        ref.read(scanServiceProvider).extractFromText(_textController.text);
    setState(() => _lastResult = result);
    if (!result.hasCandidateData) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No card details were detected.')),
      );
      return;
    }
    context.go(
      '/add/form',
      extra: {
        'cardNumber': result.cardNumber ?? '',
        'expiry': result.expiry ?? '',
        'cvv': result.cvv ?? '',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Card')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'OCR text parser',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            'Camera OCR is native-only. Web QA uses the same text parser to test scan prefill behavior.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _textController,
            minLines: 6,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'Recognized text',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: _useManualText,
            child: const Text('Use Text Result'),
          ),
          if (_lastResult != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last parse',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('Card: ${_lastResult!.cardNumber ?? 'Not found'}'),
                    Text('Expiry: ${_lastResult!.expiry ?? 'Not found'}'),
                    Text('CVV: ${_lastResult!.cvv ?? 'Not found'}'),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
