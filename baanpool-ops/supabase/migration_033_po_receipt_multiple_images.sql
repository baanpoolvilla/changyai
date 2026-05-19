-- =====================================================
-- BaanPool Ops — Migration 033
-- เพิ่มคอลัมน์ receipt_image_urls (JSONB array)
-- เพื่อรองรับการแนบรูปใบเสร็จได้มากกว่า 1 รูป
-- =====================================================

ALTER TABLE public.purchase_orders
  ADD COLUMN IF NOT EXISTS receipt_image_urls JSONB NOT NULL DEFAULT '[]'::jsonb;

-- ย้ายข้อมูลเดิมจาก receipt_image_url เข้าไปใน array (ถ้ามี)
UPDATE public.purchase_orders
SET receipt_image_urls = jsonb_build_array(receipt_image_url)
WHERE receipt_image_url IS NOT NULL
  AND receipt_image_urls = '[]'::jsonb;
