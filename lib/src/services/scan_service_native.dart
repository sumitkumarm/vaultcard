import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:vaultcard/src/domain/models/scan_result.dart';
import 'package:vaultcard/src/services/scan_text_parser.dart';

typedef TextRecognizerFactory = TextRecognizer Function();

class ScanService {
  const ScanService({
    TextRecognizerFactory recognizerFactory = _defaultRecognizerFactory,
  }) : _recognizerFactory = recognizerFactory;

  final TextRecognizerFactory _recognizerFactory;

  static TextRecognizer _defaultRecognizerFactory() {
    return TextRecognizer(script: TextRecognitionScript.latin);
  }

  Future<ScanResult> extractFromImagePath(String imagePath) async {
    final recognizer = _recognizerFactory();
    try {
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      return extractFromText(recognized.text).copyWith(
        recognizedText: recognized.text,
      );
    } finally {
      await recognizer.close();
    }
  }

  ScanResult extractFromText(String source) {
    return parseScanText(source);
  }
}
