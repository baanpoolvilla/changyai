-- =====================================================
-- ตรวจสอบพื้นที่เก็บไฟล์ที่ใช้ไปแล้ว (read-only ไม่แก้ข้อมูลใดๆ)
-- วางทั้งไฟล์นี้ใน Supabase Dashboard → SQL Editor แล้วกด Run
-- =====================================================

-- ─── 1) ใช้ไปเท่าไหร่ แยกตาม bucket ───────────────────
SELECT
  bucket_id,
  COUNT(*) AS files,
  pg_size_pretty(SUM((metadata->>'size')::BIGINT)) AS used,
  pg_size_pretty(AVG((metadata->>'size')::BIGINT)::BIGINT) AS avg_per_file
FROM storage.objects
GROUP BY bucket_id
ORDER BY SUM((metadata->>'size')::BIGINT) DESC NULLS LAST;


-- ─── 2) รวมทั้งโปรเจกต์ + เหลืออีกเท่าไหร่ ─────────────
-- แก้ค่า quota_gb ให้ตรงกับแพ็กเกจที่ใช้:
--   Free = 1, Pro = 100
WITH q AS (SELECT 1::NUMERIC AS quota_gb),
used AS (
  SELECT COALESCE(SUM((metadata->>'size')::BIGINT), 0)::NUMERIC AS bytes,
         COUNT(*) AS files
  FROM storage.objects
)
SELECT
  used.files AS total_files,
  pg_size_pretty(used.bytes::BIGINT) AS used,
  pg_size_pretty((q.quota_gb * 1073741824)::BIGINT) AS quota,
  ROUND(used.bytes / (q.quota_gb * 1073741824) * 100, 1) AS used_percent,
  pg_size_pretty((q.quota_gb * 1073741824 - used.bytes)::BIGINT) AS remaining,
  -- ประเมินจากรูปที่ย่อแล้ว ~400 KB/รูป (หลัง migration_062)
  FLOOR((q.quota_gb * 1073741824 - used.bytes) / 409600) AS photos_left_estimate
FROM used, q;


-- ─── 3) ขนาดรูปเฉลี่ยรายเดือน ─────────────────────────
-- ใช้ดูว่าตัวแก้ได้ผลจริงไหม — เดือนหลัง deploy ค่า avg_size
-- ควรลดลงเหลือหลักร้อย KB จากเดิมหลาย MB
SELECT
  TO_CHAR(DATE_TRUNC('month', created_at), 'YYYY-MM') AS month,
  COUNT(*) AS files,
  pg_size_pretty(AVG((metadata->>'size')::BIGINT)::BIGINT) AS avg_size,
  pg_size_pretty(MAX((metadata->>'size')::BIGINT)) AS largest
FROM storage.objects
GROUP BY 1
ORDER BY 1 DESC
LIMIT 6;


-- ─── 4) 20 ไฟล์ที่ใหญ่ที่สุด ──────────────────────────
-- ถ้าเจอไฟล์เก่าขนาดหลาย MB คือรูปที่อัปก่อนแก้บั๊ก
-- ลบทิ้งได้ถ้าไม่จำเป็น จะคืนพื้นที่เยอะ
SELECT
  bucket_id,
  name,
  pg_size_pretty((metadata->>'size')::BIGINT) AS size,
  created_at
FROM storage.objects
ORDER BY (metadata->>'size')::BIGINT DESC NULLS LAST
LIMIT 20;
