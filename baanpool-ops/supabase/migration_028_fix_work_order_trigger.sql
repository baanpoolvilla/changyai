-- =====================================================
-- BaanPool Ops — Migration 028
-- Fix: สร้าง trigger trg_work_order_assigned ใหม่
-- Root cause: trigger ไม่มีใน production (ไม่เคย run migration_006+)
-- =====================================================

-- ─── Step 1: Enable pg_net (ถ้ายังไม่มี) ─────────────
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ─── Step 2: สร้าง app_settings table (ถ้ายังไม่มี) ─
CREATE TABLE IF NOT EXISTS public.app_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'app_settings' AND policyname = 'Allow authenticated read'
  ) THEN
    CREATE POLICY "Allow authenticated read" ON public.app_settings
      FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- ─── Step 3: ใส่ token placeholder (ถ้ายังไม่มี) ────
INSERT INTO public.app_settings (key, value) VALUES
  ('line_messaging_token', 'REPLACE_WITH_YOUR_TOKEN')
ON CONFLICT (key) DO NOTHING;

-- ─── Step 4: Helper functions ─────────────────────────

CREATE OR REPLACE FUNCTION public.send_line_push(
  p_line_user_id TEXT,
  p_message_json JSONB
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_token TEXT;
BEGIN
  SELECT value INTO v_token
  FROM public.app_settings
  WHERE key = 'line_messaging_token';

  IF v_token IS NULL OR v_token = '' OR v_token = 'REPLACE_WITH_YOUR_TOKEN' THEN
    RAISE NOTICE 'LINE token not configured in app_settings';
    RETURN;
  END IF;

  IF p_line_user_id IS NULL OR p_line_user_id = '' THEN
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := 'https://api.line.me/v2/bot/message/push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_token
    ),
    body := jsonb_build_object(
      'to', p_line_user_id,
      'messages', p_message_json
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.send_line_text(
  p_line_user_id TEXT,
  p_message TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  PERFORM public.send_line_push(
    p_line_user_id,
    jsonb_build_array(
      jsonb_build_object('type', 'text', 'text', p_message)
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.send_line_flex(
  p_line_user_id TEXT,
  p_alt_text TEXT,
  p_flex_contents JSONB
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  PERFORM public.send_line_push(
    p_line_user_id,
    jsonb_build_array(
      jsonb_build_object(
        'type', 'flex',
        'altText', p_alt_text,
        'contents', p_flex_contents
      )
    )
  );
END;
$$;

-- ─── Step 5: Work order LINE notification trigger ─────
-- Logic:
--   INSERT  → ส่งทุกครั้ง (แม้ assigned_to = NULL)
--   UPDATE  → ส่งเฉพาะเมื่อ assigned_to เปลี่ยน
--   ผู้รับ:
--     - ผู้รับมอบหมาย → Flex Card (สีเขียว)
--     - ทุกคนที่มี line_user_id ยกเว้น role='owner' → Text

CREATE OR REPLACE FUNCTION public.trg_notify_work_order_assigned()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_property_name  TEXT;
  v_priority_label TEXT;
  v_priority_emoji TEXT;
  v_flex           JSONB;
  v_text_msg       TEXT;
  v_recipient      RECORD;
  v_sent_ids       TEXT[] := '{}';
BEGIN
  -- guard for UPDATE: skip if assigned_to didn't change
  IF TG_OP = 'UPDATE' THEN
    IF NEW.assigned_to IS NOT DISTINCT FROM OLD.assigned_to THEN
      RETURN NEW;
    END IF;
  END IF;
  -- on INSERT: always proceed (even if assigned_to is NULL)

  -- look up property name
  SELECT name INTO v_property_name
  FROM public.properties WHERE id = NEW.property_id;

  -- priority labels
  CASE COALESCE(NEW.priority, 'medium')
    WHEN 'urgent' THEN v_priority_label := 'เร่งด่วน'; v_priority_emoji := '🔴';
    WHEN 'high'   THEN v_priority_label := 'สูง';      v_priority_emoji := '🟠';
    WHEN 'medium' THEN v_priority_label := 'ปานกลาง';  v_priority_emoji := '🔵';
    WHEN 'low'    THEN v_priority_label := 'ต่ำ';       v_priority_emoji := '⚪';
    ELSE               v_priority_label := NEW.priority; v_priority_emoji := '🔵';
  END CASE;

  -- text message for non-assigned recipients
  v_text_msg :=
    '📝 ใบงานใหม่' || chr(10)
    || '📋 ' || NEW.title || chr(10)
    || '🏠 บ้าน: ' || COALESCE(v_property_name, '-') || chr(10)
    || v_priority_emoji || ' ความสำคัญ: ' || v_priority_label || chr(10)
    || '🔗 https://changyai.vercel.app/work-orders';

  -- 1. Flex card to assigned_to (if set)
  IF NEW.assigned_to IS NOT NULL THEN
    SELECT line_user_id INTO v_recipient
    FROM public.users
    WHERE id = NEW.assigned_to
      AND line_user_id IS NOT NULL AND line_user_id != '';

    IF FOUND AND v_recipient.line_user_id IS NOT NULL THEN
      v_flex := jsonb_build_object(
        'type', 'bubble',
        'header', jsonb_build_object(
          'type', 'box', 'layout', 'vertical',
          'backgroundColor', '#1DB446', 'paddingAll', 'lg',
          'contents', jsonb_build_array(
            jsonb_build_object(
              'type', 'text', 'text', '📢 คุณได้รับมอบหมายงานใหม่!',
              'color', '#FFFFFF', 'weight', 'bold', 'size', 'md'
            )
          )
        ),
        'body', jsonb_build_object(
          'type', 'box', 'layout', 'vertical', 'spacing', 'md',
          'contents', jsonb_build_array(
            jsonb_build_object(
              'type', 'text', 'text', '📝 ' || NEW.title,
              'weight', 'bold', 'size', 'lg', 'wrap', true
            ),
            jsonb_build_object('type', 'separator'),
            jsonb_build_object(
              'type', 'box', 'layout', 'vertical', 'spacing', 'sm',
              'contents', jsonb_build_array(
                jsonb_build_object(
                  'type', 'box', 'layout', 'horizontal',
                  'contents', jsonb_build_array(
                    jsonb_build_object('type', 'text', 'text', '🏠 บ้าน',
                      'size', 'sm', 'color', '#555555', 'flex', 0),
                    jsonb_build_object('type', 'text',
                      'text', COALESCE(v_property_name, '-'),
                      'size', 'sm', 'color', '#111111', 'align', 'end', 'weight', 'bold')
                  )
                ),
                jsonb_build_object(
                  'type', 'box', 'layout', 'horizontal',
                  'contents', jsonb_build_array(
                    jsonb_build_object('type', 'text',
                      'text', v_priority_emoji || ' ความสำคัญ',
                      'size', 'sm', 'color', '#555555', 'flex', 0),
                    jsonb_build_object('type', 'text', 'text', v_priority_label,
                      'size', 'sm', 'color', '#111111', 'align', 'end', 'weight', 'bold')
                  )
                )
              )
            )
          )
        ),
        'footer', jsonb_build_object(
          'type', 'box', 'layout', 'vertical',
          'contents', jsonb_build_array(
            jsonb_build_object(
              'type', 'text',
              'text', 'เข้าดูรายละเอียดที่แอป ChangYai',
              'size', 'xs', 'color', '#AAAAAA', 'align', 'center'
            )
          )
        )
      );

      PERFORM public.send_line_flex(
        v_recipient.line_user_id,
        '📢 งานใหม่: ' || NEW.title,
        v_flex
      );

      v_sent_ids := array_append(v_sent_ids, v_recipient.line_user_id);
    END IF;
  END IF;

  -- 2. Text message to all non-CEO users not yet notified
  FOR v_recipient IN
    SELECT DISTINCT line_user_id
    FROM public.users
    WHERE role != 'owner'
      AND line_user_id IS NOT NULL
      AND line_user_id != ''
  LOOP
    IF NOT (v_recipient.line_user_id = ANY(v_sent_ids)) THEN
      PERFORM public.send_line_text(v_recipient.line_user_id, v_text_msg);
      v_sent_ids := array_append(v_sent_ids, v_recipient.line_user_id);
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

-- Attach trigger
DROP TRIGGER IF EXISTS trg_work_order_assigned ON public.work_orders;
CREATE TRIGGER trg_work_order_assigned
  AFTER INSERT OR UPDATE OF assigned_to ON public.work_orders
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_notify_work_order_assigned();

-- ─── Step 6: Work order status change trigger ─────────

CREATE OR REPLACE FUNCTION public.trg_notify_work_order_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_property RECORD;
  v_tech_name TEXT;
  v_status_text TEXT;
  v_emoji TEXT;
  v_message TEXT;
  v_recipient RECORD;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  SELECT name, caretaker_id INTO v_property
  FROM public.properties WHERE id = NEW.property_id;

  IF NEW.assigned_to IS NOT NULL THEN
    SELECT full_name INTO v_tech_name FROM public.users WHERE id = NEW.assigned_to;
  END IF;

  CASE NEW.status
    WHEN 'open'        THEN v_status_text := 'เปิด';           v_emoji := '🆕';
    WHEN 'in_progress' THEN v_status_text := 'กำลังดำเนินการ'; v_emoji := '🔄';
    WHEN 'completed'   THEN v_status_text := 'เสร็จแล้ว';      v_emoji := '✅';
    WHEN 'cancelled'   THEN v_status_text := 'ยกเลิก';         v_emoji := '❌';
    ELSE                    v_status_text := NEW.status;        v_emoji := '📋';
  END CASE;

  v_message :=
    v_emoji || ' ใบงานอัปเดตสถานะ' || chr(10)
    || '📝 ' || NEW.title || chr(10)
    || '🏠 บ้าน: ' || COALESCE(v_property.name, '-') || chr(10)
    || '📊 สถานะ: ' || v_status_text
    || CASE WHEN v_tech_name IS NOT NULL THEN chr(10) || '👤 ช่าง: ' || v_tech_name ELSE '' END;

  -- Notify all non-CEO users
  FOR v_recipient IN
    SELECT DISTINCT line_user_id
    FROM public.users
    WHERE role != 'owner'
      AND line_user_id IS NOT NULL
      AND line_user_id != ''
  LOOP
    PERFORM public.send_line_text(v_recipient.line_user_id, v_message);
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_work_order_status ON public.work_orders;
CREATE TRIGGER trg_work_order_status
  AFTER UPDATE OF status ON public.work_orders
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_notify_work_order_status();

-- ─── Step 7: ตรวจสอบ triggers ที่สร้างเสร็จแล้ว ──────
SELECT
  trigger_name,
  event_object_table,
  action_timing,
  string_agg(event_manipulation, ', ' ORDER BY event_manipulation) AS events
FROM information_schema.triggers
WHERE trigger_name IN (
  'trg_work_order_assigned',
  'trg_work_order_status',
  'trg_comment_notify'
)
GROUP BY trigger_name, event_object_table, action_timing
ORDER BY trigger_name;
