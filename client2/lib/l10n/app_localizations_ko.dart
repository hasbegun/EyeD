// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'EyeD';

  @override
  String get enrollPage => '등록';

  @override
  String get detectPage => '탐지';

  @override
  String get tabIndividual => '개별';

  @override
  String get tabBulk => '일괄';

  @override
  String get tabGallery => '갤러리';

  @override
  String get nameLabel => '이름';

  @override
  String get nameRequired => '이름을 입력하세요';

  @override
  String get leftEye => '왼쪽 눈';

  @override
  String get rightEye => '오른쪽 눈';

  @override
  String get loadImage => '이미지 불러오기';

  @override
  String get notAvailable => 'N/A';

  @override
  String get enroll => '등록';

  @override
  String get enrolling => '등록 중...';

  @override
  String get enrollSuccess => '등록 완료';

  @override
  String get enrollSuccessEncrypted => '등록 완료 — 템플릿 암호화됨 🔒';

  @override
  String get enrollSuccessPlain => '등록 완료 — 템플릿 평문';

  @override
  String enrollDuplicate(String name) {
    return '중복: $name과(와) 일치';
  }

  @override
  String enrollError(String error) {
    return '등록 실패: $error';
  }

  @override
  String get eyeRequired => '최소 하나의 눈 이미지가 필요합니다';

  @override
  String get bulkSelectDir => '디렉토리 선택';

  @override
  String get bulkStart => '일괄 등록 시작';

  @override
  String bulkRunning(int current, int total) {
    return '등록 중... $current/$total';
  }

  @override
  String bulkComplete(int enrolled, int total, int skipped, int errors) {
    return '완료: $total건 중 $enrolled건 등록, $skipped건 건너뜀, $errors건 오류';
  }

  @override
  String get bulkIdle => '디렉토리를 선택하세요';

  @override
  String get bulkNoSubjects => '유효한 대상이 없습니다';

  @override
  String get galleryRefresh => '새로고침';

  @override
  String get galleryEmpty => '등록된 신원 없음';

  @override
  String galleryCount(int count) {
    return '$count명';
  }

  @override
  String get identityDetail => '신원 상세';

  @override
  String get templateDetail => '템플릿 상세';

  @override
  String get eyeSide => '눈';

  @override
  String get qualityScore => '품질';

  @override
  String get deviceId => '장치';

  @override
  String get dimensions => '크기';

  @override
  String get irisCode => '홍채 코드';

  @override
  String get maskCode => '마스크 코드';

  @override
  String get templateEncrypted => '암호화됨 (FHE)';

  @override
  String get templatePlaintext => '평문';

  @override
  String get encryptedNoPreview => 'FHE 암호화된 템플릿 — 미리보기 불가';

  @override
  String get deleteIdentity => '삭제';

  @override
  String deleteConfirm(String name) {
    return '\"$name\" 신원을 삭제하시겠습니까?';
  }

  @override
  String get deleteConfirmBody => '이 신원과 관련된 모든 템플릿이 영구 삭제됩니다.';

  @override
  String get cancel => '취소';

  @override
  String get delete => '삭제';

  @override
  String get detectLoadImage => '홍채 이미지 불러오기';

  @override
  String get detectButton => '탐지';

  @override
  String get detecting => '탐지 중...';

  @override
  String detectMatch(String name, String hd) {
    return '일치: $name (HD: $hd)';
  }

  @override
  String get detectNoMatch => '일치하는 항목 없음';

  @override
  String detectError(String error) {
    return '탐지 실패: $error';
  }

  @override
  String get connectionError => '서버에 연결할 수 없습니다';

  @override
  String get serverError => '서버 오류';

  @override
  String get logPage => '로그';

  @override
  String get logFilterAll => '전체';

  @override
  String get logFilterMatch => '일치';

  @override
  String get logFilterNoMatch => '불일치';

  @override
  String get logFilterError => '오류';

  @override
  String get logSearchPlaceholder => '신원 검색...';

  @override
  String get logHeaderTime => '시간';

  @override
  String get logHeaderHd => 'HD';

  @override
  String get logHeaderStatus => '상태';

  @override
  String get logHeaderLatency => '지연시간';

  @override
  String get logEmpty => '탐지 결과가 없습니다.';

  @override
  String get logClear => '로그 삭제';

  @override
  String get engine1Label => '엔진 1';

  @override
  String get engine2Label => '엔진 2';
}
