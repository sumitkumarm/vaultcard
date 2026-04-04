import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vaultcard/src/app.dart';
import 'package:vaultcard/src/bootstrap/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final preferences = await SharedPreferences.getInstance();
  final bootstrap = await Bootstrap.create(preferences);
  runApp(
    ProviderScope(
      overrides: bootstrap.overrides,
      child: const VaultCardApp(),
    ),
  );
}
