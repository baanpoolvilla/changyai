/// ตัวช่วยกลางสำหรับ "เลือกรูปเพื่ออัปโหลด" ทุกหน้าในแอป
///
/// เหตุผลที่ต้องมีไฟล์นี้ — บั๊กที่เคยเจอ:
/// แอปนี้รันเป็น Flutter **web** (Safari บนมือถือ) ซึ่ง image_picker_for_web
/// จะย่อรูปก็ต่อเมื่อมี maxWidth หรือ maxHeight เท่านั้น
/// ถ้าใส่แค่ imageQuality มันจะ `drawImage(source, 0, 0)` คือวาดที่ความละเอียดเดิม
/// แล้วแค่ re-encode ใหม่ ผลคือรูปจาก iPhone (12–48MP) ยังใหญ่หลาย MB
/// จนชน file_size_limit ของ Supabase Storage → 413 → "ไฟล์มีขนาดใหญ่เกินไป"
///
/// ซ้ำร้าย imageQuality มีผลเฉพาะ jpeg/webp — ถ้าเป็น png/heic เบราว์เซอร์จะ
/// encode กลับเป็น png แบบ lossless ซึ่ง "ใหญ่กว่าไฟล์ต้นฉบับ" ได้ด้วยซ้ำ
///
/// ทุกจุดที่เลือกรูปเพื่ออัปโหลดจึงต้องเรียกผ่านฟังก์ชันในไฟล์นี้ ห้ามเรียก
/// ImagePicker ตรง ๆ ไม่งั้นบั๊กเดิมจะกลับมา
library;

import 'package:image_picker/image_picker.dart';

/// ด้านยาวสูงสุดของรูปหลังย่อ (px)
/// 1600 พอสำหรับรูปหลักฐานงานซ่อม (อ่านรายละเอียดรอยรั่ว/เลขมิเตอร์ได้)
/// และได้ไฟล์ราว 300–600 KB ซึ่งอัปโหลดผ่านเน็ตมือถือได้สบาย
const double kUploadMaxDimension = 1600;

/// คุณภาพ JPEG หลังย่อ
const int kUploadImageQuality = 80;

/// เพดานขนาดไฟล์ที่ยอมให้อัปโหลด (ต้องไม่เกิน file_size_limit ของ bucket)
const int kUploadMaxBytes = 10 * 1024 * 1024; // 10 MB

/// เลือกรูป 1 รูป (กล้องหรือแกลเลอรี) พร้อมย่อขนาดอัตโนมัติ
Future<XFile?> pickUploadImage(ImagePicker picker, ImageSource source) {
  return picker.pickImage(
    source: source,
    maxWidth: kUploadMaxDimension,
    maxHeight: kUploadMaxDimension,
    imageQuality: kUploadImageQuality,
  );
}

/// เลือกได้หลายรูปจากแกลเลอรี พร้อมย่อขนาดอัตโนมัติ
Future<List<XFile>> pickUploadImages(ImagePicker picker) {
  return picker.pickMultiImage(
    maxWidth: kUploadMaxDimension,
    maxHeight: kUploadMaxDimension,
    imageQuality: kUploadImageQuality,
  );
}

/// นามสกุลไฟล์สำหรับตั้งชื่อ object ใน Storage
///
/// ห้ามใช้ [XFile.path] เด็ดขาด — บนเว็บมันคือ blob URL
/// (`blob:https://changyai.vercel.app/9f0e-...`) ซึ่งไม่มีนามสกุลไฟล์
/// `path.split('.').last` จะได้ `app/9f0e-...` ติดมาทั้ง slash
/// ทำให้ object key กลายเป็นโฟลเดอร์ซ้อนและไม่มีนามสกุล
/// [XFile.name] คือชื่อไฟล์จริงทั้งบนเว็บและ native
String uploadExtension(XFile file) {
  const fallback = 'jpg';
  const allowed = {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'};
  final name = file.name;
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return fallback;
  final ext = name.substring(dot + 1).toLowerCase();
  return allowed.contains(ext) ? ext : fallback;
}

/// ไฟล์ใหญ่เกินเพดาน — ตรวจฝั่ง client ก่อนยิงขึ้น server
/// จะได้ไม่ต้องรออัปโหลดจนจบแล้วค่อยเจอ 413 (เปลืองเน็ตมือถือ)
class FileTooLargeException implements Exception {
  final int bytes;
  final int limitBytes;

  const FileTooLargeException(this.bytes, this.limitBytes);

  String get _mb => (bytes / 1024 / 1024).toStringAsFixed(1);
  String get _limitMb => (limitBytes / 1024 / 1024).toStringAsFixed(0);

  /// ข้อความภาษาไทยพร้อมแสดงผล (ใช้โดย friendlyError)
  String get thaiMessage =>
      'ไฟล์มีขนาด $_mb MB เกินที่ระบบรับได้ ($_limitMb MB) กรุณาเลือกรูปที่เล็กลง';

  @override
  String toString() => 'FileTooLargeException($bytes > $limitBytes)';
}
