-- =====================================================
-- BaanPool Ops — Migration 040
-- ปรับปรุง LINE notifications ให้เรียบง่าย:
--   1. PM: เฉพาะวันครบกำหนด (0 วัน), ครั้งเดียว, ถึงผู้ดูแลบ้านเท่านั้น
--      → รันผ่าน pg_cron วันละ 1 ครั้ง (08:00 Bangkok time) ไม่เรียกจาก client
--   2. ใบงาน: แจ้งเฉพาะผู้รับมอบหมาย (assigned_to)
--   3. ความคิดเห็น: แจ้งเฉพาะผู้รับมอบหมาย (assigned_to)
--   4. PO อนุมัติ: แจ้ง po_assigned_to; received: ไม่แจ้ง LINE
--   5. PR ใหม่: แจ้ง CEO (role='owner') ทุกครั้งที่สร้าง PR
-- =====================================================

-- =====================================================
-- 1. notify_pm_due: เฉพาะวันครบกำหนด + ผู้ดูแลบ้านเท่านั้น
-- =====================================================
CREATE OR REPLACE FUNCTION public.notify_pm_due(
  p_pm_id       UUID,
  p_pm_title    TEXT,
  p_property_id UUID,
  p_assigned_to UUID,
  p_next_due_date DATE,
  p_description TEXT DEFAULT NULL,
  p_asset_id    UUID DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_property_name   TEXT;
  v_caretaker_id    UUID;
  v_caretaker_line  TEXT;
  v_days_until_due  INT;
  v_message         TEXT;
  v_today_start     TIMESTAMPTZ;
BEGIN
  -- คำนวณวันห่างจากกำหนด — ส่งเฉพาะวันครบกำหนด (0 วัน) เท่านั้น
  v_days_until_due := p_next_due_date - CURRENT_DATE;
  IF v_days_until_due <> 0 THEN
    RETURN;
  END IF;

  -- dedup: ส่งได้ครั้งเดียวต่อวัน
  v_today_start := date_trunc('day', NOW() AT TIME ZONE 'UTC');

  -- ดึงข้อมูล property + caretaker
  SELECT name, caretaker_id INTO v_property_name, v_caretaker_id
  FROM public.properties
  WHERE id = p_property_id;

  -- ไม่มี caretaker → ไม่มีใครต้องแจ้ง
  IF v_caretaker_id IS NULL THEN RETURN; END IF;

  -- dedup check: ถ้าแจ้งแล้ววันนี้ → ข้าม
  IF EXISTS (
    SELECT 1 FROM public.notifications
    WHERE user_id = v_caretaker_id
      AND reference_id = p_pm_id::TEXT
      AND type = 'pm'
      AND created_at >= v_today_start
  ) THEN RETURN; END IF;

  -- สร้างข้อความ LINE
  v_message :=
    '🔴 PM ถึงกำหนดวันนี้' || chr(10)
    || '📋 ' || p_pm_title || chr(10)
    || '🏠 บ้าน: ' || COALESCE(v_property_name, '-') || chr(10)
    || CASE WHEN p_description IS NOT NULL AND p_description != ''
         THEN '📝 ' || p_description || chr(10)
         ELSE '' END
    || '📅 ' || to_char(p_next_due_date, 'DD/MM/YYYY') || chr(10)
    || CASE WHEN p_asset_id IS NOT NULL
         THEN '🔗 https://changyai.vercel.app/assets/' || p_asset_id::TEXT
         ELSE '' END;

  -- ส่ง LINE ให้ caretaker
  SELECT line_user_id INTO v_caretaker_line
  FROM public.users WHERE id = v_caretaker_id;

  IF v_caretaker_line IS NOT NULL AND v_caretaker_line != '' THEN
    PERFORM public.send_line_text(v_caretaker_line, v_message);
  END IF;

  -- In-app notification
  INSERT INTO public.notifications (user_id, title, body, type, reference_id)
  VALUES (
    v_caretaker_id,
    '🔴 PM ถึงกำหนดวันนี้: ' || p_pm_title,
    '🏠 บ้าน: ' || COALESCE(v_property_name, '-') || chr(10)
      || '📅 ' || to_char(p_next_due_date, 'DD/MM/YYYY'),
    'pm',
    p_pm_id::TEXT
  )
  ON CONFLICT DO NOTHING;
END;
$$;

-- =====================================================
-- 2. check_pm_due_schedules: ตรวจเฉพาะวันครบกำหนดวันนี้
-- =====================================================
CREATE OR REPLACE FUNCTION public.check_pm_due_schedules()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_pm   RECORD;
  v_count INT := 0;
BEGIN
  -- ตรวจเฉพาะ PM ที่ next_due_date = วันนี้
  FOR v_pm IN
    SELECT id, title, property_id, assigned_to, next_due_date, description, asset_id
    FROM public.pm_schedules
    WHERE is_active = true
      AND next_due_date = CURRENT_DATE
  LOOP
    PERFORM public.notify_pm_due(
      v_pm.id,
      v_pm.title,
      v_pm.property_id,
      v_pm.assigned_to,
      v_pm.next_due_date,
      v_pm.description,
      v_pm.asset_id
    );
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

-- =====================================================
-- 3. trg_notify_work_order_assigned: แจ้งเฉพาะผู้รับมอบหมาย
-- =====================================================
CREATE OR REPLACE FUNCTION public.trg_notify_work_order_assigned()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_line_user_id   TEXT;
  v_property_name  TEXT;
  v_priority_label TEXT;
  v_priority_emoji TEXT;
  v_flex           JSONB;
BEGIN
  -- UPDATE: ข้ามถ้า assigned_to ไม่ได้เปลี่ยน
  IF TG_OP = 'UPDATE' THEN
    IF NEW.assigned_to IS NOT DISTINCT FROM OLD.assigned_to THEN RETURN NEW; END IF;
  END IF;

  -- ถ้าไม่มีผู้รับมอบหมาย → ไม่แจ้ง
  IF NEW.assigned_to IS NULL THEN RETURN NEW; END IF;

  -- ดึง LINE user ID ของผู้รับมอบหมาย
  SELECT line_user_id INTO v_line_user_id
  FROM public.users
  WHERE id = NEW.assigned_to
    AND line_user_id IS NOT NULL AND line_user_id != '';

  IF v_line_user_id IS NULL THEN RETURN NEW; END IF;

  -- ชื่อบ้าน
  SELECT name INTO v_property_name
  FROM public.properties WHERE id = NEW.property_id;

  -- ระดับความสำคัญ
  CASE COALESCE(NEW.priority, 'medium')
    WHEN 'urgent' THEN v_priority_label := 'เร่งด่วน'; v_priority_emoji := '🔴';
    WHEN 'high'   THEN v_priority_label := 'สูง';      v_priority_emoji := '🟠';
    WHEN 'medium' THEN v_priority_label := 'ปานกลาง';  v_priority_emoji := '🔵';
    WHEN 'low'    THEN v_priority_label := 'ต่ำ';       v_priority_emoji := '⚪';
    ELSE               v_priority_label := NEW.priority; v_priority_emoji := '🔵';
  END CASE;

  -- สร้าง Flex Message
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
          'type', 'text', 'text', 'เข้าดูรายละเอียดที่แอป BaanPool Ops',
          'size', 'xs', 'color', '#AAAAAA', 'align', 'center'
        )
      )
    )
  );

  PERFORM public.send_line_flex(
    v_line_user_id,
    '📢 งานใหม่: ' || NEW.title,
    v_flex
  );

  RETURN NEW;
