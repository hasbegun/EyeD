import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../models/analyze_result.dart';
import '../models/enrollment.dart';

class ApiClient {
  final Dio _engine;

  ApiClient(ApiConfig config)
      : _engine = Dio(BaseOptions(
          baseUrl: config.engineBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 60),
        ));

  // --- Health ---

  Future<bool> checkReady() async {
    try {
      final r = await _engine.get<Map<String, dynamic>>('/health/ready');
      return r.data?['ready'] == true;
    } catch (_) {
      return false;
    }
  }

  // --- Enrollment ---

  Future<EnrollResponse> enroll({
    required String jpegB64,
    required String eyeSide,
    required String identityId,
    required String identityName,
    String deviceId = 'flutter-client2',
  }) async {
    final r = await _engine.post<Map<String, dynamic>>('/enroll', data: {
      'identity_id': identityId,
      'identity_name': identityName,
      'jpeg_b64': jpegB64,
      'eye_side': eyeSide,
      'device_id': deviceId,
    });
    return EnrollResponse.fromJson(r.data!);
  }

  // --- Gallery ---

  Future<List<GalleryIdentity>> listGallery() async {
    final r = await _engine.get<List<dynamic>>('/gallery/list');
    return r.data!
        .map((e) => GalleryIdentity.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TemplateDetail> getTemplateDetail(String templateId) async {
    final r = await _engine.get<Map<String, dynamic>>(
      '/gallery/template/${Uri.encodeComponent(templateId)}',
    );
    return TemplateDetail.fromJson(r.data!);
  }

  Future<void> deleteIdentity(String identityId) async {
    await _engine
        .delete<void>('/gallery/delete/${Uri.encodeComponent(identityId)}');
  }

  // --- Config ---

  Future<Map<String, dynamic>> getConfig() async {
    final r = await _engine.get<Map<String, dynamic>>('/config');
    return r.data!;
  }

  Future<Map<String, dynamic>> toggleFhe(bool enabled) async {
    final r = await _engine.post<Map<String, dynamic>>(
      '/config/fhe',
      data: {'enabled': enabled},
    );
    return r.data!;
  }

  // --- Analyze (for detect) ---

  Future<AnalyzeResponse> analyzeImage(Uint8List imageBytes, String eyeSide) async {
    final jpegB64 = base64Encode(imageBytes);
    final r = await _engine.post<Map<String, dynamic>>('/analyze/json', data: {
      'jpeg_b64': jpegB64,
      'eye_side': eyeSide,
      'frame_id': 'detect-${DateTime.now().millisecondsSinceEpoch}',
      'device_id': 'flutter-client2',
    });
    return AnalyzeResponse.fromJson(r.data!);
  }

  void dispose() {
    _engine.close();
  }
}
