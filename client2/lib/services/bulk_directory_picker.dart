import '../providers/bulk_enroll_provider.dart';
import 'bulk_directory_picker_stub.dart'
    if (dart.library.html) 'bulk_directory_picker_web.dart' as impl;

Future<List<BulkPickedFile>> pickBulkDirectoryFiles() {
  return impl.pickBulkDirectoryFiles();
}