END;
$$;

-- ปรับ trigger: INSERT + UPDATE OF assigned_to (แจ้งเมื่อมอบหมายหรือเปลี่ยนผู้รับมอบหมาย)
DROP TRIGGER IF EXISTS trg_work_order_assigned ON public.work_orders;
CREATE TRIGGER trg_work_order_assigned
  AFTER INSERT OR UPDATE OF assigned_to ON public.work_orders
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_notify_work_order_assigned();

-- =====================================================
-- 4. trg_notify_work_order_comment:
--    แจ้ง caretaker + assigned_to + ทุกคนที่เคยคอมเม้นในใบงาน
--    ยกเว้นคนที่กำลังคอมเม้นอยู่ตอนนี้
-- =====================================================
CREATE OR REPLACE FUNCTION public.trg_notify_work_order_comment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_work_order     RECORD;
  v_property       RECORD;
  v_commenter_name TEXT;
  v_msg            TEXT;
  v_line_id        TEXT;
  v_sent_ids       TEXT[] := '{}';
  v_recipient      RECORD;
BEGIN
  -- ดึงข้อมูลใบงาน
  SELECT wo.title, wo.assigned_to, wo.property_id
  INTO v_work_order
  FROM public.work_orders wo
  WHERE wo.id = NEW.work_order_id;

  IF NOT FOUND THEN RETURN NEW; END IF;

  -- ดึงข้อมูล property (caretaker)
  SELECT p.name, p.caretaker_id
  INTO v_property
  FROM public.properties p
  WHERE p.id = v_work_order.property_id;

  -- ชื่อผู้คอมเม้น
  IF NEW.user_id IS NOT NULL THEN
    SELECT full_name INTO v_commenter_name
    FROM public.users WHERE id = NEW.user_id;
  END IF;
  v_commenter_name := COALESCE(v_commenter_name, 'ผู้ใช้');

  -- สร้างข้อความ
  v_msg :=
    '💬 ความคิดเห็นใหม่ในใบงาน' || chr(10)
    || '📝 ' || COALESCE(v_work_order.title, '-') || chr(10)
    || '🏠 บ้าน: ' || COALESCE(v_property.name, '-') || chr(10)
    || '👤 ' || v_commenter_name || ': ' || LEFT(NEW.content, 100) || chr(10)
    || '🔗 https://changyai.vercel.app/work-orders';

  -- ─── 1. Caretaker ───────────────────────────────────
  IF v_property.caretaker_id IS NOT NULL
     AND v_property.caretaker_id IS DISTINCT FROM NEW.user_id THEN
    SELECT line_user_id INTO v_line_id
    FROM public.users
    WHERE id = v_property.caretaker_id
      AND line_user_id IS NOT NULL AND line_user_id != '';

    IF v_line_id IS NOT NULL THEN
      PERFORM public.send_line_text(v_line_id, v_msg);
      v_sent_ids := array_append(v_sent_ids, v_line_id);
    END IF;

    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      v_property.caretaker_id,
      '💬 ความคิดเห็นใหม่: ' || COALESCE(v_work_order.title, '-'),
      v_commenter_name || ': ' || LEFT(NEW.content, 100),
      'work_order', NEW.work_order_id::TEXT
    ) ON CONFLICT DO NOTHING;
  END IF;

  -- ─── 2. Assigned_to ─────────────────────────────────
  IF v_work_order.assigned_to IS NOT NULL
     AND v_work_order.assigned_to IS DISTINCT FROM NEW.user_id
     AND v_work_order.assigned_to IS DISTINCT FROM v_property.caretaker_id THEN
    SELECT line_user_id INTO v_line_id
    FROM public.users
    WHERE id = v_work_order.assigned_to
      AND line_user_id IS NOT NULL AND line_user_id != '';

    IF v_line_id IS NOT NULL AND NOT (v_line_id = ANY(v_sent_ids)) THEN
      PERFORM public.send_line_text(v_line_id, v_msg);
      v_sent_ids := array_append(v_sent_ids, v_line_id);
    END IF;

    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      v_work_order.assigned_to,
      '💬 ความคิดเห็นใหม่: ' || COALESCE(v_work_order.title, '-'),
      v_commenter_name || ': ' || LEFT(NEW.content, 100),
      'work_order', NEW.work_order_id::TEXT
    ) ON CONFLICT DO NOTHING;
  END IF;

  -- ─── 3. ผู้ที่เคยคอมเม้นในใบงานนี้ (participants) ──
  FOR v_recipient IN
    SELECT DISTINCT u.id, u.line_user_id
    FROM public.work_order_comments c
    JOIN public.users u ON u.id = c.user_id
    WHERE c.work_order_id = NEW.work_order_id
      AND c.user_id IS DISTINCT FROM NEW.user_id
      AND c.user_id IS DISTINCT FROM v_work_order.assigned_to
      AND c.user_id IS DISTINCT FROM v_property.caretaker_id
      AND u.line_user_id IS NOT NULL AND u.line_user_id != ''
  LOOP
    IF NOT (v_recipient.line_user_id = ANY(v_sent_ids)) THEN
      PERFORM public.send_line_text(v_recipient.line_user_id, v_msg);
      v_sent_ids := array_append(v_sent_ids, v_recipient.line_user_id);
    END IF;

    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      v_recipient.id,
      '💬 ความคิดเห็นใหม่: ' || COALESCE(v_work_order.title, '-'),
      v_commenter_name || ': ' || LEFT(NEW.content, 100),
      'work_order', NEW.work_order_id::TEXT
    ) ON CONFLICT DO NOTHING;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_work_order_comment ON public.work_order_comments;
