// Test sổ bằng chứng giao thức — kiểm tra sổ không "nói dối" về test.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mybike_app/core/ble/protocol_evidence.dart';

void main() {
  test('id duy nhất, tiêu đề và căn cứ không rỗng', () {
    final ids = kProtocolEvidence.map((e) => e.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final e in kProtocolEvidence) {
      expect(e.title, isNotEmpty, reason: e.id);
      expect(e.basis, isNotEmpty, reason: e.id);
    }
  });

  test('mục "có vector capture thật" và "đối chiếu chéo" phải trỏ tới test có thật', () {
    for (final e in kProtocolEvidence) {
      if (e.level == EvidenceLevel.capturedVector ||
          e.level == EvidenceLevel.crossChecked) {
        expect(e.testFile, isNotNull, reason: '${e.id} thiếu testFile');
        expect(e.testName, isNotNull, reason: '${e.id} thiếu testName');
      }
      if (e.testFile != null) {
        final f = File(e.testFile!);
        expect(f.existsSync(), isTrue, reason: '${e.id}: không có file ${e.testFile}');
        expect(f.readAsStringSync(), contains(e.testName!),
            reason: '${e.id}: không thấy test "${e.testName}" trong ${e.testFile}');
      }
    }
  });

  test('mức capturedVector chỉ cho test có chữ "THẬT" (vector btsnoop)', () {
    for (final e in kProtocolEvidence.where((e) => e.level == EvidenceLevel.capturedVector)) {
      expect(e.testName, contains('THẬT'), reason: e.id);
    }
  });

  test('chỉ capturedVector được coi là đã xác minh', () {
    for (final l in EvidenceLevel.values) {
      expect(l.isVerified, l == EvidenceLevel.capturedVector);
    }
  });

  test('cân bằng cell: giả thuyết, không được phép thêm lệnh điều khiển', () {
    final e = kProtocolEvidence.firstWhere((e) => e.id == 'cell_balancing_control');
    expect(e.level, EvidenceLevel.hypothesis);
    expect(evidenceAllowsNewControl(e), isFalse);
  });

  test('chưa có lệnh điều khiển nào được coi là đủ bằng chứng để mở rộng', () {
    for (final e in kProtocolEvidence.where((e) => e.controlRelated)) {
      expect(evidenceAllowsNewControl(e), isFalse, reason: e.id);
    }
  });

  test('mọi mức có nhãn tiếng Việt', () {
    for (final l in EvidenceLevel.values) {
      expect(l.label, isNotEmpty);
    }
  });
}
