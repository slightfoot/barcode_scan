import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_ml_vision/firebase_ml_vision.dart';
import 'package:flutter/material.dart';

late final List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  cameras = await availableCameras();
  runApp(ScannerApp());
}

class ScannerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Barcode Scanner',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: Scanner(),
    );
  }
}

@immutable
class Scanner extends StatefulWidget {
  const Scanner({Key? key}) : super(key: key);

  @override
  _ScannerState createState() => _ScannerState();
}

class _ScannerState extends State<Scanner> with SingleTickerProviderStateMixin {
  final BarcodeDetector barcodeDetector = FirebaseVision.instance.barcodeDetector(
    BarcodeDetectorOptions(barcodeFormats: BarcodeFormat.ean13),
  );

  late final CameraController _controller;
  late final AnimationController _animationController;

  Future? _processing;
  List<Barcode> _barcodes = [];

  bool get hasBarcodes => (_barcodes.length != 0);

  @override
  void initState() {
    super.initState();
    _controller = CameraController(cameras[0], ResolutionPreset.high);
    _controller.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
      _controller.startImageStream(_onLatestImageAvailable);
    });
    _animationController = AnimationController(
      duration: Duration(milliseconds: 2000),
      vsync: this,
    );
    _animationController.repeat(reverse: true);
  }

  void _onLatestImageAvailable(CameraImage image) {
    //print('_onLatestImageAvailable: ${image.format.raw}');
    if (_processing != null) {
      return;
    }

    final metadata = FirebaseVisionImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rawFormat: image.format.raw,
      planeData: image.planes.map((plane) {
        return FirebaseVisionImagePlaneMetadata(
          bytesPerRow: plane.bytesPerRow,
          height: plane.height,
          width: plane.width,
        );
      }).toList(),
    );

    final total = image.planes.fold<int>(0, (prev, el) => prev + el.bytes.length);
    final bytes = Uint8List(total);
    for (int offset = 0, i = 0; offset < total;) {
      final plane = image.planes[i++];
      bytes.setAll(offset, plane.bytes);
      offset += plane.bytes.length;
    }

    final visionImage = FirebaseVisionImage.fromBytes(bytes, metadata);
    _processing = barcodeDetector.detectInImage(visionImage).then((List<Barcode> barcodes) {
      //print('Found ${barcodes.length}');
      //for (final barcode in barcodes) {
      //  print('\t${barcode.format.value}: ${barcode.boundingBox}: ${barcode.displayValue}');
      //}
      if (mounted) {
        setState(() {
          _barcodes = barcodes;
          _processing = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _controller.stopImageStream();
    _controller.dispose();
    super.dispose();
  }

  void _onCapture() {
    if (!hasBarcodes) {
      return;
    }
    final barcodes = _barcodes;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        int i = 1;
        final items = barcodes.map((b) => '${i++}. ${b.displayValue}').join('\n');
        return AlertDialog(
          content: Text(items),
          actions: [
            FlatButton(
              onPressed: () => Navigator.of(context)!.pop(),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_controller.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: _controller.value.previewSize.height,
                    height: _controller.value.previewSize.width,
                    child: Stack(
                      children: [
                        CameraPreview(_controller),
                      ],
                    ),
                  ),
                  RotatedBox(
                    quarterTurns: 1,
                    child: CustomPaint(
                      painter: BarcodePainter(
                        _animationController,
                        _barcodes,
                      ),
                      size: Size(
                        _controller.value.previewSize.width,
                        _controller.value.previewSize.height,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          RepaintBoundary(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton(
                  onPressed: hasBarcodes ? _onCapture : null,
                  child: Text('Capture'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BarcodePainter extends CustomPainter {
  BarcodePainter(this.animation, this.barcodes) : super(repaint: animation);

  final Animation<double> animation;
  final List<Barcode> barcodes;

  @override
  void paint(Canvas canvas, Size size) {
    if (barcodes.length > 0) {
      final paint = Paint()
        ..color = Colors.lightGreenAccent
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 8.0;

      for (final barcode in barcodes) {
        final points = barcode.cornerPoints;
        final l = points.length;
        for (int i = 0; i < l; i++) {
          canvas.drawLine(
            points[(i - 1) % l],
            points[i % l],
            paint,
          );
        }
      }
    } else {
      final h = size.height - (size.height * 0.3);
      final w = h / 2.0;
      final b = Alignment.center.inscribe(Size(w, h), (Offset.zero & size));
      canvas.drawRect(
          b,
          Paint()
            ..color = Colors.black45
            ..style = PaintingStyle.fill);
      final scanX = b.left + (b.width * animation.value);
      canvas.drawLine(
          Offset(scanX, b.top),
          Offset(scanX, b.bottom),
          Paint()
            ..color = Colors.redAccent
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 4.0);
    }
  }

  @override
  bool shouldRepaint(covariant BarcodePainter oldDelegate) {
    return (barcodes != oldDelegate.barcodes);
  }
}
