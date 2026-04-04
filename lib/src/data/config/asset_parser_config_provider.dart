import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:vaultcard/src/data/config/parser_config_provider.dart';
import 'package:vaultcard/src/domain/models/parser_config.dart';

class AssetParserConfigProvider implements ParserConfigProvider {
  const AssetParserConfigProvider(this._bundle);

  final AssetBundle _bundle;

  @override
  Future<ParserConfig> getConfig() async {
    final raw = await _bundle.loadString('assets/config/parser_config.json');
    return ParserConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}
