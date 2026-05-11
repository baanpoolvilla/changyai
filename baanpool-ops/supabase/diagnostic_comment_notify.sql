-- =====================================================
-- Diagnostic: ตรวจสอบ LINE notification setup ทั้งหมด
-- รัน query นี้ใน Supabase SQL Editor แล้วดูผลลัพธ์
-- =====================================================

-- ─── 1. ตรวจสอบ LINE token ใน app_settings ──────────
SELECT
  key,
  CASE
    WHEN value IS NULL OR value = '' THEN '❌ ว่างเปล่า'
    WHEN value = 'REPLACE_WITH_YOUR_TOKEN' THEN '❌ ยังไม่ได้ตั้งค่า (placeholder)'
    ELSE '✅ ตั้งค่าแล้ว (length=' || length(value) || ')'
  END AS token_status
FROM public.app_settings
WHERE key = 'line_messaging_token';

-- ─── 2. ตรวจสอบ triggers ทั้งหมดที่เกี่ยวกับ LINE ───
SELECT
  trigger_name,
  event_object_table,
  action_timing,
  string_agg(event_manipulation, ', ') AS events,
  action_statement
FROM information_schema.triggers
WHERE trigger_name IN (
  'trg_work_order_assigned',
  'trg_work_order_status',
  'trg_comment_notify'
)
GROUP BY trigger_name, event_object_table, action_timing, action_statement
ORDER BY trigger_name;

-- ─── 3. ตรวจสอบ users ทั้งหมด: มี/ไม่มี line_user_id ──
SELECT
  full_name,
  role,
  CASE
    WHEN line_user_id IS NOT NULL AND line_user_id != '' THEN '✅ มี: ' || left(line_user_id, 8) || '...'
    ELSE '❌ ไม่มี'
  END AS line_user_id_status
FROM public.users
ORDER BY role, full_name;

-- ─── 4. ตรวจสอบ pg_net HTTP responses ล่าสุด ────────
-- (ดูว่า LINE API ถูกเรียกจริงและผลลัพธ์เป็นอย่างไร)
SELECT
  id,
  status_code,
  left(content::text, 200) AS response_body,
  created
FROM net._http_response
ORDER BY created DESC
LIMIT 20;

-- ─── 5. ตรวจสอบใบงานล่าสุด + assigned user ─────────
SELECT
  wo.id,
  wo.title,
  wo.created_at,
  wo.priority,
  u.full_name AS assigned_to_name,
  u.role AS assigned_role,
  CASE
    WHEN u.line_user_id IS NOT NULL AND u.line_user_id != '' THEN '✅ มี'
    ELSE '❌ ไม่มี'
  END AS assigned_has_line_id,
  p.name AS property_name
FROM public.work_orders wo
LEFT JOIN public.users u ON u.id = wo.assigned_to
LEFT JOIN public.properties p ON p.id = wo.property_id
ORDER BY wo.created_at DESC
LIMIT 10;

-- ─── 6. ตรวจสอบ comment notification trigger ─────────
SELECT
  trigger_name,
  event_object_table,
  action_timing,
  event_manipulation
FROM information_schema.triggers
WHERE trigger_name = 'trg_comment_notify';

-- ─── 7. ตรวจสอบ work orders ที่มี comment ────────────
SELECT
  wo.id,
  wo.title,
  wo.assigned_to,
  u_assigned.full_name AS assigned_name,
  u_assigned.line_user_id AS assigned_line_id,
  p.name AS property_name,
  p.caretaker_id,
  u_caretaker.full_name AS caretaker_name,
  u_caretaker.line_user_id AS caretaker_line_id
FROM public.work_orders wo
JOIN public.properties p ON p.id = wo.property_id
LEFT JOIN public.users u_assigned ON u_assigned.id = wo.assigned_to
LEFT JOIN public.users u_caretaker ON u_caretaker.id = p.caretaker_id
WHERE wo.id IN (
  SELECT DISTINCT work_order_id FROM public.work_order_comments
)
ORDER BY wo.title;
