-- =====================================================
-- BaanPool Ops — Migration 043
-- เพิ่มฟีเจอร์ใบงาน 2 อย่าง:
--   1. cc_user_ids UUID[]  — CC หลายคน (นอกเหนือจากผู้รับผิดชอบหลัก)
--   2. additional_property_ids UUID[]  — ใบงาน 1 ใบ ครอบคลุมหลายบ้าน
--   3. อัปเดต trg_notify_work_order_assigned ให้แจ้ง CC users ด้วย
--   4. อัปเดต trg_notify_work_order_comment ให้แจ้ง CC users ด้วย
-- =====================================================

-- ─── 1. เพิ่ม column cc_user_ids ────────────────────
ALTER TABLE public.work_orders
  ADD COLUMN IF NOT EXISTS cc_user_ids UUID[] DEFAULT '{}';

-- ─── 2. เพิ่ม column additional_property_ids ───────
ALTER TABLE public.work_orders
  ADD COLUMN IF NOT EXISTS additional_property_ids UUID[] DEFAULT '{}';

-- ─── 3. อัปเดต trg_notify_work_order_assigned ──────
-- แจ้ง assigned_to (Flex Message) + CC users ที่เพิ่งถูก add
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
  v_cc_user_id     UUID;
  v_cc_line_id     TEXT;
  v_sent_ids       TEXT[] := '{}';
  v_cc_to_notify   UUID[];
BEGIN
  -- UPDATE: ข้ามถ้า assigned_to และ cc_user_ids ไม่ได้เปลี่ยน
  IF TG_OP = 'UPDATE' THEN
    IF NEW.assigned_to IS NOT DISTINCT FROM OLD.assigned_to
       AND NEW.cc_user_ids IS NOT DISTINCT FROM OLD.cc_user_ids THEN
      RETURN NEW;
    END IF;
  END IF;

  -- ถ้าไม่มีทั้ง assigned_to และ cc_user_ids → ไม่มีใครต้องแจ้ง
  IF NEW.assigned_to IS NULL
     AND (NEW.cc_user_ids IS NULL OR array_length(NEW.cc_user_ids, 1) IS NULL) THEN
    RETURN NEW;
  END IF;

  -- ชื่อบ้าน (รวมทุกบ้านที่เกี่ยวข้อง)
  SELECT string_agg(p.name, ', ' ORDER BY (p.id = NEW.property_id) DESC, p.name)
  INTO v_property_name
  FROM public.properties p
  WHERE p.id = NEW.property_id
     OR (NEW.additional_property_ids IS NOT NULL
         AND array_length(NEW.additional_property_ids, 1) > 0
         AND p.id = ANY(NEW.additional_property_ids));

  -- ระดับความสำคัญ
  CASE COALESCE(NEW.priority, 'medium')
    WHEN 'urgent' THEN v_priority_label := 'เร่งด่วน'; v_priority_emoji := '🔴';
    WHEN 'high'   THEN v_priority_label := 'สูง';      v_priority_emoji := '🟠';
    WHEN 'medium' THEN v_priority_label := 'ปานกลาง';  v_priority_emoji := '🔵';
    WHEN 'low'    THEN v_priority_label := 'ต่ำ';       v_priority_emoji := '⚪';
    ELSE               v_priority_label := NEW.priority; v_priority_emoji := '🔵';
  END CASE;

  -- สร้าง Flex Message (เหมือนเดิม)
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
                  'size', 'sm', 'color', '#111111', 'align', 'end',
                  'weight', 'bold', 'wrap', true)
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

  -- ─── แจ้ง assigned_to ──────────────────────────────
  IF NEW.assigned_to IS NOT NULL THEN
    -- แจ้งเฉพาะถ้า assigned_to เพิ่งเปลี่ยน (หรือ INSERT ใหม่)
    IF TG_OP = 'INSERT' OR NEW.assigned_to IS DISTINCT FROM OLD.assigned_to THEN
      SELECT line_user_id INTO v_line_user_id
      FROM public.users
      WHERE id = NEW.assigned_to
        AND line_user_id IS NOT NULL AND line_user_id != '';

      IF v_line_user_id IS NOT NULL THEN
        PERFORM public.send_line_flex(
          v_line_user_id,
          '📢 งานใหม่: ' || NEW.title,
          v_flex
        );
        v_sent_ids := array_append(v_sent_ids, v_line_user_id);
      END IF;
    END IF;
  END IF;

  -- ─── แจ้ง CC users (เฉพาะคนที่เพิ่งถูก add) ────────
  -- INSERT → notify ทุกคนใน cc_user_ids
  -- UPDATE → notify เฉพาะคนที่อยู่ใน NEW แต่ไม่อยู่ใน OLD
  IF TG_OP = 'INSERT' THEN
    v_cc_to_notify := COALESCE(NEW.cc_user_ids, '{}');
  ELSE
    SELECT array_agg(uid)
    INTO v_cc_to_notify
    FROM (
      SELECT unnest(COALESCE(NEW.cc_user_ids, '{}')) AS uid
      EXCEPT
      SELECT unnest(COALESCE(OLD.cc_user_ids, '{}'))
    ) sub;
  END IF;

  IF v_cc_to_notify IS NOT NULL THEN
    FOREACH v_cc_user_id IN ARRAY v_cc_to_notify LOOP
      SELECT line_user_id INTO v_cc_line_id
      FROM public.users
      WHERE id = v_cc_user_id
        AND line_user_id IS NOT NULL AND line_user_id != '';

      IF v_cc_line_id IS NOT NULL AND NOT (v_cc_line_id = ANY(v_sent_ids)) THEN
        PERFORM public.send_line_flex(
          v_cc_line_id,
          '📋 (CC) งานใหม่: ' || NEW.title,
          v_flex
        );
        v_sent_ids := array_append(v_sent_ids, v_cc_line_id);
      END IF;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

