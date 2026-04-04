import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  const ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity;

  final Connectivity? _connectivity;

  Future<bool> isOnline() async {
    final connectivity = _connectivity ?? Connectivity();
    final result = await connectivity.checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }
}
