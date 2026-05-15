import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late final TextEditingController _nicknameController;
  CardNetwork _network = CardNetwork.unknown;

  @override
  void initState() {
    super.initState();
    _cardController = TextEditingController(text: widget.prefill['cardNumber']);
    _expiryController = TextEditingController(
      text: formatExpiryInput(widget.prefill['expiry'] ?? ''),
    );
    _cvvController = TextEditingController(text: widget.prefill['cvv']);
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
                decoration: InputDecoration(
                  labelText: 'Card Number',
                  suffixIcon: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 12),
                    child: _NetworkBadge(network: _network),
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 72,
                    minHeight: 40,
                  ),
                ),
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
                      inputFormatters: const [_ExpiryTextInputFormatter()],
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
                  final cardNumber =
                      _cardController.text.replaceAll(RegExp(r'\s+'), '');
                  final input = CardInput(
                    cardNumber: cardNumber,
                    expiry: _expiryController.text.trim(),
                    cvv: _cvvController.text.trim(),
                    network: inferNetwork(cardNumber),
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

class _NetworkBadge extends StatelessWidget {
  const _NetworkBadge({required this.network});

  final CardNetwork network;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: switch (network) {
        CardNetwork.visa => const _VisaBadge(key: ValueKey('visa')),
        CardNetwork.mastercard =>
          const _MastercardBadge(key: ValueKey('mastercard')),
        CardNetwork.unknown => const Icon(
            Icons.credit_card,
            key: ValueKey('unknown'),
          ),
      },
    );
  }
}

class _VisaBadge extends StatelessWidget {
  const _VisaBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      widthFactor: 1,
      child: Container(
        width: 56,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'VISA',
          style: TextStyle(
            color: Color(0xFF1A1F71),
            fontSize: 15,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _MastercardBadge extends StatelessWidget {
  const _MastercardBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      widthFactor: 1,
      child: Container(
        width: 56,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Transform.translate(
              offset: const Offset(-8, 0),
              child: Container(
                width: 21,
                height: 21,
                decoration: const BoxDecoration(
                  color: Color(0xFFEB001B),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(8, 0),
              child: Container(
                width: 21,
                height: 21,
                decoration: const BoxDecoration(
                  color: Color(0xFFF79E1B),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Container(
              width: 15,
              height: 21,
              decoration: BoxDecoration(
                color: const Color(0xFFFF5F00).withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpiryTextInputFormatter extends TextInputFormatter {
  const _ExpiryTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = formatExpiryInput(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