-- อัปเดต trigger ให้ fire เมื่อ assigned_to หรือ cc_user_ids เปลี่ยน
DROP TRIGGER IF EXISTS trg_work_order_assigned ON public.work_orders;
CREATE TRIGGER trg_work_order_assigned
  AFTER INSERT OR UPDATE OF assigned_to, cc_user_ids ON public.work_orders
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_notify_work_order_assigned();

-- ─── 4. อัปเดต trg_notify_work_order_comment ────────
-- แจ้ง caretaker + assigned_to + CC users + ผู้เคยคอมเม้น
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
  v_cc_user_id     UUID;
  v_cc_line_id     TEXT;
BEGIN
  -- ดึงข้อมูลใบงาน (รวม cc_user_ids)
  SELECT wo.title, wo.assigned_to, wo.property_id, wo.cc_user_ids
  INTO v_work_order
  FROM public.work_orders wo
  WHERE wo.id = NEW.work_order_id;

  IF NOT FOUND THEN RETURN NEW; END IF;

  -- ดึงข้อมูล property
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

  -- ─── 3. CC users ────────────────────────────────────
  IF v_work_order.cc_user_ids IS NOT NULL THEN
    FOREACH v_cc_user_id IN ARRAY v_work_order.cc_user_ids LOOP
      -- ข้ามถ้าเป็นคนที่กำลังคอมเม้น, assigned_to, หรือ caretaker (แจ้งไปแล้ว)
      IF v_cc_user_id IS DISTINCT FROM NEW.user_id
         AND v_cc_user_id IS DISTINCT FROM v_work_order.assigned_to
         AND v_cc_user_id IS DISTINCT FROM v_property.caretaker_id THEN

        SELECT line_user_id INTO v_cc_line_id
        FROM public.users
        WHERE id = v_cc_user_id
          AND line_user_id IS NOT NULL AND line_user_id != '';

        IF v_cc_line_id IS NOT NULL AND NOT (v_cc_line_id = ANY(v_sent_ids)) THEN
          PERFORM public.send_line_text(v_cc_line_id, v_msg);
          v_sent_ids := array_append(v_sent_ids, v_cc_line_id);
        END IF;

        INSERT INTO public.notifications (user_id, title, body, type, reference_id)
        VALUES (
          v_cc_user_id,
          '💬 ความคิดเห็นใหม่: ' || COALESCE(v_work_order.title, '-'),
          v_commenter_name || ': ' || LEFT(NEW.content, 100),
          'work_order', NEW.work_order_id::TEXT
        ) ON CONFLICT DO NOTHING;
      END IF;
    END LOOP;
  END IF;

  -- ─── 4. ผู้ที่เคยคอมเม้น (participants) ─────────────
  FOR v_recipient IN
    SELECT DISTINCT u.id, u.line_user_id
    FROM public.work_order_comments c
    JOIN public.users u ON u.id = c.user_id
    WHERE c.work_order_id = NEW.work_order_id
      AND c.user_id IS DISTINCT FROM NEW.user_id
      AND c.user_id IS DISTINCT FROM v_work_order.assigned_to
      AND c.user_id IS DISTINCT FROM v_property.caretaker_id
      -- ข้ามคนที่อยู่ใน CC แล้ว (แจ้งไปแล้วข้างบน)
      AND (v_work_order.cc_user_ids IS NULL
           OR NOT (c.user_id = ANY(v_work_order.cc_user_ids)))
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

-- ─── ตรวจสอบผล ──────────────────────────────────────
SELECT 'migration_043 OK — cc_user_ids + additional_property_ids added' AS result;

SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'work_orders'
  AND column_name  IN ('cc_user_ids', 'additional_property_ids')
ORDER BY column_name;
