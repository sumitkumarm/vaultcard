import 'package:workmanager/workmanager.dart';

class BackgroundRefreshService {
  const BackgroundRefreshService();

  static const String taskPrefix = 'vaultcard.refresh.';

  Future<void> initialize(void Function() callbackDispatcher) async {
    await Workmanager().initialize(
      callbackDispatcher,
    );
  }

  Future<void> registerCardRefresh(
    String cardId, {
    Duration initialDelay = Duration.zero,
  }) async {
    await Workmanager().registerPeriodicTask(
      '$taskPrefix$cardId',
      taskPrefix,
      inputData: <String, dynamic>{'cardId': cardId},
      frequency: const Duration(hours: 24),
      initialDelay: initialDelay,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(hours: 1),
    );
  }

  Future<void> cancelCardRefresh(String cardId) {
    return Workmanager().cancelByUniqueName('$taskPrefix$cardId');
  }
}
