-- migration_037_pr_image_urls.sql
-- เพิ่มคอลัมน์รูปประกอบ PR (แยกจากรูปใบเสร็จตอนรับของ)

ALTER TABLE purchase_orders
  ADD COLUMN IF NOT EXISTS pr_image_urls TEXT[] DEFAULT '{}';
