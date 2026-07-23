-- =====================================================
-- BaanPool Ops — Migration 059
-- ตาราง equipment_returns: แจ้ง "คืนของ / ของมีปัญหา"
-- ผูกกับ purchase_orders เดิม + มีสถานะดำเนินการ
-- =====================================================

CREATE TABLE IF NOT EXISTS public.equipment_returns (
  id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_order_id  UUID         NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
  property_id        UUID         REFERENCES public.properties(id) ON DELETE SET NULL,
  item_name          TEXT,                       -- ชื่อของที่มีปัญหา (จาก items ของ PO)
  qty                INTEGER      NOT NULL DEFAULT 1,
  problem_type       TEXT         NOT NULL DEFAULT 'other'
                                  CHECK (problem_type IN ('defective','wrong','damaged','missing','other')),
  reason             TEXT         NOT NULL,       -- รายละเอียดปัญหา
  status             TEXT         NOT NULL DEFAULT 'pending'
                                  CHECK (status IN ('pending','processing','resolved','cancelled')),
  image_urls         JSONB        NOT NULL DEFAULT '[]'::jsonb,
  resolution_note    TEXT,                        -- วิธีจัดการ/ผลลัพธ์
  created_by         UUID         REFERENCES public.users(id) ON DELETE SET NULL,
  resolved_by        UUID         REFERENCES public.users(id) ON DELETE SET NULL,
  created_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  resolved_at        TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_eqret_po       ON public.equipment_returns(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_eqret_status   ON public.equipment_returns(status);
CREATE INDEX IF NOT EXISTS idx_eqret_property ON public.equipment_returns(property_id);

-- updated_at auto-update
CREATE OR REPLACE FUNCTION public.update_eqret_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;
DROP TRIGGER IF EXISTS trg_eqret_updated_at ON public.equipment_returns;
CREATE TRIGGER trg_eqret_updated_at
  BEFORE UPDATE ON public.equipment_returns
  FOR EACH ROW EXECUTE FUNCTION public.update_eqret_updated_at();

-- ─── RLS ──────────────────────────────────────────────
ALTER TABLE public.equipment_returns ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='equipment_returns' AND policyname='eqret read all') THEN
    CREATE POLICY "eqret read all"
      ON public.equipment_returns FOR SELECT TO authenticated USING (true);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='equipment_returns' AND policyname='eqret insert own') THEN
    CREATE POLICY "eqret insert own"
      ON public.equipment_returns FOR INSERT TO authenticated
      WITH CHECK (auth.uid() = created_by);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='equipment_returns' AND policyname='eqret update') THEN
    CREATE POLICY "eqret update"
      ON public.equipment_returns FOR UPDATE TO authenticated
      USING (
        auth.uid() = created_by
        OR EXISTS (
          SELECT 1 FROM public.users
          WHERE id = auth.uid() AND role IN ('admin','owner','manager')
        )
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='equipment_returns' AND policyname='eqret delete admin') THEN
    CREATE POLICY "eqret delete admin"
      ON public.equipment_returns FOR DELETE TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.users
          WHERE id = auth.uid() AND role IN ('admin','owner','manager')
        )
      );
  END IF;
END $$;

SELECT 'migration_059 OK' AS result;
