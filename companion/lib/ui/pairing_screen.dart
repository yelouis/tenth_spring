import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../sync/pairing.dart';
import '../sync/scout_link.dart';

class PairingScreen extends StatefulWidget {
  final ScoutLink? scoutLink;

  const PairingScreen({super.key, this.scoutLink});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  late final ScoutLink _scoutLink;
  bool _isProcessing = false;
  String _statusMessage = 'Scan the pairing code shown on your PC.';

  @override
  void initState() {
    super.initState();
    _scoutLink = widget.scoutLink ?? ScoutLink();
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_isProcessing) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;

      final payload = QrPayloadV2.tryParse(raw);
      if (payload == null) {
        setState(() {
          _statusMessage = 'Unrecognized QR code — scan the code from your PC game.';
        });
        continue;
      }

      setState(() {
        _isProcessing = true;
        _statusMessage = 'Connecting to PC...';
      });

      final result = await _scoutLink.pair(payload);

      if (!mounted) return;

      switch (result) {
        case PairOk():
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Scout recruited successfully!')),
          );
          Navigator.of(context).pop(true);
          return;
        case PairBadCode():
          setState(() {
            _isProcessing = false;
            _statusMessage = 'Pairing code expired — refresh the code on your PC and try again.';
          });
        case PairPcStorageError():
          setState(() {
            _isProcessing = false;
            _statusMessage = "Your PC couldn't save the pairing — refresh the code on your PC and try again.";
          });
        case PairUnreachable():
          setState(() {
            _isProcessing = false;
            _statusMessage = "Can't reach your PC — open the scout report on your PC and re-scan its code.";
          });
        case PairProtocolError(:final message):
          setState(() {
            _isProcessing = false;
            _statusMessage = 'Pairing error: ${message ?? 'protocol failure'}';
          });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair with your PC'),
      ),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              onDetect: _handleBarcode,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Theme.of(context).colorScheme.surface,
            width: double.infinity,
            child: Column(
              children: [
                if (_isProcessing)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12.0),
                    child: CircularProgressIndicator(),
                  ),
                Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
