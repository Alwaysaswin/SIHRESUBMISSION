import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

class OcrService {
  static const String baseUrl = 'http://localhost:5000';

  static Future<Map<String, dynamic>?> pickAndExtract() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (picked == null || picked.files.single.bytes == null) return null;

    final file = picked.files.single;
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/ocr/extract'),
    );
    request.files.add(
      http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name),
    );

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) return null;
    return jsonDecode(body) as Map<String, dynamic>;
  }
}