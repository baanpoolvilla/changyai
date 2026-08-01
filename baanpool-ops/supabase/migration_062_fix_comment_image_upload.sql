-- =====================================================
-- migration_062 — แก้บั๊ก "แนบรูปในคอมเมนต์แล้วขึ้นว่าไฟล์ใหญ่เกินไป"
-- =====================================================
--
-- อาการ: แนบรูปในคอมเมนต์ใบงาน/PO แล้วขึ้น
--        "เพิ่มความคิดเห็นล้มเหลว: ไฟล์มีขนาดใหญ่เกินไป กรุณาเลือกไฟล์ที่เล็กลง"
--
-- สาเหตุ: bucket po-receipts ถูกตั้ง file_size_limit = 10 MB ไว้ตั้งแต่
--         migration_029 แต่ฝั่งแอป (Flutter web) ไม่ได้ย่อรูปจริง
--         เพราะ image_picker_for_web จะย่อก็ต่อเมื่อส่ง maxWidth/maxHeight
--         ถ้าส่งแค่ imageQuality มันจะวาดรูปที่ความละเอียดเดิม
--         → รูปจาก iPhone (12–48MP) ทะลุ 10 MB → Storage ตอบ 413
--
-- ตัวแก้หลักอยู่ฝั่งแอป (lib/utils/image_upload.dart ย่อเหลือ 1600px
-- ได้ไฟล์ราว 300–600 KB) ไฟล์นี้เป็นเพียง "ตาข่ายกันตก" เผื่อมีรูป
-- ที่ย่อแล้วยังใหญ่ผิดปกติ เช่น พาโนรามา หรือภาพที่เบราว์เซอร์
-- encode กลับเป็น PNG แบบ lossless
--
-- ปลอดภัยต่อการรันซ้ำ (idempotent)
-- =====================================================

-- ─── ขยายเพดานขนาดไฟล์ + รองรับ HEIF ─────────────────
-- 50 MB ให้ตรงกับ bucket photos (ซึ่งใช้ค่า default ของโปรเจกต์)
-- เพิ่ม image/heif เพราะ iPhone รุ่นใหม่ส่ง heif มาแทน heic ได้
UPDATE storage.buckets
SET
  file_size_limit = 52428800,  -- 50 MB
  allowed_mime_types = ARRAY[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif'
  ]
WHERE id = 'po-receipts';

-- bucket ของใบเสร็จค่าใช้จ่ายด่วน (ถ้ามีอยู่แล้ว) ให้ใช้เพดานเดียวกัน
-- ถ้ายังไม่มี bucket นี้ บรรทัดนี้จะไม่ทำอะไร — ดูผลตรวจสอบด้านล่าง
UPDATE storage.buckets
SET
  file_size_limit = 52428800,
  allowed_mime_types = ARRAY[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif'
  ]
WHERE id = 'expense-receipts';

-- ─── ตรวจสอบผล ────────────────────────────────────────
SELECT 'migration_062 OK' AS result;

-- ต้องเห็น po-receipts = 52428800
-- และควรเช็คด้วยว่ามี bucket 'expense-receipts' อยู่จริงหรือไม่
-- (โค้ด quick_expense_screen.dart อัปโหลดเข้า bucket นี้
--  แต่ไม่เคยมี migration ไหนสร้างไว้ — ถ้าไม่ขึ้นในผลลัพธ์
--  แปลว่าต้องไปสร้างใน Dashboard ก่อน ไม่งั้นฟีเจอร์นั้นจะพัง)
SELECT
  id,
  public,
  file_size_limit,
  ROUND(file_size_limit / 1048576.0) AS limit_mb,
  allowed_mime_types
FROM storage.buckets
ORDER BY id;
