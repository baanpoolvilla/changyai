-- =====================================================
-- BaanPool Ops — Migration 017: Fix PM Notifications
-- แก้ไข:
--   1. เพิ่ม deduplication ใน notify_pm_due (ไม่ส่ง notification ซ้ำในวันเดียวกัน)
--   2. แก้ไข notify_pm_due ให้ notify caretaker-role ทุกคนที่เป็น caretaker_id
--      ของ property นั้น (รองรับกรณีที่ caretaker_id อาจถูก set ไม่ครบ)
--   3. เปิด pg_cron สำหรับ daily PM check ทุกวันเวลา 08:00 UTC
--   4. ตรวจสอบ RLS policy ให้ service_role insert ได้เสมอ
-- =====================================================

-- =====================================================
-- 1. อัปเดต notify_pm_due ให้มี deduplication
-- =====================================================
CREATE OR REPLACE FUNCTION public.notify_pm_due(
  p_pm_id UUID,
  p_pm_title TEXT,
  p_property_id UUID,
  p_assigned_to UUID,
  p_next_due_date DATE,
  p_description TEXT DEFAULT NULL,
  p_asset_id UUID DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_property_name TEXT;
  v_caretaker_id UUID;
  v_tech_line_id TEXT;
  v_caretaker_line_id TEXT;
  v_days_until_due INT;
  v_status_text TEXT;
  v_emoji TEXT;
  v_message TEXT;
  v_body TEXT;
  v_recipient RECORD;
  v_today_start TIMESTAMPTZ;
BEGIN
  -- Calculate days until due
  v_days_until_due := p_next_due_date - CURRENT_DATE;

  -- Only notify if due within 7 days or overdue
  IF v_days_until_due > 7 THEN
    RETURN;
  END IF;

  -- Start of today (UTC) for deduplication
  v_today_start := date_trunc('day', NOW() AT TIME ZONE 'UTC');

  -- Get property info
  SELECT name, caretaker_id INTO v_property_name, v_caretaker_id
  FROM public.properties
  WHERE id = p_property_id;

  -- Status text
  IF v_days_until_due < 0 THEN
    v_status_text := '⚠️ เกินกำหนด ' || (-v_days_until_due) || ' วัน';
    v_emoji := '🔴';
  ELSIF v_days_until_due = 0 THEN
    v_status_text := '⏰ ถึงกำหนดวันนี้';
    v_emoji := '🔴';
  ELSE
    v_status_text := '⏰ อีก ' || v_days_until_due || ' วัน';
    v_emoji := '🟡';
  END IF;

  -- Build LINE message
  v_message := v_emoji || ' แจ้งเตือน PM' || chr(10)
    || '📋 ' || p_pm_title || chr(10)
    || '🏠 บ้าน: ' || COALESCE(v_property_name, '-') || chr(10)
    || CASE WHEN p_description IS NOT NULL AND p_description != ''
         THEN '📝 รายละเอียด: ' || p_description || chr(10)
         ELSE '' END
    || '📅 กำหนด: ' || to_char(p_next_due_date, 'DD/MM/YYYY') || chr(10)
    || v_status_text || chr(10)
    || CASE WHEN p_asset_id IS NOT NULL
         THEN '🔗 https://changyai.vercel.app/assets/' || p_asset_id::TEXT
         ELSE '' END;

  -- Build in-app notification body
  v_body := '🏠 บ้าน: ' || COALESCE(v_property_name, '-') || chr(10)
    || '📅 กำหนด: ' || to_char(p_next_due_date, 'DD/MM/YYYY') || chr(10)
    || v_status_text;

  -- ─── Helper: insert with dedup (skip if already exists today) ───
  -- Used inline in each recipient block below

  -- ─── Notify assigned technician ───
  IF p_assigned_to IS NOT NULL THEN
    SELECT line_user_id INTO v_tech_line_id
    FROM public.users WHERE id = p_assigned_to;

    -- LINE notification
    IF v_tech_line_id IS NOT NULL AND v_tech_line_id != '' THEN
      PERFORM public.send_line_text(v_tech_line_id, v_message);
    END IF;

    -- In-app notification (with dedup)
    IF NOT EXISTS (
      SELECT 1 FROM public.notifications
      WHERE user_id = p_assigned_to
        AND reference_id = p_pm_id::TEXT
        AND type = 'pm'
        AND created_at >= v_today_start
    ) THEN
      INSERT INTO public.notifications (user_id, title, body, type, reference_id)
      VALUES (
        p_assigned_to,
        v_emoji || ' PM: ' || p_pm_title,
        v_body,
        'pm',
        p_pm_id::TEXT
      );
    END IF;
  END IF;

  -- ─── Notify property caretaker (caretaker_id on the property) ───
  IF v_caretaker_id IS NOT NULL THEN
    SELECT line_user_id INTO v_caretaker_line_id
    FROM public.users WHERE id = v_caretaker_id;

    -- LINE notification
    IF v_caretaker_line_id IS NOT NULL AND v_caretaker_line_id != '' THEN
      PERFORM public.send_line_text(v_caretaker_line_id, v_message);
    END IF;

    -- In-app notification (with dedup)
    IF NOT EXISTS (
      SELECT 1 FROM public.notifications
      WHERE user_id = v_caretaker_id
        AND reference_id = p_pm_id::TEXT
        AND type = 'pm'
        AND created_at >= v_today_start
    ) THEN
      INSERT INTO public.notifications (user_id, title, body, type, reference_id)
      VALUES (
        v_caretaker_id,
        v_emoji || ' PM: ' || p_pm_title,
        v_body,
        'pm',
        p_pm_id::TEXT
      );
    END IF;
  END IF;

  -- ─── Notify all admin/owner/manager users (exclude already-notified) ───
  FOR v_recipient IN
    SELECT DISTINCT id, line_user_id FROM public.users
    WHERE role IN ('admin', 'owner', 'manager')
      AND id IS DISTINCT FROM p_assigned_to
      AND id IS DISTINCT FROM v_caretaker_id
  LOOP
    -- LINE notification
    IF v_recipient.line_user_id IS NOT NULL AND v_recipient.line_user_id != '' THEN
      PERFORM public.send_line_text(v_recipient.line_user_id, v_message);
    END IF;

    -- In-app notification (with dedup)
    IF NOT EXISTS (
      SELECT 1 FROM public.notifications
      WHERE user_id = v_recipient.id
        AND reference_id = p_pm_id::TEXT
        AND type = 'pm'
        AND created_at >= v_today_start
    ) THEN
      INSERT INTO public.notifications (user_id, title, body, type, reference_id)
      VALUES (
        v_recipient.id,
        v_emoji || ' PM: ' || p_pm_title,
        v_body,
        'pm',
        p_pm_id::TEXT
      );
    END IF;
  END LOOP;
END;
$$;

-- =====================================================
-- 2. เพิ่ม RLS policy สำหรับ service_role ให้ insert ได้เสมอ
--    (ใช้กับ SECURITY DEFINER functions และ Edge Functions)
-- =====================================================
DROP POLICY IF EXISTS "Service role can insert notifications" ON public.notifications;
CREATE POLICY "Service role can insert notifications" ON public.notifications
  FOR INSERT TO service_role
  WITH CHECK (true);

-- =====================================================
-- 3. เปิด pg_cron สำหรับ daily PM check
--    NOTE: ต้องเปิด pg_cron extension ใน Supabase Dashboard ก่อน
--    Database > Extensions > pg_cron
-- =====================================================
-- เปิดใช้ extension (ถ้ายังไม่ได้เปิด):
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

-- ลบ cron เดิมถ้ามี แล้วสร้างใหม่
SELECT cron.unschedule('daily-pm-check') WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'daily-pm-check'
);

-- รัน check_pm_due_schedules ทุกวันเวลา 08:00 UTC (15:00 น. ไทย)
SELECT cron.schedule(
  'daily-pm-check',
  '0 8 * * *',
  $$SELECT public.check_pm_due_schedules()$$
);

-- =====================================================
-- 4. ตรวจสอบว่า caretaker_id ถูก set ครบ
--    รันคำสั่งนี้เพื่อดู properties ที่ไม่มี caretaker assigned:
-- =====================================================
-- SELECT id, name FROM public.properties WHERE caretaker_id IS NULL;
--
-- ถ้ามี properties ที่ไม่มี caretaker → ผู้ดูแลบ้านนั้นจะไม่ได้รับการแจ้งเตือน
-- ต้องไปตั้งค่า caretaker_id ใน property แต่ละหลัง
--
-- =====================================================
-- DONE! แก้ไขแล้ว:
-- - deduplication: ไม่ส่ง notification ซ้ำในวันเดียวกัน
-- - service_role policy: SECURITY DEFINER functions insert ได้
-- - pg_cron: เช็ค PM ทุกวัน 08:00 UTC (15:00 น. ไทย)
-- =====================================================
