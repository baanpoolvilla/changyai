-- =====================================================
-- BaanPool Ops — Fix: LINE notify caretaker + admins on work order created
-- =====================================================
-- Problem: trg_notify_work_order_assigned only sends LINE to the assigned
--          technician. Caretaker of the property and admins/managers never
--          receive a LINE message when a new work order is created.
-- Fix:     Update the INSERT branch of trg_notify_work_order_assigned to
--          also notify:
--            1. The property caretaker (if different from assigned_to)
--            2. All admin / manager users
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
  v_caretaker_id   UUID;
  v_recipient      RECORD;
  v_sent_ids       TEXT[] := '{}';   -- track already-notified line_user_ids

  -- helper: build the same Flex card used for technician
  v_flex_header_color TEXT;
  v_flex_header_text  TEXT;
BEGIN
  -- ─── guard: only when assigned_to is set or changed ──────────────────
  IF TG_OP = 'INSERT' THEN
    IF NEW.assigned_to IS NULL THEN RETURN NEW; END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.assigned_to IS NOT DISTINCT FROM OLD.assigned_to THEN RETURN NEW; END IF;
    IF NEW.assigned_to IS NULL THEN RETURN NEW; END IF;
  END IF;

  -- ─── property name + caretaker ───────────────────────────────────────
  SELECT name, caretaker_id
  INTO v_property_name, v_caretaker_id
  FROM public.properties
  WHERE id = NEW.property_id;

  -- ─── priority labels ─────────────────────────────────────────────────
  CASE COALESCE(NEW.priority, 'medium')
    WHEN 'urgent' THEN v_priority_label := 'เร่งด่วน'; v_priority_emoji := '🔴';
    WHEN 'high'   THEN v_priority_label := 'สูง';      v_priority_emoji := '🟠';
    WHEN 'medium' THEN v_priority_label := 'ปานกลาง';  v_priority_emoji := '🔵';
    WHEN 'low'    THEN v_priority_label := 'ต่ำ';       v_priority_emoji := '⚪';
    ELSE               v_priority_label := NEW.priority; v_priority_emoji := '🔵';
  END CASE;

  -- ─── 1. Notify assigned technician / caretaker (green card) ──────────
  SELECT line_user_id INTO v_line_user_id
  FROM public.users WHERE id = NEW.assigned_to;

  IF v_line_user_id IS NOT NULL AND v_line_user_id != '' THEN
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
          jsonb_build_object('type', 'text', 'text', '📝 ' || NEW.title,
            'weight', 'bold', 'size', 'lg', 'wrap', true),
          jsonb_build_object('type', 'separator'),
          jsonb_build_object(
            'type', 'box', 'layout', 'vertical', 'spacing', 'sm',
            'contents', jsonb_build_array(
              jsonb_build_object('type', 'box', 'layout', 'horizontal',
                'contents', jsonb_build_array(
                  jsonb_build_object('type', 'text', 'text', '🏠 บ้าน', 'size', 'sm', 'color', '#555555', 'flex', 0),
                  jsonb_build_object('type', 'text', 'text', COALESCE(v_property_name, '-'),
                    'size', 'sm', 'color', '#111111', 'align', 'end', 'weight', 'bold')
                )
              ),
              jsonb_build_object('type', 'box', 'layout', 'horizontal',
                'contents', jsonb_build_array(
                  jsonb_build_object('type', 'text', 'text', v_priority_emoji || ' ความสำคัญ', 'size', 'sm', 'color', '#555555', 'flex', 0),
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
          jsonb_build_object('type', 'text',
            'text', 'เข้าดูรายละเอียดที่แอป BaanPool Ops',
            'size', 'xs', 'color', '#AAAAAA', 'align', 'center')
        )
      )
    );

    PERFORM public.send_line_flex(
      v_line_user_id,
      '📢 งานใหม่: ' || NEW.title,
      v_flex
    );

    v_sent_ids := array_append(v_sent_ids, v_line_user_id);
  END IF;

  -- ─── 2. Notify caretaker of the property (if not already notified) ───
  IF v_caretaker_id IS NOT NULL AND v_caretaker_id != NEW.assigned_to THEN
    SELECT line_user_id INTO v_line_user_id
    FROM public.users WHERE id = v_caretaker_id;

    IF v_line_user_id IS NOT NULL AND v_line_user_id != ''
       AND NOT (v_line_user_id = ANY(v_sent_ids)) THEN
      PERFORM public.send_line_text(
        v_line_user_id,
        '📝 ใบงานใหม่สำหรับบ้านของคุณ' || chr(10)
          || '📋 ' || NEW.title || chr(10)
          || '🏠 บ้าน: ' || COALESCE(v_property_name, '-') || chr(10)
          || v_priority_emoji || ' ความสำคัญ: ' || v_priority_label || chr(10)
          || '🔗 https://changyai.vercel.app/work-orders'
      );
      v_sent_ids := array_append(v_sent_ids, v_line_user_id);
    END IF;
  END IF;

  -- ─── 3. Notify all admins + managers (if not already notified) ───────
  FOR v_recipient IN
    SELECT DISTINCT line_user_id
    FROM public.users
    WHERE role IN ('admin', 'manager')
      AND line_user_id IS NOT NULL
      AND line_user_id != ''
  LOOP
    IF NOT (v_recipient.line_user_id = ANY(v_sent_ids)) THEN
      PERFORM public.send_line_text(
        v_recipient.line_user_id,
        '📝 ใบงานใหม่' || chr(10)
          || '📋 ' || NEW.title || chr(10)
          || '🏠 บ้าน: ' || COALESCE(v_property_name, '-') || chr(10)
          || v_priority_emoji || ' ความสำคัญ: ' || v_priority_label || chr(10)
          || '🔗 https://changyai.vercel.app/work-orders'
      );
      v_sent_ids := array_append(v_sent_ids, v_recipient.line_user_id);
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

-- Re-attach trigger (unchanged: AFTER INSERT OR UPDATE OF assigned_to)
DROP TRIGGER IF EXISTS trg_work_order_assigned ON public.work_orders;
CREATE TRIGGER trg_work_order_assigned
  AFTER INSERT OR UPDATE OF assigned_to ON public.work_orders
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_notify_work_order_assigned();
