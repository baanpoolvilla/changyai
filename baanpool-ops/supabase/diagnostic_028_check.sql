-- =====================================================
-- Diagnostic 028: ตรวจสอบว่าทำไม LINE ยังไม่ส่ง
-- รัน query ทีละ block แล้วดูผลลัพธ์
-- =====================================================

-- ─── Block 1: Token ตั้งค่าแล้วหรือยัง ───────────────
SELECT
  key,
  CASE
    WHEN value IS NULL OR value = '' THEN '❌ ว่างเปล่า'
    WHEN value = 'REPLACE_WITH_YOUR_TOKEN' THEN '❌ ยังเป็น placeholder ต้องอัปเดต token'
    WHEN value = 'your-actual-token-here' THEN '❌ ลืมเปลี่ยน ยังเป็น example'
    ELSE '✅ ตั้งค่าแล้ว (length=' || length(value) || ')'
  END AS status,
  left(value, 20) || '...' AS token_preview
FROM public.app_settings
WHERE key = 'line_messaging_token';

-- ─── Block 2: Users มี line_user_id หรือยัง ──────────
SELECT
  full_name,
  role,
  CASE
    WHEN line_user_id IS NOT NULL AND line_user_id != ''
      THEN '✅ ' || left(line_user_id, 10) || '...'
    ELSE '❌ ไม่มี line_user_id'
  END AS line_id_status
FROM public.users
ORDER BY role, full_name;

-- ─── Block 3: pg_net ส่ง HTTP จริงไหม (responses ล่าสุด) 
SELECT
  id,
  status_code,
  left(content::text, 300) AS response_body,
  created
FROM net._http_response
ORDER BY created DESC
LIMIT 10;

-- ─── Block 4: ทดสอบส่ง LINE ตรงๆ (ใส่ line_user_id จริง)
-- เปลี่ยน 'Uxxxxxxxxxx' เป็น line_user_id ของคุณ แล้วรัน
/*
SELECT public.send_line_text(
  'Uxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
  '🧪 ทดสอบ LINE notification จาก database trigger'
);
*/
