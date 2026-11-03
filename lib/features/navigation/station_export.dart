// Chia sẻ/xuất một đoạn văn bản (CSV/JSON) qua bảng chia sẻ hệ thống.

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Ghi [content] vào tệp tạm tên [fileName] rồi mở bảng chia sẻ. Ném lỗi để nơi gọi hiển thị.
Future<void> shareTextFile(String fileName, String content, {String? caption}) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$fileName');
  await f.writeAsString(content, flush: true);
  await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: caption));
}
