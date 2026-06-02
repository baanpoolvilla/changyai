-- =====================================================
-- BaanPool Ops — Migration 041
-- PM Daily Digest: รวม PM ทุกรายการที่ due วันนั้น
-- ส่ง LINE ครั้งเดียวต่อ caretaker ต่อวัน
-- แม้บ้านมี PM 20 รายการ → ส่งแค่ 1 message
-- =====================================================

-- =====================================================
-- 1. ลบ notify_pm_due เดิม (ส่งทีละ PM)
--    แทนด้วย check_pm_due_schedules แบบ digest
-- =====================================================

CREATE OR REPLACE FUNCTION public.check_pm_due_schedules()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caretaker    RECORD;
  v_pm           RECORD;
  v_count        INT := 0;
  v_pm_count     INT;
  v_message      TEXT;
  v_pm_lines     TEXT;
  v_today_start  TIMESTAMPTZ;
  v_today_str    TEXT;
BEGIN
  v_today_start := date_trunc('day', NOW() AT TIME ZONE 'UTC');
  v_today_str   := to_char(CURRENT_DATE, 'DD/MM/YYYY');

  -- วนต่อ caretaker แต่ละคนที่มี PM due วันนี้
  FOR v_caretaker IN
    SELECT DISTINCT
      u.id          AS caretaker_id,
      u.line_user_id,
      u.full_name,
      p.id          AS property_id,
      p.name        AS property_name
    FROM public.pm_schedules   ps
    JOIN public.properties     p  ON p.id  = ps.property_id
    JOIN public.users          u  ON u.id  = p.caretaker_id
    WHERE ps.is_active    = true
      AND ps.next_due_date = CURRENT_DATE
      AND p.caretaker_id  IS NOT NULL
  LOOP

    -- รวมรายการ PM ของบ้านนี้วันนี้
    v_pm_lines := '';
    v_pm_count := 0;

    FOR v_pm IN
      SELECT ps.id, ps.title, ps.description, ps.asset_id
      FROM public.pm_schedules ps
      WHERE ps.is_active     = true
        AND ps.next_due_date = CURRENT_DATE
        AND ps.property_id   = v_caretaker.property_id
      ORDER BY ps.title
    LOOP
      v_pm_count := v_pm_count + 1;
      v_pm_lines := v_pm_lines
        || '  ' || v_pm_count || '. ' || v_pm.title
        || CASE WHEN v_pm.description IS NOT NULL AND v_pm.description != ''
              THEN ' (' || v_pm.description || ')'
              ELSE '' END
        || chr(10);

      -- สร้าง in-app notification รายการ (dedup รายวัน)
      IF NOT EXISTS (
        SELECT 1 FROM public.notifications
        WHERE user_id    = v_caretaker.caretaker_id
          AND reference_id = v_pm.id::TEXT
          AND type       = 'pm'
          AND created_at >= v_today_start
      ) THEN
        INSERT INTO public.notifications (user_id, title, body, type, reference_id)
        VALUES (
          v_caretaker.caretaker_id,
          '🔴 PM วันนี้: ' || v_pm.title,
          '🏠 ' || v_caretaker.property_name || chr(10)
            || '📅 ' || v_today_str,
          'pm',
          v_pm.id::TEXT
        )
        ON CONFLICT DO NOTHING;
      END IF;
    END LOOP;

    -- ถ้าไม่มี PM รายการ → ข้าม
    IF v_pm_count = 0 THEN CONTINUE; END IF;

    -- ตรวจ dedup LINE: ถ้าส่ง digest ไปบ้านนี้แล้ววันนี้ → ข้าม
    -- ใช้ reference_id = 'digest_<property_id>_<date>'
    DECLARE
      v_digest_key TEXT := 'digest_' || v_caretaker.property_id::TEXT || '_' || to_char(CURRENT_DATE, 'YYYYMMDD');
    BEGIN
      IF EXISTS (
        SELECT 1 FROM public.notifications
        WHERE user_id    = v_caretaker.caretaker_id
          AND reference_id = v_digest_key
          AND type       = 'pm_digest'
          AND created_at >= v_today_start
      ) THEN CONTINUE; END IF;

      -- บันทึก digest sentinel (ป้องกันซ้ำ)
      INSERT INTO public.notifications (user_id, title, body, type, reference_id)
      VALUES (
        v_caretaker.caretaker_id,
        '📋 PM วันนี้ ' || v_pm_count || ' รายการ — ' || v_caretaker.property_name,
        v_pm_lines,
        'pm_digest',
        v_digest_key
      ) ON CONFLICT DO NOTHING;
    END;

    -- ส่ง LINE digest ให้ caretaker (1 ข้อความต่อบ้านต่อวัน)
    IF v_caretaker.line_user_id IS NOT NULL AND v_caretaker.line_user_id != '' THEN
      v_message :=
        '🔴 PM ถึงกำหนดวันนี้ — ' || v_caretaker.property_name || chr(10)
        || '📅 ' || v_today_str || chr(10)
        || '📋 มี ' || v_pm_count || ' รายการ:' || chr(10)
        || v_pm_lines
        || '🔗 https://changyai.vercel.app/pm-schedules';

      PERFORM public.send_line_text(v_caretaker.line_user_id, v_message);
    END IF;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;  -- คืนจำนวน caretaker ที่ส่ง digest ไป
