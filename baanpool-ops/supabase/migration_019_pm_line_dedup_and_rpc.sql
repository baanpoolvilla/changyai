-- =====================================================
-- BaanPool Ops — Migration 019: Fix PM LINE notifications
-- แก้ไข:
--   1. เพิ่ม LINE dedup ใน notify_pm_due (ปัจจุบัน LINE ส่งทุกครั้ง ไม่มี dedup)
--      → ใช้ dedup เดียวกับ in-app: ถ้า notification มีอยู่แล้ววันนี้ → ไม่ส่งซ้ำ
--   2. Merge LINE + in-app ใน dedup check เดียว (clean + consistent)
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
  -- Only notify if due within 7 days or overdue
  v_days_until_due := p_next_due_date - CURRENT_DATE;
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

  -- ─── Notify assigned technician ───
  IF p_assigned_to IS NOT NULL THEN
    -- Dedup check: skip if already notified today (LINE + in-app together)
    IF NOT EXISTS (
      SELECT 1 FROM public.notifications
      WHERE user_id = p_assigned_to
        AND reference_id = p_pm_id::TEXT
        AND type = 'pm'
        AND created_at >= v_today_start
    ) THEN
      -- LINE notification
      SELECT line_user_id INTO v_tech_line_id
      FROM public.users WHERE id = p_assigned_to;
      IF v_tech_line_id IS NOT NULL AND v_tech_line_id != '' THEN
        PERFORM public.send_line_text(v_tech_line_id, v_message);
      END IF;

      -- In-app notification
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

  -- ─── Notify property caretaker ───
  IF v_caretaker_id IS NOT NULL AND v_caretaker_id IS DISTINCT FROM p_assigned_to THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.notifications
      WHERE user_id = v_caretaker_id
        AND reference_id = p_pm_id::TEXT
        AND type = 'pm'
        AND created_at >= v_today_start
    ) THEN
      -- LINE notification
      SELECT line_user_id INTO v_caretaker_line_id
      FROM public.users WHERE id = v_caretaker_id;
      IF v_caretaker_line_id IS NOT NULL AND v_caretaker_line_id != '' THEN
        PERFORM public.send_line_text(v_caretaker_line_id, v_message);
      END IF;

      -- In-app notification
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

  -- ─── Notify all admin/owner/manager users ───
  FOR v_recipient IN
    SELECT DISTINCT id, line_user_id FROM public.users
    WHERE role IN ('admin', 'owner', 'manager')
      AND id IS DISTINCT FROM p_assigned_to
      AND id IS DISTINCT FROM v_caretaker_id
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.notifications
      WHERE user_id = v_recipient.id
        AND reference_id = p_pm_id::TEXT
        AND type = 'pm'
        AND created_at >= v_today_start
    ) THEN
      -- LINE notification
      IF v_recipient.line_user_id IS NOT NULL AND v_recipient.line_user_id != '' THEN
        PERFORM public.send_line_text(v_recipient.line_user_id, v_message);
      END IF;

      -- In-app notification
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
-- DONE!
-- notify_pm_due() ตอนนี้:
-- - ส่ง LINE เฉพาะครั้งแรกของวัน (เช้าวันใหม่ส่งได้อีก)
-- - สร้าง in-app notification พร้อมกับ LINE (ใน dedup check เดียวกัน)
-- - ไม่ spam LINE ทุกครั้งที่ app โหลด
-- =====================================================
