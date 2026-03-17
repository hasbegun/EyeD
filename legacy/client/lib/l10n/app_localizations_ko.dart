// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'EyeD - 홍채 인식';

  @override
  String get brandName => 'EyeD';

  @override
  String get dashboard => '대시보드';

  @override
  String get devices => '장치';

  @override
  String get enrollment => '등록';

  @override
  String get analysis => '분석';

  @override
  String get history => '이력';

  @override
  String get admin => '관리';

  @override
  String get framesProcessed => '처리된 프레임';

  @override
  String get matches => '일치';

  @override
  String get errors => '오류';

  @override
  String get liveResults => '실시간 결과';

  @override
  String get waitingForResults => '결과를 기다리는 중...';

  @override
  String get noDevicesDetected => '감지된 장치가 없습니다.\n장치가 프레임을 전송하면 자동으로 표시됩니다.';

  @override
  String get frames => '프레임';

  @override
  String get hd => 'HD';

  @override
  String get latency => '지연시간';

  @override
  String get identityName => '이름';

  @override
  String get eyeSideLeft => '왼쪽';

  @override
  String get eyeSideRight => '오른쪽';

  @override
  String get enroll => '등록';

  @override
  String get selectImageFromBrowser => '브라우저에서 이미지를 선택하세요';

  @override
  String get gallery => '갤러리';

  @override
  String get noIdentitiesEnrolled => '등록된 신원이 없습니다.';

  @override
  String get delete => '삭제';

  @override
  String duplicateDetected(String duplicateIdentityId) {
    return '중복 감지 ($duplicateIdentityId)';
  }

  @override
  String enrolled(String templateId) {
    return '등록 완료: $templateId';
  }

  @override
  String get analyze => '분석';

  @override
  String get selectImageAndAnalyze => '이미지를 선택한 후 분석 버튼을 누르세요';

  @override
  String get segmentation => '분할';

  @override
  String get original => '원본';

  @override
  String get pipelineOutputs => '파이프라인 출력';

  @override
  String get normalizedIris => '정규화된 홍채';

  @override
  String get irisCode => '홍채 코드';

  @override
  String get noiseMask => '노이즈 마스크';

  @override
  String get qualityMetrics => '품질 지표';

  @override
  String get sharpness => '선명도';

  @override
  String get offgaze => '시선 이탈';

  @override
  String get occlusion90 => '가림 90';

  @override
  String get occlusion30 => '가림 30';

  @override
  String get pupilIrisRatio => '동공/홍채 비율';

  @override
  String get geometry => '기하 정보';

  @override
  String get pupilCenter => '동공 중심';

  @override
  String get irisCenter => '홍채 중심';

  @override
  String get pupilRadius => '동공 반지름';

  @override
  String get irisRadius => '홍채 반지름';

  @override
  String get eyeOrientation => '안구 방향';

  @override
  String get noGalleryTemplates => '갤러리 템플릿이 없습니다 — 먼저 신원을 등록하세요';

  @override
  String get noMatch => '일치하지 않음';

  @override
  String hdValue(String hd) {
    return 'HD: $hd';
  }

  @override
  String matchIdentity(String id) {
    return '일치 ($id)';
  }

  @override
  String get filterAll => '전체';

  @override
  String get filterMatch => '일치';

  @override
  String get filterNoMatch => '불일치';

  @override
  String get filterError => '오류';

  @override
  String get searchPlaceholder => '장치, 프레임, 신원 검색...';

  @override
  String get headerTime => '시간';

  @override
  String get headerDevice => '장치';

  @override
  String get headerFrame => '프레임';

  @override
  String get headerHd => 'HD';

  @override
  String get headerStatus => '상태';

  @override
  String get headerLatency => '지연시간';

  @override
  String get noResultsMatchFilter => '현재 필터에 일치하는 결과가 없습니다.';

  @override
  String get pollingEvery5s => '5초마다 조회 중';

  @override
  String get serviceGateway => '게이트웨이';

  @override
  String get serviceIrisEngine => '홍채 엔진';

  @override
  String get serviceNats => 'NATS';

  @override
  String get alive => '생존';

  @override
  String get ready => '준비';

  @override
  String get nats => 'NATS';

  @override
  String get circuitBreaker => '서킷 브레이커';

  @override
  String get version => '버전';

  @override
  String get pipeline => '파이프라인';

  @override
  String get gallerySize => '갤러리 크기';

  @override
  String get database => '데이터베이스';

  @override
  String get status => '상태';

  @override
  String get clientPort => '클라이언트 포트';

  @override
  String get monitorPort => '모니터 포트';

  @override
  String get unreachable => '연결 불가';

  @override
  String get connected => '연결됨';

  @override
  String get disconnected => '연결 끊김';

  @override
  String get unknown => '알 수 없음';

  @override
  String get natsClientPortInfo => '4222 (내부) / 9502 (호스트)';

  @override
  String get natsMonitorPortInfo => '8222 (내부) / 9501 (호스트)';

  @override
  String get notFoundCode => '404';

  @override
  String get pageNotFound => '페이지를 찾을 수 없습니다';

  @override
  String get statusLive => '실시간';

  @override
  String get statusOffline => '오프라인';

  @override
  String get videoLive => '실시간';

  @override
  String get videoConnecting => '연결 중';

  @override
  String get videoWaiting => '대기 중';

  @override
  String get videoOffline => '오프라인';

  @override
  String get waitingForVideo => '영상을 기다리는 중...';

  @override
  String get noImages => '이미지 없음';

  @override
  String get eyeSideShortLeft => '좌';

  @override
  String get eyeSideShortRight => '우';

  @override
  String errorPrefix(String error) {
    return '오류: $error';
  }

  @override
  String get noMatchData => '일치 데이터 없음';

  @override
  String get languageName => '한국어';

  @override
  String get datasetPaths => '데이터셋 디렉토리';

  @override
  String get datasetPathsPrimary => '기본';

  @override
  String get datasetPathsExtra => '추가';

  @override
  String get addDirectory => '디렉토리 추가';

  @override
  String get remove => '제거';

  @override
  String get enterAbsolutePath => '절대 경로를 입력하세요 (예: /data/MyDataset)';

  @override
  String get add => '추가';

  @override
  String get cancel => '취소';

  @override
  String get pathAlreadyRegistered => '이미 등록된 경로입니다';

  @override
  String datasetsCount(int count) {
    return '$count개 데이터셋';
  }

  @override
  String get directoryNotFound => '디렉토리를 찾을 수 없습니다';

  @override
  String get close => '닫기';

  @override
  String get bulkEnroll => '일괄 등록';

  @override
  String get bulkEnrollStart => '시작';

  @override
  String get bulkEnrollSubjectFilter =>
      '대상 필터 (쉼표로 구분, 예: 000,001,002) — 비워두면 전체';

  @override
  String get bulkEnrolled => '등록됨';

  @override
  String get bulkDuplicate => '중복';

  @override
  String bulkEnrollComplete(int enrolled, int duplicates, int errors) {
    return '완료: $enrolled건 등록, $duplicates건 중복, $errors건 오류';
  }

  @override
  String get bulkEnrollRunning => '등록 중...';

  @override
  String bulkEnrollProgress(int processed) {
    return '등록 중 $processed건';
  }

  @override
  String get refresh => '새로고침';

  @override
  String get identityDetails => '신원 상세';

  @override
  String get templateId => '템플릿 ID';

  @override
  String get eyeSide => '눈 방향';

  @override
  String get identityId => '신원 ID';

  @override
  String get templates => '템플릿';

  @override
  String get noTemplates => '템플릿 없음';

  @override
  String get codeSize => '코드 크기';

  @override
  String get scales => '스케일';

  @override
  String get deviceId => '장치 ID';

  @override
  String get loading => '로딩 중...';

  @override
  String get maskCode => '마스크 코드';

  @override
  String get themeSystem => '시스템';

  @override
  String get themeLight => '밝게';

  @override
  String get themeDark => '어둡게';

  @override
  String get connectionLost => '연결 끊김';

  @override
  String get connectionLostDesc => '백엔드 서비스에 연결할 수 없습니다.';

  @override
  String get reconnect => '재연결';

  @override
  String get reconnecting => '재연결 중...';

  @override
  String reconnectCountdown(int seconds) {
    return '재연결 ($seconds초)';
  }

  @override
  String connectionRetryCount(int current, int max) {
    return '시도 $current/$max';
  }

  @override
  String get dbInspector => 'DB 검사기';

  @override
  String get dbSchema => '스키마';

  @override
  String get dbBrowse => '탐색';

  @override
  String get dbHeGuide => 'HE 가이드';

  @override
  String get dbSelectTable => '테이블 선택...';

  @override
  String dbRowsTotal(int count) {
    return '총 $count행';
  }

  @override
  String get dbRelationships => '관계';

  @override
  String get dbPrimaryKey => 'PK';

  @override
  String get dbForeignKey => 'FK';

  @override
  String get dbHeEncrypted => 'HE 암호화';

  @override
  String get dbPlaintextNpz => '평문 NPZ';

  @override
  String get dbSize => '크기';

  @override
  String get dbFormat => '형식';

  @override
  String get dbCiphertexts => '암호문';

  @override
  String get dbHexPrefix => '16진수 접두어';

  @override
  String get dbRelatedData => '관련 데이터';

  @override
  String get dbSelectTablePrompt => '테이블을 선택하여 행을 탐색하세요';

  @override
  String get individualEnroll => '개별 등록';

  @override
  String get bulkEnrollTab => '일괄 등록';

  @override
  String get galleryTab => '갤러리';

  @override
  String get leftEye => '왼쪽 눈';

  @override
  String get rightEye => '오른쪽 눈';

  @override
  String get loadFromDisk => '파일 선택';

  @override
  String get notApplicable => 'N/A';

  @override
  String get atLeastOneEyeRequired => '최소 한쪽 눈 이미지가 필요합니다';

  @override
  String get segmentationFailed => '홍채를 찾을 수 없습니다. 더 나은 품질의 이미지를 선택해 주세요.';

  @override
  String duplicateUserDetected(String name) {
    return '중복 감지: $name(으)로 이미 등록됨';
  }

  @override
  String enrollSuccess(int count) {
    return '등록 성공 ($count개 템플릿)';
  }

  @override
  String get selectLocalDirectory => '디렉토리 선택';

  @override
  String get localBulkEnroll => '로컬 디렉토리';

  @override
  String get serverBulkEnroll => '서버 데이터셋';

  @override
  String get scanningDirectory => '디렉토리 스캔 중...';

  @override
  String subjectsFound(int count) {
    return '$count명 발견';
  }

  @override
  String enrollingSubject(int current, int total, String name) {
    return '$total명 중 $current번째 등록 중: $name';
  }

  @override
  String localBulkComplete(int enrolled, int duplicates, int errors) {
    return '완료: $enrolled건 등록, $duplicates건 중복, $errors건 오류';
  }

  @override
  String get noSubjectsFound => '디렉토리에 유효한 대상이 없습니다';

  @override
  String get startEnroll => '등록 시작';
}
