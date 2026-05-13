-- migration_030: add is_self_purchase flag to purchase_orders
-- Run this in Supabase SQL editor

ALTER TABLE public.purchase_orders
  ADD COLUMN IF NOT EXISTS is_self_purchase boolean NOT NULL DEFAULT false;
