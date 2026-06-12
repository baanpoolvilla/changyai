-- =====================================================
-- BaanPool Ops — Migration 046
-- backfill line_user_id จาก email สำหรับ user ที่ login ผ่าน LINE
-- แต่ line_user_id ใน users table เป็น NULL
--
-- email pattern: line_{lineUserId}@changyai.app
-- → ดึง lineUserId ออกมาเก็บใน line_user_id
-- =====================================================

-- 1. backfill line_user_id สำหรับทุกคนที่ email = line_xxx@changyai.app
--    แต่ line_user_id ยัง NULL หรือ empty
UPDATE public.users
SET line_user_id = split_part(
                    split_part(email, '@', 1),  -- "line_Uxxxxxxx"
                    'line_',                     -- แยกที่ "line_"
                    2                            -- เอาส่วนที่ 2 → "Uxxxxxxx"
                  )
WHERE email LIKE 'line_%@changyai.app'
  AND (line_user_id IS NULL OR line_user_id = '')
  AND split_part(split_part(email, '@', 1), 'line_', 2) != '';

-- 2. อัปเดต trg_notify_pr_created ให้ใช้ fallback จาก email ด้วย
--    กรณี line_user_id ยัง NULL → ดึง LINE ID จาก email
CREATE OR REPLACE FUNCTION public.trg_notify_pr_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_creator_name  TEXT;
  v_property_name TEXT;
  v_message       TEXT;
  v_line_id       TEXT;
  v_recipient     RECORD;
BEGIN
  -- ชื่อผู้สร้าง PR
  SELECT full_name INTO v_creator_name
  FROM public.users WHERE id = NEW.created_by;

  -- ชื่อบ้าน
  SELECT name INTO v_property_name
  FROM public.properties WHERE id = NEW.property_id;

  -- สร้างข้อความ
  v_message :=
    '📋 มีการเปิด PR ใหม่' || chr(10)
    || '📦 ' || NEW.title || chr(10)
    || '🏠 บ้าน: ' || COALESCE(v_property_name, '-') || chr(10)
    || '👤 โดย: ' || COALESCE(v_creator_name, '-') || chr(10)
    || '💰 มูลค่า: ' || COALESCE(NEW.total_price::TEXT, '0') || ' บาท' || chr(10)
    || '🔗 https://changyai.vercel.app/purchase-orders';

  -- แจ้ง CEO (role = 'owner') ทุกคน ทาง LINE + in-app
  FOR v_recipient IN
    SELECT id,
           COALESCE(
             NULLIF(line_user_id, ''),
             CASE WHEN email LIKE 'line_%@changyai.app'
               THEN NULLIF(split_part(split_part(email, '@', 1), 'line_', 2), '')
               ELSE NULL
             END
           ) AS effective_line_id
    FROM public.users
    WHERE role = 'owner'
  LOOP
    -- LINE
    IF v_recipient.effective_line_id IS NOT NULL THEN
      PERFORM public.send_line_text(v_recipient.effective_line_id, v_message);
    END IF;

    -- In-app notification
    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      v_recipient.id,
      '📋 PR ใหม่: ' || NEW.title,
      '👤 โดย: ' || COALESCE(v_creator_name, '-') || chr(10)
        || '🏠 ' || COALESCE(v_property_name, '-') || chr(10)
        || '💰 ' || COALESCE(NEW.total_price::TEXT, '0') || ' บาท',
      'work_order',
      NEW.id::TEXT
    ) ON CONFLICT DO NOTHING;
  END LOOP;

  RETURN NEW;
END;
$$;

-- ─────────────────────────────────────────────────────
-- ตรวจสอบผล
-- ─────────────────────────────────────────────────────
SELECT 'migration_046 OK' AS result;

-- ดู CEO users ทั้งหมดพร้อม line_user_id
SELECT full_name, role, email,
       line_user_id,
       CASE WHEN line_user_id IS NOT NULL THEN 'มี LINE ID ✓'
            ELSE 'ยังไม่มี LINE ID ✗'
       END AS status
FROM public.users
WHERE role = 'owner'
ORDER BY full_name;
