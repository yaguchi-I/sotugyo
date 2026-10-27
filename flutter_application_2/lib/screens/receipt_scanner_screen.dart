import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class ReceiptScannerScreen extends StatefulWidget {
  const ReceiptScannerScreen({super.key});

  @override
  State<ReceiptScannerScreen> createState() => _ReceiptScannerScreenState();
}

class _ReceiptScannerScreenState extends State<ReceiptScannerScreen> {
  String _extractedDate = '';
  String _extractedAmount = '';
  String _fullText = '';

  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.japanese);

  Future<void> _scanReceipt() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image == null) return;

    final inputImage = InputImage.fromFilePath(image.path);
    final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

    final String text = recognizedText.text;
    
    final dateRegExp = RegExp(r'\d{4}[年/]\d{1,2}[月/]\d{1,2}[日]?');
    final amountRegExp = RegExp(r'(?:合計|小計|¥|￥)\s*([0-9,]+)');

    String date = '';
    String amount = '';

    final dateMatch = dateRegExp.firstMatch(text);
    if (dateMatch != null) {
      date = dateMatch.group(0) ?? '';
    }

    final amountMatch = amountRegExp.firstMatch(text);
    if (amountMatch != null) {
      amount = amountMatch.group(1) ?? '';
    }

    setState(() {
      _fullText = text;
      _extractedDate = date;
      _extractedAmount = amount;
    });
  }

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('レシート読み取り'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton.icon(
              onPressed: _scanReceipt,
              icon: const Icon(Icons.camera_alt),
              label: const Text('レシートを撮影'),
            ),
            const SizedBox(height: 24),
            const Text('読み取った日付:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(_extractedDate.isNotEmpty ? _extractedDate : '未検出'),
            const SizedBox(height: 16),
            const Text('読み取った金額:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(_extractedAmount.isNotEmpty ? _extractedAmount : '未検出'),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, {
                  'date': _extractedDate,
                  'amount': _extractedAmount,
                });
              },
              child: const Text('この内容で入力する'),
            ),
            const SizedBox(height: 32),
            const Text('読み取った全文:', style: TextStyle(fontWeight: FontWeight.bold)),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8.0),
              color: Colors.grey[200],
              child: Text(_fullText),
            ),
          ],
        ),
      ),
    );
  }
}