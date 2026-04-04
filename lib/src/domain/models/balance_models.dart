import 'package:vaultcard/src/domain/models/vault_card.dart';

class BalanceResult {
  const BalanceResult({
    required this.balance,
    required this.transactions,
    required this.fetchedAt,
  });

  final double balance;
  final List<CardTransaction> transactions;
  final DateTime fetchedAt;
}

enum RefreshFailureReason { network, parseError, rateLimited, offline, unknown }

class RefreshFailure {
  const RefreshFailure({
    required this.reason,
    required this.message,
  });

  final RefreshFailureReason reason;
  final String message;
}

class RefreshOutcome {
  const RefreshOutcome.success(this.result)
      : failure = null,
        cooldownUntil = null;

  const RefreshOutcome.failure(this.failure)
      : result = null,
        cooldownUntil = null;

  const RefreshOutcome.cooldown(this.cooldownUntil)
      : result = null,
        failure = null;

  final BalanceResult? result;
  final RefreshFailure? failure;
  final DateTime? cooldownUntil;

  bool get isSuccess => result != null;
  bool get isFailure => failure != null;
  bool get isCooldown => cooldownUntil != null;
}
