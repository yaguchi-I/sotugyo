import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';

import '../models/receipt_data.dart';

/// Gemini とのやり取り（OCR読み取り・相談チャット）をまとめたクラス。
/// 画面側はこのクラスだけ呼べばいいようにしてある。
class GeminiService {
  GeminiService._();
  static final GeminiService instance = GeminiService._();

  // チームルール：モデルは必ず gemini-3.5-flash
  static const String _modelName = 'gemini-3.5-flash';

  /// レシート読み取り用（JSONで返させる）
  late final GenerativeModel _ocrModel = FirebaseAI.googleAI().generativeModel(
    model: _modelName,
    generationConfig: GenerationConfig(
      responseMimeType: 'application/json',
      temperature: 0,
    ),
  );

  /// 相談チャット用
  late final GenerativeModel _chatModel = FirebaseAI.googleAI().generativeModel(
    model: _modelName,
    systemInstruction: Content.system(
      'あなたは一人暮らしの若者向けの節約アドバイザーです。'
      'レシートや家計の内容をもとに、具体的で実践しやすい節約術・レシピ・買い物のコツを提案してください。'
      '回答は日本語で、スマホで読みやすいよう短めの段落にしてください。'
      'Markdownの記号（**や#など）は使わず、プレーンテキストで書いてください。',
    ),
  );

  static const String _ocrPrompt = '''
この画像を読み取ってください。
レシート（または購入明細）であれば、次の形式のJSONだけを返してください。説明文は不要です。
{
  "isReceipt": true,
  "store": "店名（読めなければnull）",
  "date": "YYYY-MM-DD（読めなければnull）",
  "items": [{"name": "品名", "price": 税込金額の整数}],
  "total": 合計金額の整数（読めなければnull）,
  "category": "食費 / 日用品 / 外食 / 交通費 / 娯楽 / その他 のどれか"
}
値引きは price をマイナスの整数にして items に含めてください。
レシートではない画像の場合は {"isReceipt": false} だけを返してください。
''';

  /// 画像をOCRしてレシート情報に変換する
  Future<ReceiptData> analyzeReceipt(Uint8List imageBytes, String mimeType) async {
    final response = await _ocrModel.generateContent([
      Content.multi([
        TextPart(_ocrPrompt),
        InlineDataPart(mimeType, imageBytes),
      ]),
    ]);

    final text = response.text;
    if (text == null || text.trim().isEmpty) {
      throw Exception('読み取り結果が空でした');
    }
    return ReceiptData.fromJson(_decodeJson(text));
  }

  /// 相談チャットを開始する。
  /// receipt を渡すと、その内容を前提にした会話になる。
  ChatSession startConsultation({
    ReceiptData? receipt,
    Uint8List? imageBytes,
    String? mimeType,
  }) {
    if (receipt == null) {
      return _chatModel.startChat();
    }

    final firstParts = <Part>[
      TextPart(
        '次のレシートについて相談したいです。読み取り結果はこちらです。\n'
        '${receipt.toPromptText()}',
      ),
      if (imageBytes != null) InlineDataPart(mimeType ?? 'image/jpeg', imageBytes),
    ];

    return _chatModel.startChat(
      history: [
        Content.multi(firstParts),
        Content.model([
          TextPart('レシートの内容を確認しました。気になることを何でも聞いてください。'),
        ]),
      ],
    );
  }

  /// ```json ... ``` で囲まれて返ってきた場合にも対応
  Map<String, dynamic> _decodeJson(String text) {
    var cleaned = text.trim();
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start != -1 && end > start) {
      cleaned = cleaned.substring(start, end + 1);
    }
    final decoded = jsonDecode(cleaned);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('JSONの形式が想定と違います');
  }
}
