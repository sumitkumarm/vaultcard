import 'package:vaultcard/src/domain/models/scan_result.dart';
import 'package:vaultcard/src/services/scan_text_parser.dart';

class ScanService {
  const ScanService();

  Future<ScanResult> extractFromImagePath(String imagePath) {
    throw UnsupportedError('Camera OCR is not available in web QA mode.');
  }

  ScanResult extractFromText(String source) {
    return parseScanText(source);
  }
}
