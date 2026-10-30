// OTA firmware — metadata công khai (đã verify thật 2026-10-13).
// GET https://vms.dat.bike/api/v1/firmware?beta={0,1}&dev={0,1}
// → { version, releaseNote, firmwares: { bms: {location, revision, hash}, ... } }
// File .bin/.zip nằm trên S3 công khai, tải trực tiếp.
// Truyền BLE (FAST_OTA service) là Phase 2 — cần UUID OTA chưa confirm.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class BoardFirmware {
  final String board;
  final String location;
  final String? revision;
  final String? hash;

  const BoardFirmware({
    required this.board,
    required this.location,
    this.revision,
    this.hash,
  });
}

class FirmwareRelease {
  final String version;
  final String releaseNote;
  final bool isBeta;
  final bool isDev;
  final List<BoardFirmware> boards;

  const FirmwareRelease({
    required this.version,
    required this.releaseNote,
    required this.isBeta,
    required this.isDev,
    required this.boards,
  });
}

class OtaService {
  static const _base = 'https://vms.dat.bike/api/v1';

  Future<FirmwareRelease?> fetchLatest({bool beta = false, bool dev = false}) async {
    try {
      final uri = Uri.parse('$_base/firmware?beta=${beta ? 1 : 0}&dev=${dev ? 1 : 0}');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        throw OtaException('Lỗi tải metadata firmware: HTTP ${res.statusCode}');
      }
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final firmwares = (json['firmwares'] as Map<String, dynamic>? ?? {});
      final boards = <BoardFirmware>[];
      for (final entry in firmwares.entries) {
        final v = entry.value as Map<String, dynamic>;
        boards.add(BoardFirmware(
          board: entry.key,
          location: v['location'] as String,
          revision: v['revision'] as String?,
          hash: v['hash'] as String?,
        ));
      }
      return FirmwareRelease(
        version: json['version'] as String? ?? '?',
        releaseNote: json['releaseNote'] as String? ?? '',
        isBeta: json['isBeta'] == true,
        isDev: json['isDev'] == true,
        boards: boards,
      );
    } catch (_) {
      // Khi lỗi mạng hoặc không có kết nối, trả về null thay vì dữ liệu giả
      return null;
    }
  }

  /// Tải board về file tạm, báo progress 0.0→1.0.
  Future<File> downloadBoard(
    BoardFirmware board, {
    required void Function(double progress) onProgress,
  }) async {
    final uri = Uri.parse(board.location);
    final req = http.Request('GET', uri);
    final res = await http.Client().send(req).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw OtaException('S3 trả HTTP ${res.statusCode} cho ${board.board}');
    }
    final total = res.contentLength ?? 0;
    // KHÔNG dùng Directory.systemTemp — trên Android là /data/local/tmp,
    // app không có quyền ghi (crash). Dùng cache dir của app.
    final tmp = await getTemporaryDirectory();
    final file = File('${tmp.path}/datbike-${board.board}-${board.revision ?? "x"}.bin');
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }
    } finally {
      await sink.close();
    }
    onProgress(1.0);

    // Kiểm tra tính toàn vẹn (Checksum / Hash verification)
    if (board.hash != null && board.hash!.trim().isNotEmpty) {
      final expectedHash = board.hash!.trim().toLowerCase();
      final bytes = await file.readAsBytes();
      final String calculatedHash;
      if (expectedHash.length == 32) {
        calculatedHash = md5.convert(bytes).toString().toLowerCase();
      } else {
        calculatedHash = sha256.convert(bytes).toString().toLowerCase();
      }
      if (calculatedHash != expectedHash) {
        try {
          await file.delete();
        } catch (_) {}
        throw OtaException(
          'Mã băm firmware không khớp (Toàn vẹn tệp hỏng)! '
          'Kỳ vọng: $expectedHash, Tính toán: $calculatedHash',
        );
      }
    }

    return file;
  }
}

class OtaException implements Exception {
  final String message;
  OtaException(this.message);
  @override
  String toString() => message;
}
