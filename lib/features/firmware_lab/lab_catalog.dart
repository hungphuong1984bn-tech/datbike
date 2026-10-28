// Firmware Lab — catalog char cần kiểm nghiệm trên xe thật.
//
// MỤC ĐÍCH: mỗi char chúng ta đã "dịch" từ firmware (Ghidra/btsnoop/sniff)
// đều chỉ là DỰ ĐOÁN cho đến khi được xác nhận trên xe. Catalog này đóng gói
// dự đoán thành các test có thể PHỦ NHẬN: ghi payload cụ thể → quan sát xe →
// đánh dấu ĐÚNG/SAI + ghi chú trải nghiệm thực tế. Kết quả lưu vào
// firmware_lab_results.jsonl (cùng thư mục ble_logs) để phân tích lại.
//
// Nguồn bằng chứng:
// - [GHIDRA]   decompile mainPcb-1.14.0 (task-memory id 53/54, 23/10)
// - [BTSNOOP]  capture app gốc 4.5.0 (Samsung, 16:16 14/10)
// - [SNIFF]    sniff_read events trong log app Flutter
// - [LOG 23/10] session_20261023T174523 (test settings/khóa/honk live)

enum LabRisk { safe, caution, danger }

/// Cách app GỐC ghi char này (để lab tái lập đúng đường truyền).
enum LabWriteMode { none, plain, protected }

class LabPreset {
  final String label;
  final String data; // nội dung ô input
  final bool hex; // true = parse HEX, false = ASCII text
  final String prediction; // dự đoán RIÊNG cho preset này
  const LabPreset(this.label, this.data, this.hex, this.prediction);
}

class LabCharTest {
  final String id;
  final String name;
  final String uuid;
  final String category;
  final LabWriteMode writeMode;
  final bool canRead;
  final String readExpect; // dự đoán giá trị/khiếu dữ liệu khi ĐỌC
  final List<LabPreset> presets; // dự đoán khi GHI từng preset
  final LabRisk risk;
  final String evidence;
  final String? observed; // đã quan sát thực tế (chưa necessarily khớp dự đoán)
  final String verifyHint; // cách kiểm tra bằng tay trên xe

  const LabCharTest({
    required this.id,
    required this.name,
    required this.uuid,
    required this.category,
    this.writeMode = LabWriteMode.none,
    this.canRead = true,
    this.readExpect = '',
    this.presets = const [],
    this.risk = LabRisk.safe,
    required this.evidence,
    this.observed,
    this.verifyHint = '',
  });

  String get shortId => uuid.substring(0, 8);
}

const labCategories = [
  'SETTINGS — MASTER_CONFIG (protected, boolean)',
  'NGUỒN & KHÓA',
  'THÔNG TIN & TRẠNG THÁI (đọc)',
  'CÒI / TÌM XE / THẺ NFC',
  'SẠC',
  'AUTH / HANDSHAKE (NGUY HIỂM)',
  'DASHBOARD / LOG (đọc mã hoá)',
  'OTA / VESC (KHÔNG ghi tuỳ tiện)',
];

const kLabSettingsBool = 'Handler parse BOOLEAN: payload[0] == ASCII \'1\' (0x31) '
    '? BẬT : TẮT — mọi giá trị khác (kể cả byte 0x01) đều bị hiểu là TẮT '
    '[GHIDRA: addi -49 + moveqz]. Read trả RAW u8 (00/01), KHÔNG phải ASCII.';

