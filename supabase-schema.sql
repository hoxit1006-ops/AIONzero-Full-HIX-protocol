-- ============================================
-- HIX NODE - Fresh Supabase Schema
-- Run this in Supabase SQL Editor (Dashboard > SQL Editor > New query)
-- ============================================

-- Drop old tables if starting completely fresh (optional - comment out if you have a brand new project)
-- DROP TABLE IF EXISTS motion_data CASCADE;
-- DROP TABLE IF EXISTS network_value CASCADE;
-- DROP TABLE IF EXISTS tasks CASCADE;

-- ============================================
-- 1. MOTION_DATA - Core table for mining data
-- Matches exactly what your index.html sends
-- ============================================
CREATE TABLE IF NOT EXISTS motion_data (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    wallet_address TEXT NOT NULL,
    timestamp TIMESTAMPTZ DEFAULT now() NOT NULL,
    acceleration JSONB NOT NULL,  -- [x, y, z] array
    rotation JSONB NOT NULL,     -- [alpha, beta, gamma] array
    heart_rate DOUBLE PRECISION,
    device_type TEXT NOT NULL,   -- 'mobile' | 'watch'
    session_id UUID NOT NULL,
    activity_type TEXT NOT NULL, -- 'general' | 'imported_universal'
    task_name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Index for fast queries by wallet, session, time
CREATE INDEX IF NOT EXISTS idx_motion_wallet ON motion_data(wallet_address);
CREATE INDEX IF NOT EXISTS idx_motion_session ON motion_data(session_id);
CREATE INDEX IF NOT EXISTS idx_motion_created ON motion_data(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_motion_task ON motion_data(task_name);

-- ============================================
-- 2. NETWORK_VALUE - Miner totals (optional, for leaderboard)
-- ============================================
CREATE TABLE IF NOT EXISTS network_value (
    wallet_address TEXT PRIMARY KEY,
    total_vectors BIGINT DEFAULT 0,
    pending_hix NUMERIC(20, 6) DEFAULT 0,
    last_sync_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================
-- 3. TASKS - Mission definitions (optional, for future)
-- You can add missions here instead of hardcoding in app
-- ============================================
CREATE TABLE IF NOT EXISTS tasks (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT,
    bounty_multiplier DOUBLE PRECISION DEFAULT 1.0,
    category TEXT,  -- 'phone' | 'watch'
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Seed default tasks (match your current mission select) - run once
INSERT INTO tasks (title, bounty_multiplier, category) VALUES
    ('General Mining', 1.0, 'phone'),
    ('Precision Stability (Phone)', 1.5, 'phone'),
    ('Patrol Walk (Phone)', 1.2, 'phone'),
    ('Squat & Stand (Phone)', 1.3, 'phone'),
    ('Tool Usage (Watch)', 2.5, 'watch'),
    ('Door Opening (Watch)', 2.0, 'watch'),
    ('Keyboard Typing (Watch)', 1.8, 'watch'),
    ('Hand Washing (Watch)', 2.0, 'watch');

-- ============================================
-- 4. ROW LEVEL SECURITY (RLS)
-- Allow app to INSERT motion data, restrict reads
-- ============================================
ALTER TABLE motion_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE network_value ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;

-- Motion data: allow INSERT (your app uses anon key)
DROP POLICY IF EXISTS "Allow insert motion_data" ON motion_data;
CREATE POLICY "Allow insert motion_data" ON motion_data
    FOR INSERT TO anon, authenticated
    WITH CHECK (true);

-- Motion data: no SELECT policy = anon/authenticated cannot read (service_role bypasses RLS)

-- Tasks: anyone can read (for future mission list)
DROP POLICY IF EXISTS "Allow read tasks" ON tasks;
CREATE POLICY "Allow read tasks" ON tasks
    FOR SELECT TO anon, authenticated
    USING (is_active = true);

-- Network value: restrict for now (admin/backend only)
DROP POLICY IF EXISTS "No public network_value" ON network_value;
CREATE POLICY "No public network_value" ON network_value
    FOR ALL TO anon
    USING (false)
    WITH CHECK (false);

-- ============================================
-- 5. Function to upsert network_value on new motion
-- (Optional - uncomment if you want auto-totals)
-- ============================================
/*
CREATE OR REPLACE FUNCTION update_network_value()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO network_value (wallet_address, total_vectors, pending_hix, updated_at)
    VALUES (
        NEW.wallet_address,
        1,
        0,
        now()
    )
    ON CONFLICT (wallet_address) DO UPDATE SET
        total_vectors = network_value.total_vectors + 1,
        updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_motion_to_network ON motion_data;
CREATE TRIGGER trg_motion_to_network
    AFTER INSERT ON motion_data
    FOR EACH ROW EXECUTE FUNCTION update_network_value();
*/

-- ============================================
-- DONE! 
-- Your app posts to: /rest/v1/motion_data
-- ============================================