CREATE TRIGGER trg_work_order_comment
  AFTER INSERT ON public.work_order_comments
  FOR EACH ROW EXECUTE FUNCTION public.trg_notify_work_order_comment();

-- =====================================================
-- 5. trg_notify_po_status: approved → po_assigned_to เท่านั้น
-- =====================================================
CREATE OR REPLACE FUNCTION public.trg_notify_po_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_assignee_line TEXT;
  v_property_name TEXT;
  v_message       TEXT;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN RETURN NEW; END IF;

  -- ดึงชื่อบ้าน
  SELECT name INTO v_property_name
  FROM public.properties WHERE id = NEW.property_id;

  -- CEO อนุมัติ → แจ้ง po_assigned_to (คนที่จะไปซื้อ)
  IF NEW.status = 'approved' AND NEW.po_assigned_to IS NOT NULL THEN
    SELECT u.line_user_id INTO v_assignee_line
    FROM public.users u
    WHERE u.id = NEW.po_assigned_to
      AND u.line_user_id IS NOT NULL AND u.line_user_id != '';

    IF v_assignee_line IS NOT NULL THEN
      v_message :=
        '✅ PR ได้รับการอนุมัติแล้ว — กรุณาจัดซื้อ' || chr(10)
        || '📦 ' || NEW.title || chr(10)
        || '🏠 บ้าน: ' || COALESCE(v_property_name, '-') || chr(10)
        || '💰 วงเงิน: ' || COALESCE(NEW.total_price::TEXT, '-') || ' บาท' || chr(10)
        || '🔗 https://changyai.vercel.app/purchase-orders';
      PERFORM public.send_line_text(v_assignee_line, v_message);
    END IF;
  END IF;

  -- หากไม่มี po_assigned_to แต่ approved → แจ้ง created_by
  IF NEW.status = 'approved' AND NEW.po_assigned_to IS NULL THEN
    SELECT u.line_user_id INTO v_assignee_line
    FROM public.users u
    WHERE u.id = NEW.created_by
      AND u.line_user_id IS NOT NULL AND u.line_user_id != '';

    IF v_assignee_line IS NOT NULL THEN
      v_message :=
        '✅ PR ได้รับการอนุมัติแล้ว' || chr(10)
        || '📦 ' || NEW.title || chr(10)
        || '🏠 บ้าน: ' || COALESCE(v_property_name, '-') || chr(10)
        || '🔗 https://changyai.vercel.app/purchase-orders';
      PERFORM public.send_line_text(v_assignee_line, v_message);
    END IF;
  END IF;

  -- received / cancelled → ไม่มี LINE notification

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_po_status ON public.purchase_orders;
CREATE TRIGGER trg_po_status
  AFTER UPDATE OF status ON public.purchase_orders
  FOR EACH ROW EXECUTE FUNCTION public.trg_notify_po_status();

