class EnrollResponse {
  final String identityId;
  final String templateId;
  final bool isDuplicate;
  final String? duplicateIdentityId;
  final String? duplicateIdentityName;
  final String? error;

  const EnrollResponse({
    required this.identityId,
    required this.templateId,
    required this.isDuplicate,
    this.duplicateIdentityId,
    this.duplicateIdentityName,
    this.error,
  });

  factory EnrollResponse.fromJson(Map<String, dynamic> json) => EnrollResponse(
        identityId: json['identity_id'] as String,
        templateId: json['template_id'] as String,
        isDuplicate: json['is_duplicate'] as bool? ?? false,
        duplicateIdentityId: json['duplicate_identity_id'] as String?,
        duplicateIdentityName: json['duplicate_identity_name'] as String?,
        error: json['error'] as String?,
      );
}

class TemplateInfo {
  final String templateId;
  final String eyeSide;

  const TemplateInfo({required this.templateId, required this.eyeSide});

  factory TemplateInfo.fromJson(Map<String, dynamic> json) => TemplateInfo(
        templateId: json['template_id'] as String,
        eyeSide: json['eye_side'] as String,
      );
}

class GalleryIdentity {
  final String identityId;
  final String name;
  final List<TemplateInfo> templates;

  const GalleryIdentity({
    required this.identityId,
    required this.name,
    required this.templates,
  });

  factory GalleryIdentity.fromJson(Map<String, dynamic> json) =>
      GalleryIdentity(
        identityId: json['identity_id'] as String,
        name: json['name'] as String? ?? '',
        templates: (json['templates'] as List<dynamic>?)
                ?.map((e) => TemplateInfo.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

class TemplateDetail {
  final String templateId;
  final String identityId;
  final String identityName;
  final String eyeSide;
  final int width;
  final int height;
  final int nScales;
  final double qualityScore;
  final String deviceId;
  final String? irisCodeB64;
  final String? maskCodeB64;

  const TemplateDetail({
    required this.templateId,
    required this.identityId,
    required this.identityName,
    required this.eyeSide,
    required this.width,
    required this.height,
    required this.nScales,
    required this.qualityScore,
    required this.deviceId,
    this.irisCodeB64,
    this.maskCodeB64,
  });

  factory TemplateDetail.fromJson(Map<String, dynamic> json) => TemplateDetail(
        templateId: json['template_id'] as String,
        identityId: json['identity_id'] as String,
        identityName: json['identity_name'] as String? ?? '',
        eyeSide: json['eye_side'] as String,
        width: json['width'] as int,
        height: json['height'] as int,
        nScales: json['n_scales'] as int,
        qualityScore: (json['quality_score'] as num).toDouble(),
        deviceId: json['device_id'] as String? ?? '',
        irisCodeB64: json['iris_code_b64'] as String?,
        maskCodeB64: json['mask_code_b64'] as String?,
      );
}
