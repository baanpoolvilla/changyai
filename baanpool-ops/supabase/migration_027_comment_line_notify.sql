-- =====================================================
-- BaanPool Ops — Migration 027
-- LINE notification trigger for work_order_comments
-- Notify: property caretaker + work order assigned_to
--         (exclude the commenter themselves)
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
BEGIN
  -- ─── 1. Get work order info ───────────────────────────────────────────
  SELECT wo.title, wo.assigned_to, wo.property_id
  INTO v_work_order
  FROM public.work_orders wo
  WHERE wo.id = NEW.work_order_id;

  IF NOT FOUND THEN RETURN NEW; END IF;

  -- ─── 2. Get property info (for caretaker_id + name) ──────────────────
  SELECT p.name, p.caretaker_id
  INTO v_property
  FROM public.properties p
  WHERE p.id = v_work_order.property_id;

  -- ─── 3. Commenter name ────────────────────────────────────────────────
  IF NEW.user_id IS NOT NULL THEN
    SELECT full_name INTO v_commenter_name
    FROM public.users WHERE id = NEW.user_id;
  END IF;
  v_commenter_name := COALESCE(v_commenter_name, 'ผู้ใช้');

  -- ─── 4. Build message ────────────────────────────────────────────────
  v_msg :=
    '💬 ความคิดเห็นใหม่ในใบงาน' || chr(10)
    || '📝 ' || COALESCE(v_work_order.title, '-') || chr(10)
    || '🏠 บ้าน: ' || COALESCE(v_property.name, '-') || chr(10)
    || '👤 ' || v_commenter_name || ': ' || LEFT(NEW.content, 100)
    || chr(10) || '🔗 https://changyai.vercel.app/work-orders';

  -- ─── 5. Notify caretaker (if set and not the commenter) ──────────────
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
  END IF;

  -- ─── 6. Notify assigned_to (if set, not commenter, not already sent) ─
  IF v_work_order.assigned_to IS NOT NULL
     AND v_work_order.assigned_to IS DISTINCT FROM NEW.user_id THEN
    SELECT line_user_id INTO v_line_id
    FROM public.users
    WHERE id = v_work_order.assigned_to
      AND line_user_id IS NOT NULL AND line_user_id != '';

    IF v_line_id IS NOT NULL
       AND NOT (v_line_id = ANY(v_sent_ids)) THEN
      PERFORM public.send_line_text(v_line_id, v_msg);
      v_sent_ids := array_append(v_sent_ids, v_line_id);
    END IF;
  END IF;

  -- ─── 7. In-app notification: caretaker ───────────────────────────────
  IF v_property.caretaker_id IS NOT NULL
     AND v_property.caretaker_id IS DISTINCT FROM NEW.user_id THEN
    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      v_property.caretaker_id,
      '💬 ความคิดเห็นใหม่: ' || COALESCE(v_work_order.title, '-'),
      v_commenter_name || ': ' || LEFT(NEW.content, 100),
      'work_order',
      NEW.work_order_id::TEXT
    )
    ON CONFLICT DO NOTHING;
  END IF;

  -- ─── 8. In-app notification: assigned_to ─────────────────────────────
  IF v_work_order.assigned_to IS NOT NULL
     AND v_work_order.assigned_to IS DISTINCT FROM NEW.user_id
     AND v_work_order.assigned_to IS DISTINCT FROM v_property.caretaker_id THEN
    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      v_work_order.assigned_to,
      '💬 ความคิดเห็นใหม่: ' || COALESCE(v_work_order.title, '-'),
      v_commenter_name || ': ' || LEFT(NEW.content, 100),
      'work_order',
      NEW.work_order_id::TEXT
    )
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

-- ─── Attach trigger ──────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_comment_notify ON public.work_order_comments;
CREATE TRIGGER trg_comment_notify
  AFTER INSERT ON public.work_order_comments
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_notify_work_order_comment();
