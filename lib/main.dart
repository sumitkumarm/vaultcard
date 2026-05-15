import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:vaultcard/src/app.dart';
import 'package:vaultcard/src/background/background_callback.dart';
import 'package:vaultcard/src/bootstrap/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  tz.initializeTimeZones();
  final timezoneInfo = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
  final preferences = await SharedPreferences.getInstance();
  final bootstrap = await Bootstrap.create(preferences);
  await bootstrap.backgroundRefreshService
      .initialize(backgroundRefreshCallbackDispatcher);
  runApp(
    ProviderScope(
      overrides: bootstrap.overrides,
      child: const VaultCardApp(),
    ),
  );
}
