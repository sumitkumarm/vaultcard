import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vaultcard/src/domain/models/scan_result.dart';
import 'package:vaultcard/src/providers/providers.dart';

class ScanCardScreen extends ConsumerStatefulWidget {
  const ScanCardScreen({super.key});

  @override
  ConsumerState<ScanCardScreen> createState() => _ScanCardScreenState();
}

class _ScanCardScreenState extends ConsumerState<ScanCardScreen> {
  final _textController = TextEditingController();
  CameraController? _cameraController;
  bool _isCameraReady = false;
  bool _isProcessing = false;
  bool _showManualFallback = false;
  String? _cameraError;
  ScanResult? _lastResult;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _cameraError = 'No camera is available on this device.';
          _showManualFallback = true;
        });
        return;
      }
      final preferredCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        preferredCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _isCameraReady = true;
      });
    } on CameraException catch (error) {
      setState(() {
        _cameraError = error.description ?? error.code;
        _showManualFallback = true;
      });
    } catch (error) {
      setState(() {
        _cameraError = error.toString();
        _showManualFallback = true;
      });
    }
  }

  Future<void> _captureAndScan() async {
    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isProcessing) {
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final picture = await controller.takePicture();
      final result = await ref
          .read(scanServiceProvider)
          .extractFromImagePath(picture.path);
      if (!mounted) {
        return;
      }
      _handleResult(result);
    } on CameraException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.description ?? error.code)),
      );
      setState(() => _showManualFallback = true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Scan failed: $error')));
      setState(() => _showManualFallback = true);
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _handleResult(ScanResult result) {
    setState(() {
      _lastResult = result;
      _showManualFallback = true;
      _textController.text = result.recognizedText ?? _textController.text;
    });

    if (!result.hasCandidateData) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No card details were detected. You can paste OCR text manually.',
          ),
        ),
      );
      return;
    }

    context.go(
      '/add/form',
      extra: {
        'cardNumber': result.cardNumber ?? '',
        'expiry': result.expiry ?? '',
        'cvv': result.cvv ?? '',
      },
    );
  }

  void _useManualText() {
    _handleResult(
        ref.read(scanServiceProvider).extractFromText(_textController.text));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Card')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Scan with your camera',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            'VaultCard keeps recognition on device. Capture the card, then review the prefilled form before saving.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: _buildCameraPreview(context),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed:
                _isCameraReady && !_isProcessing ? _captureAndScan : null,
            icon: _isProcessing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.camera_alt_outlined),
            label: Text(_isProcessing ? 'Scanning...' : 'Capture Card'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              setState(() => _showManualFallback = !_showManualFallback);
            },
            child: Text(
              _showManualFallback ? 'Hide text fallback' : 'Use text fallback',
            ),
          ),
          if (_lastResult != null) ...[
            const SizedBox(height: 12),
            _ScanSummary(result: _lastResult!),
          ],
          if (_showManualFallback) ...[
            const SizedBox(height: 24),
            Text(
              'Fallback OCR text',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Use this when camera permissions are denied or recognition needs manual cleanup.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _textController,
              minLines: 6,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: 'Recognized text',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _useManualText,
              child: const Text('Use Text Result'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCameraPreview(BuildContext context) {
    final controller = _cameraController;
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _cameraError!,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (!_isCameraReady || controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(controller),
        IgnorePointer(
          child: Center(
            child: Container(
              width: 280,
              height: 180,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScanSummary extends StatelessWidget {
  const _ScanSummary({required this.result});

  final ScanResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last scan', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Card: ${result.cardNumber ?? 'Not found'}'),
            Text('Expiry: ${result.expiry ?? 'Not found'}'),
            Text('CVV: ${result.cvv ?? 'Not found'}'),
            Text('Confidence: ${(result.confidence * 100).round()}%'),
          ],
        ),
      ),
    );
  }
}
