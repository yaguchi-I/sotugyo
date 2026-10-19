import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  String _responseText = "";
  bool _isLoading = false;

  Future<void> askGemini() async {
    setState(() {
      _isLoading = true;
      _responseText = "通信中...";
    });

    const apiKey = 'AQ.Ab8RN6Jn2XETWXDUPF1FGrXmKebuBvhnGUhCNInEZglzJVPVSw';
    final model = GenerativeModel(model: 'gemini-3.5-flash', apiKey: apiKey);
    const prompt = '一人暮らしの夕飯で、もやしを使った50円以内のレシピを考えて';
    final content = [Content.text(prompt)];

    try {
      final response = await model.generateContent(content);
      setState(() {
        _responseText = response.text ?? '';
      });
    } catch (e) {
      setState(() {
        _responseText = 'エラー: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI相談室')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: _isLoading ? null : askGemini,
              icon: const Icon(Icons.send),
              label: const Text('もやしレシピを聞く'),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_responseText, style: const TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}