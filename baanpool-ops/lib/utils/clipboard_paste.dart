/// ดักรูปที่ผู้ใช้ "วาง" (Ctrl+V / Cmd+V) ลงหน้าเว็บ
///
/// ช่างมักแคปหน้าจอหรือก๊อปรูปจากแชท LINE มาวางตรง ๆ เร็วกว่าเซฟลงเครื่อง
/// แล้วค่อยกดเลือกไฟล์ — บนเว็บทำได้ผ่าน paste event ของเบราว์เซอร์เท่านั้น
/// (Clipboard ของ Flutter อ่านได้แค่ข้อความ) จึงต้องแยก implementation
/// ตามแพลตฟอร์มด้วย conditional import
library;

import 'package:image_picker/image_picker.dart';

import 'clipboard_paste_stub.dart'
    if (dart.library.js_interop) 'clipboard_paste_web.dart' as impl;

/// นามสกุลที่ Storage policy ของ bucket `photos` ยอมรับ
/// (ต้องตรงกับ migration 057 ไม่งั้นอัปโหลดแล้วโดนปฏิเสธ)
const _mimeToExtension = <String, String>{
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/heic': 'heic',
};

/// ตั้งชื่อไฟล์ให้รูปที่วางมา — ของจริงจากคลิปบอร์ดมักชื่อ `image.png` ซ้ำกันหมด
/// คืน null ถ้าเป็นชนิดที่อัปโหลดไม่ได้ (เช่น gif/svg) ผู้เรียกจะได้แจ้งผู้ใช้
String? pastedImageName(String mimeType) {
  final ext = _mimeToExtension[mimeType.toLowerCase()];
  if (ext == null) return null;
  return 'pasted-${DateTime.now().microsecondsSinceEpoch}.$ext';
}

/// เริ่มดักรูปที่วางเข้ามา คืนฟังก์ชันสำหรับเลิกดัก (ต้องเรียกตอน dispose)
///
/// บนแพลตฟอร์มที่ไม่ใช่เว็บจะไม่ทำอะไรเลย
///
/// [onImages] จะได้เฉพาะรูปที่อัปโหลดได้ ส่วน [onRejected] จะถูกเรียก
/// เมื่อสิ่งที่วางมาเป็นรูปชนิดที่ระบบไม่รับ
void Function() listenForPastedImages(
  void Function(List<XFile> images) onImages, {
  void Function()? onRejected,
}) {
  return impl.listenForPastedImages(onImages, onRejected: onRejected);
}
