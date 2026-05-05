-- =====================================================
-- BaanPool Ops — Notification Read Timestamp + Auto-Cleanup
-- =====================================================
-- 1. Add read_at timestamp to notifications
-- 2. Auto-delete notifications that were read 2+ days ago
-- =====================================================

-- 1. Add read_at column
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS read_at TIMESTAMPTZ;

COMMENT ON COLUMN public.notifications.read_at IS 'เวลาที่อ่านการแจ้งเตือน (ใช้สำหรับลบอัตโนมัติหลัง 2 วัน)';

-- 2. Update the mark-as-read to set read_at (this is handled via the UPDATE policy)
-- The Flutter app will set read_at = now() when marking as read.

-- 3. Create a function to clean up old read notifications (read > 2 days ago)
CREATE OR REPLACE FUNCTION public.cleanup_old_notifications()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM public.notifications
  WHERE is_read = TRUE
    AND read_at IS NOT NULL
    AND read_at < NOW() - INTERVAL '2 days';
END;
$$;

-- 4. If pg_cron extension is available, schedule daily cleanup
-- (Uncomment if pg_cron is enabled in your Supabase project)
-- SELECT cron.schedule('cleanup-notifications', '0 3 * * *', 'SELECT public.cleanup_old_notifications();');
