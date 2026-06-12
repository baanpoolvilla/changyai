-- =====================================================
-- BaanPool Ops — Migration 047
-- แก้ line_user_id ที่อาจมี lowercase 'u' ให้เป็น uppercase 'U'
--
-- ปัญหา: Supabase Auth lowercase email อัตโนมัติ
--   email เก็บ: line_u5de79f...@changyai.app  (u lowercase)
--   LINE API ส่งมา: U5de79f...                (U uppercase)
--   migration_046 extract จาก email → ได้ lowercase → LINE ปฏิเสธ
--
-- LINE user ID ขึ้นต้นด้วย 'U' เสมอ
-- =====================================================

-- 1. แก้ line_user_id ที่เป็น NULL ด้วยการ extract จาก email + uppercase ตัวแรก
UPDATE public.users
SET line_user_id =
  UPPER(LEFT(
    split_part(split_part(email, '@', 1), 'line_', 2),
    1
  ))
  || SUBSTRING(
    split_part(split_part(email, '@', 1), 'line_', 2),
    2
  )
WHERE email LIKE 'line_%@changyai.app'
  AND (line_user_id IS NULL OR line_user_id = '')
  AND LENGTH(split_part(split_part(email, '@', 1), 'line_', 2)) > 1;

-- 2. แก้ line_user_id ที่ extract ไปแล้วแต่ตัวแรก lowercase (จาก migration_046)
UPDATE public.users
SET line_user_id =
  UPPER(LEFT(line_user_id, 1)) || SUBSTRING(line_user_id, 2)
WHERE email LIKE 'line_%@changyai.app'
  AND line_user_id IS NOT NULL
  AND line_user_id != ''
  AND LEFT(line_user_id, 1) != UPPER(LEFT(line_user_id, 1));

-- ─────────────────────────────────────────────────────
-- ตรวจสอบผล: ดู line_user_id ของทุก user
-- ─────────────────────────────────────────────────────
SELECT 'migration_047 OK' AS result;

SELECT
  full_name,
  role,
  LEFT(email, 40) AS email_prefix,
  line_user_id,
  CASE
    WHEN line_user_id IS NULL OR line_user_id = '' THEN '❌ ยังไม่มี LINE ID'
    WHEN LEFT(line_user_id, 1) = 'U' THEN '✅ LINE ID ถูกต้อง'
    ELSE '⚠️ LINE ID ผิดรูปแบบ: ' || line_user_id
  END AS status
FROM public.users
ORDER BY role, full_name;
