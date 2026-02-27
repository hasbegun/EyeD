import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../models/dataset.dart';
import '../models/detailed_result.dart';
import '../models/enrollment.dart';
import '../models/health.dart';

class GatewayClient {
  final Dio _gateway;
  final Dio _engine;
  final ApiConfig config;

  GatewayClient(this.config)
      : _gateway = Dio(BaseOptions(baseUrl: config.gatewayBaseUrl)),
        _engine = Dio(BaseOptions(baseUrl: config.engineBaseUrl));

  // --- Health ---

  Future<HealthAlive> checkAlive() async {
    final r = await _gateway.get<Map<String, dynamic>>('/health/alive');
    return HealthAlive.fromJson(r.data!);
  }

  Future<HealthReady> checkReady() async {
    final r = await _gateway.get<Map<String, dynamic>>('/health/ready');
    return HealthReady.fromJson(r.data!);
  }

  Future<EngineHealth> checkEngineReady() async {
    final r = await _engine.get<Map<String, dynamic>>('/health/ready');
    return EngineHealth.fromJson(r.data!);
  }

  // --- Gallery ---

  Future<int> getGallerySize() async {
    final r = await _engine.get<Map<String, dynamic>>('/gallery/size');
    return r.data!['gallery_size'] as int;
  }

  Future<List<GalleryIdentity>> listGallery() async {
    final r = await _engine.get<List<dynamic>>('/gallery/list');
    return r.data!
        .map((e) => GalleryIdentity.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteIdentity(String identityId) async {
    await _engine
        .delete<void>('/gallery/delete/${Uri.encodeComponent(identityId)}');
  }

  Future<TemplateDetail> getTemplateDetail(String templateId) async {
    final r = await _engine.get<Map<String, dynamic>>(
      '/gallery/template/${Uri.encodeComponent(templateId)}',
    );
    return TemplateDetail.fromJson(r.data!);
  }

  // --- Datasets ---

  Future<List<DatasetInfo>> listDatasets() async {
    final r = await _engine.get<List<dynamic>>('/datasets');
    return r.data!
        .map((e) => DatasetInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<DatasetInfo> getDatasetInfo(String name) async {
    final r = await _engine
        .get<Map<String, dynamic>>('/datasets/${Uri.encodeComponent(name)}/info');
    return DatasetInfo.fromJson(r.data!);
  }

  Future<List<SubjectInfo>> listDatasetSubjects(String name) async {
    final r = await _engine
        .get<List<dynamic>>('/datasets/${Uri.encodeComponent(name)}/subjects');
    return r.data!
        .map((e) => SubjectInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<DatasetImage>> listDatasetImages(
    String name, {
    String? subject,
    int offset = 0,
    int limit = 100,
  }) async {
    final params = <String, dynamic>{
      'offset': offset,
      'limit': limit,
    };
    if (subject != null) params['subject'] = subject;
    final r = await _engine.get<List<dynamic>>(
      '/datasets/${Uri.encodeComponent(name)}/images',
      queryParameters: params,
    );
    return r.data!
        .map((e) => DatasetImage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  String getDatasetImageUrl(String name, String path) {
    return '${_engine.options.baseUrl}/datasets/${Uri.encodeComponent(name)}/image/$path';
  }

  Future<Uint8List> fetchDatasetImage(String name, String path) async {
    final r = await _engine.get<List<int>>(
      '/datasets/${Uri.encodeComponent(name)}/image/$path',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(r.data!);
  }

  // --- Dataset paths ---

  Future<List<DatasetPathInfo>> listDatasetPaths() async {
    final r = await _engine.get<List<dynamic>>('/datasets/paths');
    return r.data!
        .map((e) => DatasetPathInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<DatasetPathInfo> addDatasetPath(String path) async {
    final r = await _engine.post<Map<String, dynamic>>(
      '/datasets/paths',
      data: {'path': path},
    );
    return DatasetPathInfo.fromJson(r.data!);
  }

  Future<void> removeDatasetPath(String path) async {
    await _engine.delete<void>(
      '/datasets/paths',
      queryParameters: {'path': path},
    );
  }

  // --- Analysis ---

  Future<DetailedResult> analyzeDetailed(
    String datasetName,
    String imagePath,
    String eyeSide,
  ) async {
    final imageBytes = await fetchDatasetImage(datasetName, imagePath);
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        imageBytes,
        filename: imagePath.split('/').last,
      ),
      'eye_side': eyeSide,
      'frame_id': 'run-$imagePath',
      'device_id': 'flutter-client',
    });
    final r =
        await _engine.post<Map<String, dynamic>>('/analyze/detailed', data: form);
    return DetailedResult.fromJson(r.data!);
  }

  // --- Enrollment ---

  Future<EnrollResponse> enroll({
    required String jpegB64,
    required String eyeSide,
    required String identityId,
    required String identityName,
    String deviceId = 'flutter-client',
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

  /// Fetch a dataset image and return it as base64-encoded JPEG string.
  Future<String> fetchDatasetImageAsBase64(String name, String path) async {
    final bytes = await fetchDatasetImage(name, path);
    return base64Encode(bytes);
  }

  /// Bulk-enroll subjects from a dataset via SSE streaming.
  ///
  /// Yields [BulkEnrollProgress] for each image processed and a final
  /// [BulkEnrollDone] with summary counts.
  Stream<BulkEnrollEvent> enrollBatch({
    required String dataset,
    List<String>? subjects,
  }) async* {
    final body = <String, dynamic>{'dataset': dataset};
    if (subjects != null) body['subjects'] = subjects;

    final response = await _engine.post<ResponseBody>(
      '/enroll/batch',
      data: body,
      options: Options(responseType: ResponseType.stream),
    );

    final stream = response.data!.stream;
    String buffer = '';

    await for (final chunk in stream) {
      buffer += utf8.decode(chunk);

      // Parse SSE lines: each event ends with \n\n
      while (buffer.contains('\n\n')) {
        final idx = buffer.indexOf('\n\n');
        final block = buffer.substring(0, idx);
        buffer = buffer.substring(idx + 2);

        String? eventType;
        String? data;
        for (final line in block.split('\n')) {
          if (line.startsWith('event: ')) {
            eventType = line.substring(7).trim();
          } else if (line.startsWith('data: ')) {
            data = line.substring(6);
          }
        }

        if (data == null) continue;
        final json = jsonDecode(data) as Map<String, dynamic>;

        if (eventType == 'done') {
          yield BulkEnrollDone(BulkEnrollSummary.fromJson(json));
        } else {
          yield BulkEnrollProgress(BulkEnrollResult.fromJson(json));
        }
      }
    }
  }

  void dispose() {
    _gateway.close();
    _engine.close();
  }
}
