import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vaultcard/src/providers/providers.dart';

class ScanCardScreen extends ConsumerStatefulWidget {
  const ScanCardScreen({super.key});

  @override
  ConsumerState<ScanCardScreen> createState() => _ScanCardScreenState();
}

class _ScanCardScreenState extends ConsumerState<ScanCardScreen> {
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Card')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'OCR spike placeholder',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Paste recognized text here to simulate the scan-to-form handoff until camera and OCR are fully validated on device.',
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
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                final result = ref.read(scanServiceProvider).extractFromText(
                      _textController.text,
                    );
                context.go(
                  '/add/form',
                  extra: {
                    'cardNumber': result.cardNumber ?? '',
                    'expiry': result.expiry ?? '',
                    'cvv': result.cvv ?? '',
                  },
                );
              },
              child: const Text('Use Scan Result'),
            ),
          ],
        ),
      ),
    );
  }
}
