-- =====================================================
-- BaanPool Ops — Migration 015: Allow caretaker to manage PM Schedules
-- Fix: caretaker ไม่สามารถเพิ่ม PM Schedule ได้ (RLS 42501)
-- Run this SQL in Supabase SQL Editor (Dashboard > SQL)
-- =====================================================

-- ─── 1. Caretaker can INSERT / UPDATE / DELETE PM schedules
--        for properties they manage (caretaker_id = auth.uid()) ─────

DROP POLICY IF EXISTS "Caretaker can manage own property PM schedules" ON public.pm_schedules;
CREATE POLICY "Caretaker can manage own property PM schedules"
  ON public.pm_schedules FOR ALL
  TO authenticated
  USING (
    public.get_user_role() = 'caretaker'
    AND property_id IN (
      SELECT id FROM public.properties WHERE caretaker_id = auth.uid()
    )
  )
  WITH CHECK (
    public.get_user_role() = 'caretaker'
    AND property_id IN (
      SELECT id FROM public.properties WHERE caretaker_id = auth.uid()
    )
  );
