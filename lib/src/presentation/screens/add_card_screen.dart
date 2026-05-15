import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AddCardScreen extends StatelessWidget {
  const AddCardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Card')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose how to add your card',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Scan the card to prefill fields or enter the details manually.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: const Icon(Icons.document_scanner_outlined),
                title: const Text('Scan Card'),
                subtitle: const Text('Use on-device OCR to prefill card fields'),
                onTap: () => context.push('/scan'),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.keyboard_alt_outlined),
                title: const Text('Enter Manually'),
                subtitle: const Text('Type card number, expiry, and CVV'),
                onTap: () => context.push('/add/form'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
