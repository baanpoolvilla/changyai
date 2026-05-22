-- migration_038_comment_images.sql
-- เพิ่มคอลัมน์รูปภาพให้ comment ทั้งหมด (work_order_comments + purchase_order_comments)

ALTER TABLE work_order_comments
  ADD COLUMN IF NOT EXISTS image_url TEXT;

ALTER TABLE purchase_order_comments
  ADD COLUMN IF NOT EXISTS image_url TEXT;
