import 'package:vaultcard/src/domain/models/parser_config.dart';

abstract interface class ParserConfigProvider {
  Future<ParserConfig> getConfig();
}
