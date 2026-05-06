-- =====================================================
-- BaanPool Ops — Fix: always notify on INSERT even if assigned_to is NULL
-- =====================================================
-- Root cause: previous trigger returned early when assigned_to IS NULL,
--             so Super Admin never received LINE when WO had no assignee.
-- Fix:
--   INSERT  → always notify all non-CEO users; send Flex to assignee if set
--   UPDATE of assigned_to → only fire if assigned_to actually changed
-- =====================================================

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
  -- ─── guard for UPDATE: skip if assigned_to didn't change ─────────────
  IF TG_OP = 'UPDATE' THEN
    IF NEW.assigned_to IS NOT DISTINCT FROM OLD.assigned_to THEN
      RETURN NEW;
    END IF;
  END IF;
  -- NOTE: on INSERT we always proceed (even if assigned_to is NULL)

  -- ─── property name ────────────────────────────────────────────────────
  SELECT name INTO v_property_name
  FROM public.properties WHERE id = NEW.property_id;

  -- ─── priority ─────────────────────────────────────────────────────────
  CASE COALESCE(NEW.priority, 'medium')
    WHEN 'urgent' THEN v_priority_label := 'เร่งด่วน'; v_priority_emoji := '🔴';
    WHEN 'high'   THEN v_priority_label := 'สูง';      v_priority_emoji := '🟠';
    WHEN 'medium' THEN v_priority_label := 'ปานกลาง';  v_priority_emoji := '🔵';
    WHEN 'low'    THEN v_priority_label := 'ต่ำ';       v_priority_emoji := '⚪';
    ELSE               v_priority_label := NEW.priority; v_priority_emoji := '🔵';
  END CASE;

  -- ─── text message for non-assigned recipients ─────────────────────────
  v_text_msg :=
    '📝 ใบงานใหม่' || chr(10)
    || '📋 ' || NEW.title || chr(10)
    || '🏠 บ้าน: ' || COALESCE(v_property_name, '-') || chr(10)
    || v_priority_emoji || ' ความสำคัญ: ' || v_priority_label || chr(10)
    || '🔗 https://changyai.vercel.app/work-orders';

  -- ─── 1. Flex card to assigned_to (if set) ────────────────────────────
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
              'text', 'เข้าดูรายละเอียดที่แอป BaanPool Ops',
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

  -- ─── 2. Text message to all non-CEO users not yet notified ───────────
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

-- Re-attach trigger
DROP TRIGGER IF EXISTS trg_work_order_assigned ON public.work_orders;
CREATE TRIGGER trg_work_order_assigned
  AFTER INSERT OR UPDATE OF assigned_to ON public.work_orders
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_notify_work_order_assigned();