-- =====================================================
-- 6. trg_notify_pr_created: แจ้ง CEO เมื่อมีการสร้าง PR ใหม่
-- =====================================================
CREATE OR REPLACE FUNCTION public.trg_notify_pr_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_creator_name  TEXT;
  v_property_name TEXT;
  v_message       TEXT;
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

  -- แจ้ง CEO (role = 'owner') ทุกคน
  FOR v_recipient IN
    SELECT line_user_id FROM public.users
    WHERE role = 'owner'
      AND line_user_id IS NOT NULL AND line_user_id != ''
  LOOP
    PERFORM public.send_line_text(v_recipient.line_user_id, v_message);
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pr_created ON public.purchase_orders;
CREATE TRIGGER trg_pr_created
  AFTER INSERT ON public.purchase_orders
  FOR EACH ROW EXECUTE FUNCTION public.trg_notify_pr_created();

-- =====================================================
-- 7. pg_cron: รัน check_pm_due_schedules วันละ 1 ครั้ง เวลา 08:00 Bangkok (01:00 UTC)
--    ไม่ต้องเรียกจาก Flutter client อีกต่อไป
-- =====================================================

-- เปิดใช้ pg_cron (ถ้ายังไม่มี)
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

-- ลบ job เดิมก่อน (ป้องกัน duplicate)
SELECT cron.unschedule('pm_due_daily_check')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'pm_due_daily_check'
);

-- สร้าง cron job ใหม่: ทุกวัน 01:00 UTC = 08:00 Bangkok
SELECT cron.schedule(
  'pm_due_daily_check',
  '0 1 * * *',
  $$ SELECT public.check_pm_due_schedules(); $$
);

-- =====================================================
-- ตรวจสอบ triggers ที่ active
-- =====================================================
SELECT trigger_name, event_object_table, event_manipulation, action_timing
FROM information_schema.triggers
WHERE trigger_name IN (
  'trg_work_order_assigned',
  'trg_work_order_comment',
  'trg_po_status',
  'trg_pr_created'
)
ORDER BY event_object_table, trigger_name;
