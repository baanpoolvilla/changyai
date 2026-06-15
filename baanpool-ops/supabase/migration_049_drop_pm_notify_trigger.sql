-- migration_049: ลบ trigger trg_pm_schedule_notify ที่เรียก notify_pm_due()
-- notify_pm_due() ถูกลบไปใน migration_041 แล้ว แต่ trigger ยังหลงเหลืออยู่
-- ทำให้ INSERT pm_schedules ล้มเหลวทุกครั้ง
-- ระบบแจ้งเตือน PM ตอนนี้ใช้ cron check_pm_due_schedules() แทน

DROP TRIGGER IF EXISTS trg_pm_schedule_notify ON public.pm_schedules;
DROP FUNCTION IF EXISTS public.trg_pm_schedule_notify();
