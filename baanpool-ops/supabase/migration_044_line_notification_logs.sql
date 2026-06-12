-- =====================================================
-- BaanPool Ops — Migration 044
-- เพิ่มตาราง line_notification_logs สำหรับบันทึก log
-- การส่งแจ้งเตือนผ่าน LINE ทุกครั้ง
--
-- แก้ไข send_line_push ให้บันทึก log อัตโนมัติ
-- เมื่อส่งข้อความ LINE ทุกประเภท (text + flex)
-- =====================================================

-- 1. สร้างตาราง line_notification_logs
CREATE TABLE IF NOT EXISTS public.line_notification_logs (
  id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  sent_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  recipient_line_user_id  TEXT        NOT NULL,
  recipient_name          TEXT,
  message_type            TEXT        NOT NULL DEFAULT 'text',
  message_preview         TEXT
);

CREATE INDEX IF NOT EXISTS idx_line_logs_sent_at
  ON public.line_notification_logs (sent_at DESC);

-- 2. RLS: เฉพาะ role=admin เท่านั้นที่อ่านได้
--    INSERT ทำจาก SECURITY DEFINER function จึงไม่ต้องมี policy
ALTER TABLE public.line_notification_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "line_logs_admin_read" ON public.line_notification_logs
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 3. แก้ไข send_line_push ให้บันทึก log ก่อนส่ง
CREATE OR REPLACE FUNCTION public.send_line_push(
  p_line_user_id TEXT,
  p_message_json JSONB
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_token           TEXT;
  v_recipient_name  TEXT;
  v_message_type    TEXT;
  v_message_preview TEXT;
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

  -- ค้นหาชื่อผู้รับจาก line_user_id
  SELECT full_name INTO v_recipient_name
  FROM public.users
  WHERE line_user_id = p_line_user_id
  LIMIT 1;

  -- ตรวจสอบประเภทและสร้าง preview
  v_message_type := COALESCE(p_message_json->0->>'type', 'text');
  v_message_preview := CASE
    WHEN v_message_type = 'flex' THEN LEFT(p_message_json->0->>'altText', 300)
    ELSE LEFT(p_message_json->0->>'text', 300)
  END;

  -- บันทึก log
  INSERT INTO public.line_notification_logs (
    recipient_line_user_id, recipient_name, message_type, message_preview
  ) VALUES (
    p_line_user_id, v_recipient_name, v_message_type, v_message_preview
  );

  -- ส่งข้อความผ่าน pg_net
  PERFORM net.http_post(
    url     := 'https://api.line.me/v2/bot/message/push',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_token
    ),
    body    := jsonb_build_object(
      'to',       p_line_user_id,
      'messages', p_message_json
    )
  );
END;
$$;
