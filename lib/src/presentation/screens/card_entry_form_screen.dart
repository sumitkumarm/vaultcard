import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vaultcard/src/domain/models/card_input.dart';
import 'package:vaultcard/src/domain/models/vault_card.dart';
import 'package:vaultcard/src/providers/providers.dart';
import 'package:vaultcard/src/utils/card_utils.dart';
import 'package:vaultcard/src/utils/validators.dart';

class CardEntryFormScreen extends ConsumerStatefulWidget {
  const CardEntryFormScreen({
    super.key,
    this.prefill = const {},
  });

  final Map<String, String> prefill;

  @override
  ConsumerState<CardEntryFormScreen> createState() =>
      _CardEntryFormScreenState();
}

class _CardEntryFormScreenState extends ConsumerState<CardEntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _cardController;
  late final TextEditingController _expiryController;
  late final TextEditingController _cvvController;
  late final TextEditingController _pinController;
  late final TextEditingController _nicknameController;
  CardNetwork _network = CardNetwork.unknown;

  @override
  void initState() {
    super.initState();
    _cardController = TextEditingController(text: widget.prefill['cardNumber']);
    _expiryController = TextEditingController(text: widget.prefill['expiry']);
    _cvvController = TextEditingController(text: widget.prefill['cvv']);
    _pinController = TextEditingController();
    _nicknameController = TextEditingController();
    _cardController.addListener(() {
      setState(() {
        _network = inferNetwork(
          _cardController.text.replaceAll(RegExp(r'\s+'), ''),
        );
      });
    });
    _network = inferNetwork(_cardController.text.replaceAll(RegExp(r'\s+'), ''));
  }

  @override
  void dispose() {
    _cardController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _pinController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Card Details')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextFormField(
                controller: _cardController,
                decoration: const InputDecoration(labelText: 'Card Number'),
                keyboardType: TextInputType.number,
                validator: (value) => validateCardNumber(value ?? ''),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _expiryController,
                      decoration:
                          const InputDecoration(labelText: 'Expiry (MM/YY)'),
                      keyboardType: TextInputType.datetime,
                      validator: (value) => validateExpiry(value ?? ''),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _cvvController,
                      decoration: const InputDecoration(labelText: 'CVV'),
                      keyboardType: TextInputType.number,
                      validator: (value) => validateCvv(value ?? ''),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _pinController,
                decoration: const InputDecoration(labelText: 'PIN'),
                obscureText: true,
                keyboardType: TextInputType.number,
                validator: (value) => validatePin(value ?? ''),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<CardNetwork>(
                initialValue: _network == CardNetwork.unknown ? null : _network,
                decoration: const InputDecoration(labelText: 'Network'),
                items: CardNetwork.values
                    .where((network) => network != CardNetwork.unknown)
                    .map(
                      (network) => DropdownMenuItem(
                        value: network,
                        child: Text(network.name.toUpperCase()),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _network = value ?? CardNetwork.unknown),
                validator: (value) => value == null || value == CardNetwork.unknown
                    ? 'Select a network'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nicknameController,
                decoration:
                    const InputDecoration(labelText: 'Nickname (optional)'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () async {
                  final router = GoRouter.of(context);
                  if (!_formKey.currentState!.validate()) {
                    return;
                  }
                  final input = CardInput(
                    cardNumber:
                        _cardController.text.replaceAll(RegExp(r'\s+'), ''),
                    expiry: _expiryController.text.trim(),
                    cvv: _cvvController.text.trim(),
                    pin: _pinController.text.trim(),
                    network: _network,
                    nickname: _nicknameController.text.trim(),
                  );
                  final id =
                      await ref.read(cardsControllerProvider.notifier).addCard(
                            input,
                          );
                  if (!mounted) {
                    return;
                  }
                  router.go('/card/$id');
                },
                child: const Text('Save Card'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
