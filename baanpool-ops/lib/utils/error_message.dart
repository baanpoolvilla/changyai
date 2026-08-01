import 'package:supabase_flutter/supabase_flutter.dart';

import 'image_upload.dart';

/// แปลง exception จาก Supabase/เครือข่าย ให้เป็นข้อความภาษาไทยที่ผู้ใช้อ่านเข้าใจ
/// แทนการโชว์รหัส error ดิบ เช่น
///   PostgrestException(message: new row violates check constraint..., code: 23514)
/// → "ข้อมูลไม่ถูกต้องตามเงื่อนไขของระบบ กรุณาตรวจสอบข้อมูลที่กรอก"
String friendlyError(Object error) {
  // ─── ตรวจฝั่ง client ก่อนอัปโหลด ───────────────────────
  // บอกขนาดจริงกับเพดาน ผู้ใช้จะได้รู้ว่าต้องเล็กลงแค่ไหน
  if (error is FileTooLargeException) {
    return error.thaiMessage;
  }

  // ─── Supabase: Postgres / PostgREST ───────────────────
  if (error is PostgrestException) {
    switch (error.code) {
      case '42501': // insufficient_privilege (ติด RLS)
      case 'PGRST301':
        return 'คุณไม่มีสิทธิ์ทำรายการนี้ กรุณาติดต่อผู้ดูแลระบบ';
      case '23505': // unique_violation
        return 'มีข้อมูลนี้อยู่แล้วในระบบ';
      case '23503': // foreign_key_violation
        return 'ไม่สามารถทำรายการได้ เพราะข้อมูลนี้ถูกใช้งานอยู่ที่อื่น';
      case '23514': // check_violation
        return 'ข้อมูลไม่ถูกต้องตามเงื่อนไขของระบบ กรุณาตรวจสอบข้อมูลที่กรอก';
      case '23502': // not_null_violation
        return 'กรุณากรอกข้อมูลที่จำเป็นให้ครบถ้วน';
      case '22P02': // invalid_text_representation
        return 'รูปแบบข้อมูลไม่ถูกต้อง';
      case 'PGRST116': // ไม่พบแถวที่ต้องการ
        return 'ไม่พบข้อมูลที่ต้องการ อาจถูกลบไปแล้ว';
      case 'PGRST204': // ไม่พบคอลัมน์ตาม schema cache
        return 'โครงสร้างข้อมูลไม่ตรงกับระบบ กรุณาแจ้งผู้ดูแลระบบ';
    }
    // ไม่รู้จักรหัส — เดาจากข้อความ
    final msg = error.message.toLowerCase();
    if (msg.contains('row-level security') || msg.contains('policy')) {
      return 'คุณไม่มีสิทธิ์ทำรายการนี้ กรุณาติดต่อผู้ดูแลระบบ';
    }
    if (msg.contains('jwt') || msg.contains('token')) {
      return 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่';
    }
    return 'ระบบขัดข้อง กรุณาลองใหม่อีกครั้ง';
  }

  // ─── Supabase: Auth ───────────────────────────────────
  if (error is AuthException) {
    final msg = error.message.toLowerCase();
    if (msg.contains('invalid login') || msg.contains('credentials')) {
      return 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
    }
    if (msg.contains('expired') || msg.contains('jwt')) {
      return 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่';
    }
    if (msg.contains('email not confirmed')) {
      return 'อีเมลยังไม่ได้ยืนยัน กรุณาตรวจสอบกล่องจดหมาย';
    }
    return 'เข้าสู่ระบบไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }

  // ─── เครือข่าย / Storage ───────────────────────────────
  // ตรวจจากข้อความ ไม่ import dart:io เพราะแอปนี้เป็น Flutter web
  final raw = error.toString();
  if (raw.contains('SocketException') ||
      raw.contains('ClientException') ||
      raw.contains('Failed to fetch') ||
      raw.contains('XMLHttpRequest')) {
    return 'เชื่อมต่ออินเทอร์เน็ตไม่ได้ กรุณาตรวจสอบสัญญาณแล้วลองใหม่';
  }
  if (raw.contains('TimeoutException')) {
    return 'ระบบตอบสนองช้า กรุณาลองใหม่อีกครั้ง';
  }

  // Storage (อัปโหลดรูป/ไฟล์) — เช็คจากข้อความ ไม่อ้าง type ตรงๆ
  if (raw.contains('StorageException')) {
    final low = raw.toLowerCase();
    if (low.contains('exceeded') || low.contains('too large')) {
      return 'ไฟล์มีขนาดใหญ่เกินไป กรุณาเลือกไฟล์ที่เล็กลง';
    }
    if (low.contains('not found') || low.contains('bucket')) {
      return 'ไม่พบที่จัดเก็บไฟล์ กรุณาแจ้งผู้ดูแลระบบ';
    }
    return 'อัปโหลดไฟล์ไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }

  return 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง';
}
