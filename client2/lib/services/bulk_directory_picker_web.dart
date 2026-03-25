import 'dart:typed_data';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

import '../providers/bulk_enroll_provider.dart';

Future<List<BulkPickedFile>> pickBulkDirectoryFiles() async {
  final input = html.FileUploadInputElement();
  input.multiple = true;
  input.setAttribute('webkitdirectory', '');
  input.click();

  await input.onChange.first;
  final files = input.files;
  if (files == null || files.isEmpty) {
    return const <BulkPickedFile>[];
  }

  final picked = <BulkPickedFile>[];
  for (final file in files) {
    final webkitRelativePath =
        (js_util.getProperty(file, 'webkitRelativePath') as String?) ?? '';
    final relativePath =
        webkitRelativePath.isNotEmpty ? webkitRelativePath : file.name;

    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoad.first;

    final result = reader.result;
    Uint8List? bytes;
    if (result is ByteBuffer) {
      bytes = Uint8List.view(result);
    } else if (result is Uint8List) {
      bytes = result;
    }
    if (bytes == null) continue;

    picked.add(BulkPickedFile(relativePath: relativePath, bytes: bytes));
  }

  return picked;
}
