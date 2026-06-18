class BackgroundRefreshService {
  const BackgroundRefreshService();

  static const String taskPrefix = 'vaultcard.refresh.';

  Future<void> initialize(void Function() callbackDispatcher) async {}

  Future<void> registerCardRefresh(
    String cardId, {
    Duration initialDelay = Duration.zero,
  }) async {}

  Future<void> cancelCardRefresh(String cardId) async {}
}