END;
$$;

-- =====================================================
-- 2. ทิ้ง notify_pm_due เดิม (ไม่ใช้แล้ว)
-- =====================================================
DROP FUNCTION IF EXISTS public.notify_pm_due(UUID, TEXT, UUID, UUID, DATE, TEXT, UUID);

-- =====================================================
-- 3. pg_cron: รันทุกวัน 08:00 Bangkok (01:00 UTC)
--    ถ้ายังไม่มี cron job → สร้างใหม่
--    ถ้ามีแล้ว (จาก migration_040) → อัปเดต schedule
-- =====================================================
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

-- ลบ job เดิมถ้ามี
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'pm_due_daily_check') THEN
    PERFORM cron.unschedule('pm_due_daily_check');
  END IF;
END $$;

SELECT cron.schedule(
  'pm_due_daily_check',
  '0 1 * * *',
  $$ SELECT public.check_pm_due_schedules(); $$
);

-- =====================================================
-- 4. ลบ trigger trg_work_order_status ถ้ายังหลงเหลือ
-- =====================================================
DROP TRIGGER IF EXISTS trg_work_order_status ON public.work_orders;

-- =====================================================
-- 5. อัปเดต LINE token ใหม่ (เปลี่ยน OA)
--    → แก้ 'PASTE_NEW_TOKEN_HERE' เป็น token จริง
-- =====================================================
-- UPDATE public.app_settings
-- SET value = 'PASTE_NEW_TOKEN_HERE', updated_at = NOW()
-- WHERE key = 'line_messaging_token';

-- =====================================================
-- 6. เคลียร์ line_user_id ทุกคน (หลังเปลี่ยน OA ใหม่)
--    ผู้ใช้ต้อง login ใหม่เพื่อระบบดึง ID ใหม่
--    → uncomment บรรทัดนี้เมื่อพร้อมจะเปลี่ยน OA จริง
-- =====================================================
-- UPDATE public.users SET line_user_id = NULL;

-- =====================================================
-- ตรวจสอบผล
-- =====================================================
SELECT 'migration_041 OK' AS result;

-- ดู cron jobs ที่ active
SELECT jobname, schedule, command, active
FROM cron.job
WHERE jobname = 'pm_due_daily_check';

-- ดู triggers ที่ active บน work_orders
SELECT trigger_name, event_manipulation
FROM information_schema.triggers
WHERE event_object_table = 'work_orders'
ORDER BY trigger_name;