final labCatalog = <LabCharTest>[
  // ================= A. SETTINGS =================
  LabCharTest(
    id: 'speed_limit',
    name: 'Giới hạn tốc độ (SPEED_LIMIT)',
    uuid: '0a19a49a-23bc-45ab-b2e9-4bf31665c76b',
    category: labCategories[0],
    writeMode: LabWriteMode.protected,
    readExpect: 'Protected read → 1 byte raw u8: 01 = đang bật, 00 = tắt (default 1, NVS \'speed-limit\').',
    presets: [
      const LabPreset('Ghi "1" (ASCII)', '1', false,
          'Đọc lại ra 01. Trần tốc độ qua VESC chỉ áp khi ECE cũng = 1.'),
      const LabPreset('Ghi "0" (ASCII)', '0', false, 'Đọc lại ra 00.'),
      const LabPreset('Ghi byte 01 (RAW)', '01', true,
          'TEST PHỦ NHẬN: parser so payload[0]-\'1\' → 0x01≠0x31 → bị hiểu là TẮT, đọc lại ra 00.'),
      const LabPreset('Ghi "2" (ASCII)', '2', false,
          'Bị hiểu là TẮT (như \'0\') — đọc lại ra 00. Đây là lỗi UI 3-mục bản cũ.'),
    ],
    risk: LabRisk.caution,
    evidence: 'GHIDRA onWriteSpeedLimit @0x40153d50 · uuid_map PROTECTED_WRITE_CHARS',
    observed: 'LOG 23/10 17:45: ghi \'1\' → đọc 01, ghi \'0\' → đọc 00 (khớp). 24/10 PASS ×3: "cần bật ECE mới limit được".',
    verifyHint: 'Ghi rồi bấm ĐỌC: giá trị đổi đúng 00/01 theo dự đoán = PASS.',
  ),
  LabCharTest(
    id: 'ece_mode',
    name: 'Chế độ ECE (ECE_MODE)',
    uuid: '3b56ac38-60fb-40f8-a42c-fa09e0714e44',
    category: labCategories[0],
    writeMode: LabWriteMode.protected,
    readExpect: 'Protected read → 1 byte raw u8 (default 0).',
    presets: [
      const LabPreset('Ghi "1"', '1', false, 'Đọc lại 01. ✅ VERIFIED 24/10: ECE là CỔNG của giới hạn — SpeedLimit chỉ hiệu lực khi ECE=1; khi ECE bật xe KHÔNG cho chuyển mode lái (phải tắt ECE để chuyển).'),
      const LabPreset('Ghi "0"', '0', false, 'Đọc lại 00. Xe chuyển mode lái được trở lại.'),
      const LabPreset('Ghi byte 01 (RAW)', '01', true, 'Bị hiểu là TẮT → đọc lại 00.'),
    ],
    risk: LabRisk.caution,
    evidence: 'GHIDRA onWriteEceMode @0x40153bd0 · trần áp tại getEceMode() @0x400d6fa7 · LAB 24/10 PASS (cơ chế ECE-gate + khóa mode lái)',
    observed: '✅ 24/10: "cần bật ece mới limit được", "khi ECE bật không thao tác chuyển mode lái được — phải tắt ECE".',
    verifyHint: 'Ghi 1 cả 2 char (ECE + SpeedLimit) → chạy xe xem có bị chặn ~60 km/h (cần tắt/mở xe trước).',
  ),
  LabCharTest(
    id: 'grab_mode',
    name: 'Regen / phanh tái sinh (GRAB_MODE a1d8e7c4)',
    uuid: 'a1d8e7c4-5b3f-4902-8a6e-9c0d2f1e3b4a',
    category: labCategories[0],
    writeMode: LabWriteMode.protected,
    readExpect: 'Protected read → 1 byte raw u8 (default 0).',
    presets: [
      const LabPreset('Ghi "1"', '1', false, 'Đọc lại 01. Người dùng xác nhận đổi giá trị làm đổi dòng nạp ngược (Regen); firmware chưa xác minh mức/độ lớn.'),
      const LabPreset('Ghi "0"', '0', false, 'Đọc lại 00.'),
    ],
    risk: LabRisk.caution,
    evidence: 'GHIDRA onWriteGrabMode @0x40153e30 (cùng parser boolean)',
    observed: 'LOG 23/10: đọc 00, ghi \'1\' → 01 (khớp parser).',
    verifyHint: 'Đổi 0↔1 rồi chạy chậm nơi vắng, nhả ga: so dòng nạp ngược (RECUP kW) giữa hai giá trị.',
  ),
  LabCharTest(
    id: 'idling_turn_off',
    name: 'Tự tắt khi đỗ (IDLING_TURN_OFF)',
    uuid: '69c79762-9dd3-413e-9aaf-bdd147563c93',
    category: labCategories[0],
    writeMode: LabWriteMode.protected,
    readExpect: 'Protected read → 1 byte raw u8 (default 0).',
    presets: [
      const LabPreset('Ghi "1"', '1', false, 'Đọc lại 01. DỰ ĐOÁN: xe đỗ đứng yên một thời gian → tự tắt nguồn (timer chưa rõ giá trị).'),
      const LabPreset('Ghi "0"', '0', false, 'Đọc lại 00.'),
    ],
    risk: LabRisk.caution,
    evidence: 'GHIDRA — nằm trong PROTECTED_WRITE_CHARS (uuid_map) · handler boolean',
    observed: '✅ LAB 23/10 PASS: ghi \'1\' → đọc lại 01. Timer tự tắt chưa đo (cần đỗ xe vài phút).',
    verifyHint: 'Bật = 1, để xe đứng yên (không vặn ga) 5-10 phút xem xe tự tắt không.',
  ),
  LabCharTest(
    id: 'distance_mode',
    name: 'Tự bật/tắt theo khoảng cách (DISTANCE)',
    uuid: '5d681587-c268-4bd3-9560-66ec79dbfdc8',
    category: labCategories[0],
    writeMode: LabWriteMode.protected,
    readExpect: 'Protected read → 2 byte u16 LE (default 8 — đơn vị chưa rõ: mét? ×10?).',
    presets: [
      const LabPreset('Ghi "1"', '1', false, 'Handler parse boolean nhưng char LƯU u16 — ✅ LAB 23/10: ghi \'1\' → đọc lại dec "01 00" (u16 LE = 1) đúng dự đoán.'),
      const LabPreset('Ghi "0"', '0', false, 'Đọc lại về giá trị tắt.'),
      const LabPreset('Ghi byte 02 00 (RAW u16)', '02 00', true, 'Nếu handler chỉ nhìn payload[0] như byte đầu → lưu 2. Đọc lại cho biết thật sự lưu gì.'),
    ],
    risk: LabRisk.caution,
    evidence: 'GHIDRA onWriteDistance @0x401552cc (boolean) · NVS \'distance\' u16 default 8',
    observed: '✅ LAB 23/10: lưu trữ u16 verified ("01 00" sau ghi \'1\'); "xe không có phản ứng" ngay lúc test — hiệu ứng tự bật/tắt theo khoảng cách cần di chuyển mới thấy.',
    verifyHint: 'Bật rồi cầm điện thoại ra xa/tới gần xe (10-20m) quan sát xe tự tắt/bật.',
  ),

  // ================= B. NGUỒN & KHÓA =================
  // ✅ LAB 23/10 đêm (firmware_lab_results_1.jsonl) ĐẢO NGƯỢC 3 nhãn:
  //   7f13fe5c = BẬT/TẮT NGUỒN (char lệnh động — "xe tắt bật đúng")
  //   eec8fd7f = KHÓA AN TOÀN ('1' khóa: cần thẻ NFC mở lại + còi hú khi đá chống)
  //   b0ca953d = ĐÈN XE ('1' bật đèn, khác '1' tắt toàn bộ đèn)
  LabCharTest(
    id: 'lock_bike',
    name: 'BẬT/TẮT NGUỒN — char "lệnh động" 7f13fe5c ✅đã xác minh',
    uuid: '7f13fe5c-1971-4fec-97fd-f90e16cf8c28',
    category: labCategories[1],
    writeMode: LabWriteMode.protected,
    readExpect: 'PLAIN echo 1 byte "30"/"31" = giá trị ghi lần cuối (không mã hoá — đọc ngay không cần decrypt).',
    presets: [
      const LabPreset('Ghi "1" (protected)', '1', false,
          'BẬT nguồn xe. ✅ LAB 23/10: "xe tắt bật đúng, xe chỉ tắt mở không có hành động khác" — KHÔNG phải char khóa như nhãn Ghidra cũ.'),
      const LabPreset('Ghi "0" (protected)', '0', false,
          'TẮT nguồn xe. ✅ ĐÃ XÁC MINH (user pass + btsnoop [1386]).'),
    ],
    risk: LabRisk.danger,
    evidence: 'LAB 23/10 đêm PASS ×4 ("xe tắt bật đúng") · uuid_map config module "ON_OFF_BIKE (char lệnh động)" ĐÚNG · nhãn Ghidra "LOCK @0x40156ba8" SAI',
    observed: '✅ XÁC MINH 23/10 23:40-23:41: đọc trả plain "30" (echo); ghi 0/1 = tắt/bật nguồn, không khóa bánh, không còi.',
    verifyHint: 'Đã xác minh — chỉ test lại khi nghi ngờ.',
  ),
  LabCharTest(
    id: 'power_switch',
    name: 'Còi hú đánh thức / công tắc PLAIN (350d9a82) ✅đã xác minh',
    uuid: '350d9a82-b3f3-4213-bdda-6403be495f53',
    category: labCategories[1],
    writeMode: LabWriteMode.plain,
    readExpect: 'Trả RỖNG trước khi xác thực [UUID_MAP §3].',
    presets: [
      const LabPreset("Ghi '1' (plain)", '1', false,
          '✅ LAB 23/10: xe HÚ 1 tiếng (đánh thức MCU) — ĐÂY CHÍNH LÀ CÒI TÌM XE! Gói đơn KHÔNG tự bật nguồn. App v1.5.6 đã dùng làm Tìm xe.'),
      const LabPreset("Ghi '0' (plain)", '0', false, '✅ LAB 23/10: "không thấy làm gì" — không tắt nguồn, không tác động.'),
    ],
    risk: LabRisk.caution,
    evidence: 'LAB 23/10 23:43: "ghi 1 xe sẽ kêu (dự đoán char tìm xe), ghi 0 không thấy làm gì" · btsnoop Write #11 handle 0x0038',
    observed: '✅ XÁC MINH 23/10: \'1\' = hú; \'0\' = không tác động. Dự đoán cũ "bật nguồn relay" SAI ở trạng thái xe tắt.',
    verifyHint: 'Xe TẮT → ghi \'1\' → nghe còi. Lặp mỗi ~1.5s = chuỗi tìm xe.',
  ),
  LabCharTest(
    id: 'power_protected',
    name: 'KHÓA AN TOÀN (ARM) eec8fd7f ✅đã xác minh — NHÃN "nguồn protected" SAI',
    uuid: 'eec8fd7f-4709-441a-a838-b9eb3066ede4',
    category: labCategories[1],
    writeMode: LabWriteMode.protected,
    readExpect: 'Protected read → dec "00 00" (ý nghĩa chưa rõ — không phản ánh trạng thái khóa).',
    presets: [
      const LabPreset('Ghi "1" (protected) = KHÓA', '1', false,
          '✅ LAB 23/10: xe KHÓA AN TOÀN — BẮT BUỘC quẹt thẻ NFC mới kết nối lại được; ai ĐÁ CHỐNG/dynamic xe → còi HÚ. ⚠️ Chỉ test khi có thẻ NFC trong tay!'),
      const LabPreset('Ghi "0" (protected) = MỞ', '0', false,
          '✅ LAB 23/10: mở khóa an toàn ("ghi 0 sẽ mở ra"). App v1.5.6: nút KHÓA AN TOÀN dùng char này.'),
    ],
    risk: LabRisk.danger,
    evidence: 'LAB 23/10 23:44-23:45 PASS ×5 kèm ghi chú của user · (giải thích lại btsnoop: double-write 0x003a \'1\' = khóa + xác nhận chứ không phải "chốt relay")',
    observed: '✅ XÁC MINH 23/10: \'1\' = khóa (NFC-required + còi chống trộm), \'0\' = mở. KHÔNG phải gói confirmation nguồn.',
    verifyHint: 'KHÓA rồi thử đá chống → còi hú; mở bằng ' '0' ' hoặc quẹt thẻ.',
  ),
  LabCharTest(
    id: 'vesc_programming',
    name: 'CHẾ ĐỘ NẠP VESC / DEV MODE (b0ca953d) ⚠️ PURE XOR TOGGLE',
    uuid: 'b0ca953d-46db-4451-b457-b81696d4e3ae',
    category: labCategories[1],
    writeMode: LabWriteMode.protected,
    readExpect: 'Protected read → 1 byte raw u8 (00 = bình thường, 01 = đang bật VESC programming / Dev Mode).',
    presets: [
      const LabPreset('Đảo trạng thái (XOR Toggle)', '1', false,
          '⚠️ RE2 VERIFIED (onWriteVescProgamming @0x4015565c): Handler BỎ QUA nội dung payload và luôn đảo bit cfg+0x62 (bVar1 ^ 1). Khi = 1: NGỪNG vescPollTask (@0x400db6b0) & CAN watchdog (@0x400d5b02), làm IM trên taplo = 0 và tắt đèn như hệ quả phụ!'),
    ],
    risk: LabRisk.danger,
    evidence: 'GHIDRA RE2 decomp_vescprog.log: FUN_4015565c (onWriteVescProgamming) XOR cfg+0x62 · read @0x401555c9 gọi getVescProgrammingActive (@0x40142dc0)',
    observed: '✅ ĐÍNH CHÍNH 26/10: Phân tích cũ "1=bật đèn, khác 1=tắt đèn" bị SAI do test chẵn/lẻ lần ghi trên hàm XOR toggle! Thực chất đây là cờ VESC Programming / Chế độ phát triển.',
    verifyHint: '⚠️ TUYỆT ĐỐI KHÔNG bấm khi xe đang chạy! Đọc lại sau mỗi lần ghi sẽ thấy giá trị đảo 00 ↔ 01 bất kể ghi gì.',
  ),
  LabCharTest(
    id: 'turn_off_bms',
    name: 'Tắt hẳn BMS (TURN_OFF_BMS)',
    uuid: '1f4108ad-8a70-4165-87d0-88e16f433758',
    category: labCategories[1],
    writeMode: LabWriteMode.protected,
    readExpect: 'Trả RỖNG trước auth [UUID_MAP §3].',
    presets: [
      const LabPreset('Ghi "1"', '1', false,
          'Guard: chỉ chạy khi xe ĐANG BẬT + ĐỨNG YÊN, vTaskDelay(1s) → BMS tắt hẳn: xe MẤT ĐIỆN HOÀN TOÀN (BLE chết luôn). Phải bật lại vật lý. Nếu xe đang tắt → log fw "Couldn\'t turn off..." và KHÔNG chạy.'),
    ],
    risk: LabRisk.danger,
    evidence: 'GHIDRA handler @0x401558e4-adjacent: guard string "Couldn\'t turn off the discharge of bms because the bike is off or moving" + vTaskDelay(1000)',
    observed: '✅ XÁC MINH 23/10 PASS: "xe tắt ngúm không bấm được" — đúng như dự đoán (chế độ cất xe lâu ngày).',
    verifyHint: '⚠️ Chỉ test khi sẵn sàng mở ca-pô bật lại xe. Đã xác minh.',
  ),
  LabCharTest(
    id: 'reset_ble',
    name: 'Factory reset BLE (RESET)',
    uuid: 'a23df519-5279-4fdc-87ef-9b9e65b4a31f',
    category: labCategories[1],
    writeMode: LabWriteMode.protected,
    readExpect: 'Trả RỖNG trước auth.',
    presets: [
      const LabPreset('Ghi "1" (bất kỳ payload ≠ rỗng)', '1', false,
          'MỌI payload khác rỗng đều chạy reset: settings BLE về default, có thể mất bond/tên xe. Log fw: "Factory reset BLE settings".'),
      const LabPreset('Ghi rỗng (00)', '00', true, 'Payload 1 byte 0x00 — dự đoán VẪN chạy (handler chỉ check rỗng).'),
    ],
    risk: LabRisk.danger,
    evidence: 'GHIDRA: mọi payload khác rỗng chạy reset (FUN_401558e4 family)',
    verifyHint: '⚠️ Sau test phải set lại: tên xe, settings. Kiểm tra: speed-limit về default 1? tên xe về "Dat Bike Quantum S1"?',
  ),

  // ================= C. THÔNG TIN =================
  LabCharTest(
    id: 'fw_version',
    name: 'Phiên bản firmware',
    uuid: 'd1da175e-b1b5-4248-8f36-98c9482b8d24',
    category: labCategories[2],
    readExpect: 'PLAIN text "1.14.0" (không mã hoá, cần bond).',
    risk: LabRisk.safe,
    evidence: 'UUID_MAP §2 · char_read events',
    observed: 'Nhiều phiên: luôn "1.14.0".',
    verifyHint: 'Đọc ra đúng chuỗi version = PASS.',
  ),
  LabCharTest(
    id: 'device_serial',
    name: 'Serial xe (DEVICE_SERIAL)',
    uuid: '041d5a06-e35f-42d3-92c8-0d421186d2f3',
    category: labCategories[2],
    readExpect: 'Trước auth: cipher [counter 4B][payload]. Sau auth: decrypt → serial thật.',
    presets: [
      const LabPreset('Đọc', '', false, 'Decrypt ra serial thật dạng "RL9C…" (17 ký tự).'),
    ],
    risk: LabRisk.safe,
    evidence: 'GHIDRA getCharDeviceSerial · app readDeviceSerial',
    observed: '23/10: decrypt = "RL9C4NGSSSCC00187".',
    verifyHint: 'So khớp serial in trên khung xe.',
  ),
  LabCharTest(
    id: 'bike_model',
    name: 'Model xe (MODEL)',
    uuid: '4aae98e9-90b5-492f-8180-9538fa2c843d',
    category: labCategories[2],
    readExpect: 'Protected read → CHUỖI model "QT_S1" (✅ LAB 23/10: không phải byte số 5 như dự đoán — tên model dạng text).',
    risk: LabRisk.safe,
    evidence: 'GHIDRA loadBikeName/build tên theo model @cfg+0x5c · LAB 23/10 dec = "QT_S1"',
    observed: '✅ XÁC MINH 23/10: dec = "QT_S1".',
    verifyHint: 'Đã xác minh.',
  ),
  LabCharTest(
    id: 'fw_name',
    name: 'Tên xe (NAME) — đổi tên THẬT, tồn tại sau reboot',
    uuid: '88c30d2c-f80f-43f8-b0cb-fc1e4ae49be9',
    category: labCategories[2],
    writeMode: LabWriteMode.protected,
    readExpect: 'Decrypt → tên xe hiện tại (build từ model nếu chưa đặt: "Dat Bike Quantum S1").',
    presets: [
      const LabPreset('Đọc tên hiện tại', '', false, 'Ra chuỗi tên xe ≤ 20 ký tự.'),
      const LabPreset('Đặt tên "LAB TEST 23"', 'LAB TEST 23', false, 'Ghi → đọc lại ra đúng tên mới. NVS \'ble-info\'/\'name\' maxLen 20, log fw "Set new name: %s". TÊN CÒN SAU KHI TẮT XE.'),
      const LabPreset('Phục hồi "Dat Bike Quantum S1"', 'Dat Bike Quantum S1', false, 'Đặt lại tên gốc (dùng nếu đã lỡ đổi).'),
    ],
    risk: LabRisk.caution,
    evidence: 'GHIDRA: read=getName cfg+0x28, write=setName FUN_40136040 NVS \'name\' [id 54 — đảo ngược kết luận cũ]',
    observed: '19/19 sample đọc "Dat Bike Quantum S1" (decrypt đúng bằng class thật offline).',
    verifyHint: 'Đặt tên → ngắt kết nối/tắt xe → đọc lại còn tên mới = PASS (chứng minh write thật, không phải echo).',
  ),
  LabCharTest(
    id: 'echo_name',
    name: 'Char 460a5bc5 (Read-Only trong BLEInfo — không có Write handler)',
    uuid: '460a5bc5-a5f5-4968-b548-dc218935245e',
    category: labCategories[2],
    writeMode: LabWriteMode.none,
    readExpect: 'Protected read qua FUN_40154e70. Trong BLEInfo (FUN_40155dfc), Write callback là hàm rỗng FUN_4014f644.',
    presets: const [],
    risk: LabRisk.safe,
    evidence: 'GHIDRA RE2 decomp_reg.log L147-150: Protected Read FUN_40154e70, Write = FUN_4014f644 (no-op)',
    observed: 'Không lưu NVS; tên xe thật nằm ở 88c30d2c.',
    verifyHint: 'Chỉ đọc.',
  ),
  LabCharTest(
    id: 'frame_serial',
    name: 'Đồng bộ giờ RTC Taplo (44e2bde6 — CURRENT_TIME)',
    uuid: '44e2bde6-9cd5-4159-9d43-a3e3f4e9c737',
    category: labCategories[2],
    writeMode: LabWriteMode.protected,
    readExpect: 'PLAIN "28825" tĩnh (firmware không đăng ký read callback động trong BLEInfo).',
    presets: [
      const LabPreset('Ghi giờ hiện tại (giây TRONG NGÀY local)', '__NOW__', false,
          'Protected write chuỗi số giây-trong-ngày-local (0-86399, vd capture app gốc 16:16:47 = \'58607\', 16:16:22 = \'58582\') → TAPLO đổi giờ. Đính chính RE2: \'58607\' trong btsnoop là đồng bộ giờ tự động sau handshake, KHÔNG PHẢI mã PIN xe!'),
    ],
    risk: LabRisk.caution,
    evidence: 'GHIDRA RE2 decomp_reg.log L246-249: Write-Only Protected Write FUN_40154f24 · btsnoop "58607" = 16:16:47 local',
    observed: '✅ syncTime từ màn Cài Đặt hoạt động đúng nhiều phiên.',
    verifyHint: 'Chỉ test ghi giờ khi muốn — taplo sẽ nhảy theo giờ điện thoại.',
  ),
  LabCharTest(
    id: 'manifest',
    name: 'Manifest boards (73d50009)',
    uuid: '73d50009-ed01-4bb1-bdc2-e89b725a91db',
    category: labCategories[2],
    readExpect: 'Decrypt → "1adadba-#-8c02b07-896e9a7" (hash phiên bản board — ✅ LAB 23/10 khớp giá trị sniff cũ; chuỗi "vcu7-#-bms7-ctrl7" là của firmware khác).',
    risk: LabRisk.safe,
    evidence: 'LAB 23/10 PASS · SNIFF 23/10 decrypt',
    observed: '✅ XÁC MINH 23/10: "1adadba-#-8c02b07-896e9a7" ổn định.',
    verifyHint: 'Đã xác minh.',
  ),
  LabCharTest(
    id: 'unknown_2c73e84e',
    name: 'Thống kê Log Buffer nội bộ (2c73e84e — 4×uint32 LE, Read-Only)',
    uuid: '2c73e84e-0150-4be2-928c-dee3e8e21b52',
    category: labCategories[2],
    writeMode: LabWriteMode.none,
    readExpect: 'Protected read → 16 byte = 4 × uint32 LE thống kê linked-list log nội bộ (3 word đầu ổn định, word 4 biến đổi; các byte >16B là rác stale-tail của AttValue).',
    presets: const [],
    risk: LabRisk.safe,
    evidence: 'GHIDRA RE2 decomp_getters2.log (FUN_400edc10/c3c/c64/cf8) + decomp_reg.log L341-345 (Write callback = FUN_4014f644 rỗng)',
    observed: '✅ ĐÍNH CHÍNH 26/10: Phân tích cũ "read u16 / write trigger action" là SAI — char này chỉ đọc 16B (4×u32), không có write handler.',
    verifyHint: 'Đọc và chỉ lấy đúng 16 byte đầu sau giải mã.',
  ),

  // ================= D. CÒI / NFC =================
  LabCharTest(
    id: 'beep_uuid',
    name: 'BEEP-UUID / Token xoay (87efab0d) — PLAIN Read/Write (stub)',
    uuid: '87efab0d-9e32-4ab8-8916-ed7cb72d819a',
    category: labCategories[3],
    writeMode: LabWriteMode.plain,
    readExpect: 'PLAIN Read (FUN_40155a30): trả về token ngẫu nhiên xoay mới sau MỖI lần đọc (không mã hóa Protected Read).',
    presets: [
      const LabPreset('Ghi "1" (plain — như findBike app gốc)', '1', false,
          'GHIDRA RE2: Đăng ký qua FUN_4015030c (PLAIN Write) → setBeepUUID("1") lưu NVS \'ble-info\'/\'beep\'. Không có hàm tiêu thụ trong fw 1.14.0 nên còi không kêu.'),
      const LabPreset('Ghi "0" (plain)', '0', false, 'Lưu "0" vào NVS \'beep\' (stub).'),
    ],
    risk: LabRisk.safe,
    evidence: 'GHIDRA RE2 decomp_reg.log L272-276 (FUN_4015030c PLAIN Read/Write) · setBeepUUID FUN_40156d08 · 00_SCOPE.md L76',
    observed: '✅ ĐÍNH CHÍNH 26/10: Cổng này dùng PLAIN Read/Write (không phải Protected); mỗi lần Read trả 1 giá trị ngẫu nhiên mới. Còi tìm xe thật = plain \'1\' lên 350d9a82.',
    verifyHint: 'Đã xác minh stub. Muốn tìm xe → dùng tính năng Tìm xe (350d9a82).',
  ),
  LabCharTest(
    id: 'add_card',
    name: 'Đăng ký thẻ NFC (ADD_CARD)',
    uuid: 'c75ebe03-ea2f-4c0e-a720-1e7112a72d81',
    category: labCategories[3],
    writeMode: LabWriteMode.protected,
    readExpect: 'Read → 2 byte [addingFlag, 0] — sniff thấy "00 00".',
    presets: [
      const LabPreset('Đọc trạng thái', '', false, '2 byte: byte đầu = đang thêm thẻ hay không (dự đoán 00).'),
      const LabPreset('Ghi "1" → quẹt thẻ mới', '1', false,
          'RfidCardManager "Adding new card..." ~10s: quẹt thẻ MỚI → xe nhận thẻ (thẻ cũ đã có: "Card already existed"). Byte đầu read có thể nhảy 01 trong lúc thêm.'),
      const LabPreset('Ghi "0" (hủy)', '0', false, 'Dự đoán hủy chế độ thêm thẻ (nếu có xử lý).'),
    ],
    risk: LabRisk.caution,
    evidence: 'GHIDRA RfidCardManager strings (card1/card2) · read handler FUN_40151030 trả [flag,0] · write body 0x40151020 misalign chưa parse trọn',
    observed: 'SNIFF dec "00 00".',
    verifyHint: 'Cần THẺ NFC MỚI trong tay mới test ghi — quẹt trong ~10s sau ghi.',
  ),

  // ================= E. SẠC =================
  LabCharTest(
    id: 'charging_profile',
    name: 'Profile sạc (CHARGING) — RAW BYTE, khác mọi setting khác!',
    uuid: '8a2b0d10-9c52-4f5a-9d3e-1f7a0c4b6e21',
    category: labCategories[4],
    writeMode: LabWriteMode.protected,
    readExpect: 'Protected read → 1 byte raw profile (default 0 = Standard).',
    presets: [
      const LabPreset('Ghi byte 00 (Standard)', '00', true, 'Đọc lại 00. Có nhánh riêng trong handler cho giá trị 2.'),
      const LabPreset('Ghi byte 01 (Fast)', '01', true, 'Đọc lại 01.'),
      const LabPreset('Ghi byte 02 (Boost)', '02', true, 'Đọc lại 02 — handler có nhánh bnei==2 riêng.'),
      const LabPreset('Ghi ASCII "1" (0x31) — TEST PHỦ NHẬN', '1', false,
          '✅ LAB 23/10: dec sau ghi = "00 00 31 00…" — byte 0x31 ĐƯỢC LƯU thẳng đúng như dự đoán raw-byte (handler không ép kiểu).'),
    ],
    risk: LabRisk.caution,
    evidence: 'GHIDRA handler @0x40154240: l8ui payload[0] → s8i obj+2 → putUChar NVS \'charging\'/\'defaultProfile\'',
    observed: '✅ LAB 23/10: lưu raw OK nhưng user xác nhận TÍNH NĂNG THUỘC DÒNG ERA — xe Quantum S1 không có profile sạc, ghi vô hại không hiệu ứng.',
    verifyHint: 'Không cần test thêm trên Quantum S1 (tính năng Era).',
  ),

  // ================= F. AUTH =================
  LabCharTest(
    id: 'app_auth',
    name: 'APP_AUTH counter (c8eaf27b) — CHỈ ĐỌC',
    uuid: 'c8eaf27b-9fb7-4bc3-b11a-bf68c97b1b1f',
    category: labCategories[5],
    readExpect: '4 byte counter LE — dự đoán tăng sau mỗi lần auth/write.',
    risk: LabRisk.danger,
    evidence: 'GATT capture: nhận app-token 12B ASCII, đọc trả 4B counter',
    observed: '—',
    verifyHint: 'CHỈ bấm ĐỌC. GHI payload lạ có thể phá phiên/ buộc self-register lại.',
  ),
  LabCharTest(
    id: 'authorization',
    name: 'AUTHORIZATION nonce (5e9a2c71) — CHỈ ĐỌC',
    uuid: '5e9a2c71-0b3d-4f86-a1c2-7d4e8f0b9a63',
    category: labCategories[5],
    readExpect: '16 byte = 15B nonce + 1B status (00 = chưa auth, 01 = đã chấp nhận).',
    risk: LabRisk.danger,
    evidence: 'BTSNOOF + handshake đã implement (authenticateSession)',
    observed: '—',
    verifyHint: 'Đọc khi đã auth → byte 16 = 01. GHI sai HMAC sẽ làm xe drop link.',
  ),
  LabCharTest(
    id: 'unknown_91e84eb0',
    name: 'Cờ trạng thái Auth 91e84eb0 (Protected Read 1B = 0x01)',
    uuid: '91e84eb0-dea0-436f-a157-f21d89443b32',
    category: labCategories[5],
    readExpect: 'Protected read → 1 byte tĩnh 0x01 (feature-present flag).',
    presets: [
      const LabPreset('Đọc', '', false, 'Giải mã Protected Read trả 01 tĩnh.'),
    ],
    risk: LabRisk.safe,
    evidence: 'RE2 00_SCOPE.md L77: Protected Read luôn trả dec "01"',
    observed: '✅ XÁC MINH RE2: dec "01" tĩnh.',
    verifyHint: 'Chỉ đọc.',
  ),
  LabCharTest(
    id: 'legacy_app_auth',
    name: 'LEGACY_APP_AUTH (4cb05df8 — Protected Read 12B)',
    uuid: '4cb05df8-9c3a-4d7e-9b2f-8e1a3c6d5b41',
    category: labCategories[5],
    readExpect: 'Protected read → 12 byte dữ liệu auth đổi theo session.',
    presets: [
      const LabPreset('Đọc', '', false, 'Giải mã Protected Read ra 12B dữ liệu auth.'),
    ],
    risk: LabRisk.caution,
    evidence: 'RE2 00_SCOPE.md L78: Protected Read trả 12B dữ liệu auth theo phiên',
    observed: '✅ XÁC MINH RE2: 12B auth data.',
    verifyHint: 'Chỉ đọc, không ghi.',
  ),

  // ================= G. DASHBOARD / LOG =================
  LabCharTest(
    id: 'dashboard',
    name: 'Dashboard telemetry (6d2eb205) — verify bảng offset',
    uuid: '6d2eb205-6f9b-4ecf-bb1b-a5fad127c66c',
    category: labCategories[6],
    readExpect: '45B cipher → decrypt (session key) → protobuf. Offset CHUẨN 21/10: ODO@0, speed@4, current@8 (ÂM=xả pin, DƯƠNG=sạc), V@15, SoC@19, BMS@20/motor@24/ECU@28, kmLeft@37.',
    presets: [
      const LabPreset('Đọc 1 lần (decrypt)', '', false, 'Speed/voltage khớp thực tế xe = xác nhận luôn bảng offset dashboard.'),
    ],
    risk: LabRisk.safe,
    evidence: 'Bảng offset chuẩn 21/10 (task-memory) · poll 700ms hoạt động mọi phiên',
    observed: 'Hiển thị dashboard chính xác nhiều phiên.',
    verifyHint: 'Đọc khi biết rõ trạng thái xe (đang bật, đứng yên → speed 0).',
  ),
  LabCharTest(
    id: 'bike_log',
    name: 'Bike log 108B (018e6a6f)',
    uuid: '018e6a6f-4bda-7b07-8586-1298248a8d5c',
    category: labCategories[6],
    readExpect: '108B cipher → decrypt → bike log protobuf (log phụ của xe).',
    presets: [
      const LabPreset('Đọc', '', false, '✅ LAB 23/10: dec = protobuf chứa TÊN XE ("Dat Bike Quantum S1") + MODEL ("QT_S1") + SERIAL ("RL9C4NGSSSCC00187") + trường số — log định danh xe.'),
    ],
    risk: LabRisk.safe,
    evidence: 'LAB 23/10 PASS · chars 207B/108B',
    observed: '✅ XÁC MINH 23/10: protobuf 0a=NAME 12=MODEL 1a=SERIAL 20=…',
    verifyHint: 'Đã xác minh.',
  ),
  LabCharTest(
    id: 'battery_log',
    name: 'Battery log 207B (84c7be0b)',
    uuid: '84c7be0b-7619-45c1-a503-95f4ff8736ed',
    category: labCategories[6],
    readExpect: '207B cipher → decrypt → protobuf pin: V, I, 13 cell, nhiệt, protection.',
    presets: [
      const LabPreset('Đọc', '', false, 'So khớp điện áp pin thực (76-77V đầy).'),
    ],
    risk: LabRisk.safe,
    evidence: 'fetchBatteryDetails hoạt động · tab Pin app',
    observed: 'Dữ liệu pin hiển thị đúng nhiều phiên.',
    verifyHint: 'Đọc → so với tab Pin.',
  ),

  // ================= H. OTA / VESC =================
  LabCharTest(
    id: 'vesc_char',
    name: 'VESC Snapshot (35a9b4f6) — 3 × float32 LE (12B), CHỈ ĐỌC',
    uuid: '35a9b4f6-e5f5-405b-9b08-ada85d78cc12',
    category: labCategories[7],
    readExpect: 'Protected read → 12 byte = 3 × float32 LE: [dòng motor (0.0 khi đỗ), điện áp VESC (~76.6V), duty cycle (~0.854)].',
    risk: LabRisk.safe,
    evidence: 'GHIDRA RE2 00_SCOPE.md L74: handler FUN_40156db0 đóng gói 3 float (vtable+0x54, *(obj+0x1c), *(obj+4))',
    observed: '✅ ĐÍNH CHÍNH 26/10: Gói thật dài 12B (3 float, float đầu = 0.0 khi xe đứng yên nên phân tích cũ nhầm là 2 float).',
    verifyHint: 'Đọc → lấy đủ 12 byte đầu giải mã thành 3 số float32 LE.',
  ),
  LabCharTest(
    id: 'ota_service',
    name: 'OTA service (68311857 / 07765f94 / 46a7b351 / 4244dedb / e0b2b4b4)',
    uuid: '68311857-4f93-4060-a42d-16da35a5843c',
    category: labCategories[7],
    readExpect: 'e0b2b4b4: read/write — log 21/29 ghi \'success\' 108 lần mà xe im lặng. writeNoResp chars: đọc thử.',
    presets: [
      const LabPreset('Đọc e0b2b4b4', '', false, 'Giá trị chưa rõ — ghi nhận để đối chiếu.'),
    ],
    risk: LabRisk.danger,
    evidence: 'GATT table: toàn bộ writeNoResp · uuid_map: FAST_OTA_SERVICE + MAINPCB_FIRMWARE char',
    observed: 'Ghi 108 lần không tác dụng (21/10).',
    verifyHint: '⚠️ KHÔNG ghi — OTA nửa vời có thể brick xe. Chỉ đọc.',
  ),
];
