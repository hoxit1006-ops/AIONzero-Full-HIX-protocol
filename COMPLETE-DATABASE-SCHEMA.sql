-- ============================================
-- HIX PROTOCOL - COMPLETE DATABASE SCHEMA
-- Run this ONCE in Supabase SQL Editor
-- This is EVERYTHING you need!
-- ============================================

-- ============================================
-- 1. MOTION_DATA TABLE (Core mining data)
-- ============================================
CREATE TABLE IF NOT EXISTS motion_data (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    wallet_address TEXT NOT NULL,
    timestamp TIMESTAMPTZ DEFAULT now() NOT NULL,
    acceleration JSONB NOT NULL,
    rotation JSONB NOT NULL,
    magnitude DOUBLE PRECISION,
    heart_rate DOUBLE PRECISION,
    device_type TEXT NOT NULL,
    session_id UUID NOT NULL,
    activity_type TEXT NOT NULL,
    task_name TEXT NOT NULL,
    device_tier INTEGER DEFAULT 1,
    is_suspicious BOOLEAN DEFAULT FALSE,
    suspension_reason TEXT,
    is_validated BOOLEAN DEFAULT FALSE,
    validated_by TEXT,
    validation_timestamp TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for fast queries
CREATE INDEX IF NOT EXISTS idx_motion_wallet ON motion_data(wallet_address);
CREATE INDEX IF NOT EXISTS idx_motion_session ON motion_data(session_id);
CREATE INDEX IF NOT EXISTS idx_motion_created ON motion_data(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_motion_task ON motion_data(task_name);
CREATE INDEX IF NOT EXISTS idx_motion_suspicious ON motion_data(is_suspicious, is_validated);

-- Enable RLS
ALTER TABLE motion_data ENABLE ROW LEVEL SECURITY;

-- Policy: Allow INSERT (anon users can submit motion data)
DROP POLICY IF EXISTS "Allow insert motion_data" ON motion_data;
CREATE POLICY "Allow insert motion_data" ON motion_data
    FOR INSERT TO anon, authenticated
    WITH CHECK (true);

-- ============================================
-- 2. USERS TABLE (Miner totals)
-- ============================================
CREATE TABLE IF NOT EXISTS users (
    wallet_address TEXT PRIMARY KEY,
    total_vectors BIGINT DEFAULT 0,
    earned_hix DECIMAL(20, 6) DEFAULT 0,
    device_tier INTEGER DEFAULT 1,
    referral_code TEXT UNIQUE,
    referral_earnings DECIMAL(20, 6) DEFAULT 0,
    is_validator BOOLEAN DEFAULT FALSE,
    validator_earnings DECIMAL(20, 6) DEFAULT 0,
    validator_license_paid BOOLEAN DEFAULT FALSE,
    last_active TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_wallet ON users(wallet_address);
CREATE INDEX IF NOT EXISTS idx_users_validator ON users(is_validator);
CREATE INDEX IF NOT EXISTS idx_users_referral ON users(referral_code);

ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read their own data
DROP POLICY IF EXISTS "Users can read own data" ON users;
CREATE POLICY "Users can read own data" ON users
    FOR SELECT TO anon, authenticated
    USING (wallet_address = current_setting('request.jwt.claim.sub', true));

-- ============================================
-- 3. NETWORK_STATS TABLE (Global pulse)
-- ============================================
CREATE TABLE IF NOT EXISTS network_stats (
    id INTEGER PRIMARY KEY DEFAULT 1,
    total_vectors BIGINT DEFAULT 0,
    vectors_today BIGINT DEFAULT 0,
    active_miners_24h INTEGER DEFAULT 0,
    total_validators INTEGER DEFAULT 0,
    active_validators INTEGER DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT single_row CHECK (id = 1)
);

-- Initialize
INSERT INTO network_stats (id, total_vectors, vectors_today, active_miners_24h, total_validators, active_validators)
VALUES (1, 0, 0, 0, 0, 0)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE network_stats ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow read network_stats" ON network_stats;
CREATE POLICY "Allow read network_stats" ON network_stats
    FOR SELECT TO anon, authenticated
    USING (true);

-- ============================================
-- 4. VALIDATOR_NODES TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS validator_nodes (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    wallet_address TEXT NOT NULL UNIQUE,
    license_number INTEGER UNIQUE,
    payment_amount DECIMAL(10, 2) NOT NULL,
    payment_tx_hash TEXT,
    payment_timestamp TIMESTAMPTZ DEFAULT NOW(),
    tier TEXT NOT NULL,
    reward_multiplier DECIMAL(4, 2) DEFAULT 1.0,
    total_validations BIGINT DEFAULT 0,
    total_earnings DECIMAL(20, 6) DEFAULT 0,
    accuracy_score DECIMAL(5, 4) DEFAULT 1.0,
    is_active BOOLEAN DEFAULT TRUE,
    last_validation TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_validator_wallet ON validator_nodes(wallet_address);
CREATE INDEX IF NOT EXISTS idx_validator_license ON validator_nodes(license_number);

ALTER TABLE validator_nodes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Validators can read own data" ON validator_nodes;
CREATE POLICY "Validators can read own data" ON validator_nodes
    FOR SELECT TO anon, authenticated
    USING (wallet_address = current_setting('request.jwt.claim.sub', true));

-- ============================================
-- 5. REFERRALS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS referrals (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    referrer_wallet TEXT NOT NULL,
    referee_wallet TEXT NOT NULL,
    referral_code TEXT NOT NULL,
    lifetime_earnings DECIMAL(20, 6) DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(referrer_wallet, referee_wallet)
);

CREATE INDEX IF NOT EXISTS idx_referrals_referrer ON referrals(referrer_wallet);
CREATE INDEX IF NOT EXISTS idx_referrals_referee ON referrals(referee_wallet);

ALTER TABLE referrals ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 6. TASKS TABLE (Missions)
-- ============================================
CREATE TABLE IF NOT EXISTS tasks (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT,
    bounty_multiplier DOUBLE PRECISION DEFAULT 1.0,
    category TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Seed default tasks
INSERT INTO tasks (title, bounty_multiplier, category) VALUES
    ('General Mining', 1.0, 'phone'),
    ('Precision Stability (Phone)', 1.5, 'phone'),
    ('Patrol Walk (Phone)', 1.2, 'phone'),
    ('Squat & Stand (Phone)', 1.3, 'phone'),
    ('Tool Usage (Watch)', 2.5, 'watch'),
    ('Door Opening (Watch)', 2.0, 'watch'),
    ('Keyboard Typing (Watch)', 1.8, 'watch'),
    ('Hand Washing (Watch)', 2.0, 'watch')
ON CONFLICT DO NOTHING;

ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow read tasks" ON tasks;
CREATE POLICY "Allow read tasks" ON tasks
    FOR SELECT TO anon, authenticated
    USING (is_active = true);

-- ============================================
-- 7. HELPER FUNCTIONS
-- ============================================

-- Increment user vectors
CREATE OR REPLACE FUNCTION increment_user_vectors(
    p_wallet_address TEXT,
    p_increment INTEGER DEFAULT 1,
    p_tier_multiplier DECIMAL DEFAULT 1.0
)
RETURNS void AS $$
DECLARE
    hix_reward DECIMAL;
BEGIN
    hix_reward := p_increment * 0.0001 * p_tier_multiplier;
    
    INSERT INTO users (wallet_address, total_vectors, earned_hix, device_tier, last_active)
    VALUES (p_wallet_address, p_increment, hix_reward, p_tier_multiplier::INTEGER, NOW())
    ON CONFLICT (wallet_address) 
    DO UPDATE SET
        total_vectors = users.total_vectors + p_increment,
        earned_hix = users.earned_hix + hix_reward,
        last_active = NOW(),
        updated_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION increment_user_vectors TO anon;
GRANT EXECUTE ON FUNCTION increment_user_vectors TO authenticated;

-- Increment network stats
CREATE OR REPLACE FUNCTION increment_network_stats()
RETURNS void AS $$
BEGIN
    UPDATE network_stats
    SET vectors_today = vectors_today + 1,
        total_vectors = total_vectors + 1,
        updated_at = NOW()
    WHERE id = 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION increment_network_stats TO anon;
GRANT EXECUTE ON FUNCTION increment_network_stats TO authenticated;

-- Get user full stats
CREATE OR REPLACE FUNCTION get_user_full_stats(p_wallet TEXT)
RETURNS TABLE (
    total_vectors BIGINT,
    earned_hix DECIMAL,
    device_tier INTEGER,
    referral_code TEXT,
    referral_earnings DECIMAL,
    is_validator BOOLEAN,
    validator_earnings DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.total_vectors,
        u.earned_hix,
        u.device_tier,
        u.referral_code,
        u.referral_earnings,
        u.is_validator,
        u.validator_earnings
    FROM users u
    WHERE u.wallet_address = p_wallet;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_user_full_stats TO anon;
GRANT EXECUTE ON FUNCTION get_user_full_stats TO authenticated;

-- ============================================
-- 8. ANTI-CHEAT ENGINE (submit_motion)
-- ============================================

CREATE OR REPLACE FUNCTION submit_motion(
    p_wallet_address TEXT,
    p_acceleration JSONB,
    p_rotation JSONB,
    p_session_id UUID,
    p_device_tier INTEGER
)
RETURNS JSONB AS $$
DECLARE
    v_acc_x DECIMAL;
    v_acc_y DECIMAL;
    v_acc_z DECIMAL;
    v_magnitude DECIMAL;
    v_is_suspicious BOOLEAN := FALSE;
    v_reason TEXT := NULL;
    v_last_time TIMESTAMPTZ;
BEGIN
    -- Extract physics data
    v_acc_x := (p_acceleration->>0)::DECIMAL;
    v_acc_y := (p_acceleration->>1)::DECIMAL;
    v_acc_z := (p_acceleration->>2)::DECIMAL;
    
    -- Calculate magnitude
    v_magnitude := SQRT(v_acc_x^2 + v_acc_y^2 + v_acc_z^2);
    
    -- CHECK: Impossible acceleration (Max 20G)
    IF v_magnitude > 20 OR v_magnitude < 0.1 THEN
        v_is_suspicious := TRUE;
        v_reason := 'Impossible acceleration magnitude';
    END IF;

    -- CHECK: Rate limiting (Max 5 per second)
    SELECT created_at INTO v_last_time 
    FROM motion_data 
    WHERE wallet_address = p_wallet_address 
    ORDER BY created_at DESC LIMIT 1;

    IF v_last_time IS NOT NULL AND NOW() - v_last_time < INTERVAL '200 milliseconds' THEN
         v_is_suspicious := TRUE;
         v_reason := 'Rate limit exceeded';
    END IF;

    -- Record the data
    INSERT INTO motion_data (
        wallet_address, 
        acceleration, 
        rotation, 
        session_id, 
        device_tier, 
        magnitude, 
        is_suspicious, 
        suspension_reason,
        is_validated,
        device_type,
        activity_type,
        task_name,
        timestamp
    ) VALUES (
        p_wallet_address, 
        p_acceleration, 
        p_rotation, 
        p_session_id,
        p_device_tier, 
        v_magnitude, 
        v_is_suspicious, 
        v_reason,
        FALSE,
        'mobile',
        'general',
        'Continuous Mining',
        NOW()
    );

    -- Reward user (only if not suspicious)
    IF NOT v_is_suspicious THEN
        PERFORM increment_user_vectors(p_wallet_address, 1, p_device_tier::DECIMAL);
        PERFORM increment_network_stats();
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE, 
        'is_suspicious', v_is_suspicious,
        'vector_counted', NOT v_is_suspicious,
        'reason', v_reason
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION submit_motion TO anon;
GRANT EXECUTE ON FUNCTION submit_motion TO authenticated;

-- ============================================
-- 9. VALIDATOR NODE PURCHASE FUNCTION
-- ============================================

CREATE OR REPLACE FUNCTION purchase_validator_node(
    p_wallet_address TEXT,
    p_tier TEXT,
    p_payment_amount DECIMAL,
    p_payment_tx_hash TEXT
)
RETURNS INTEGER AS $$
DECLARE
    license_num INTEGER;
    multiplier DECIMAL;
BEGIN
    -- Determine multiplier and license range
    CASE p_tier
        WHEN 'genesis' THEN
            license_num := (SELECT COALESCE(MAX(license_number), 0) + 1 FROM validator_nodes WHERE license_number BETWEEN 1 AND 10);
            multiplier := 5.0;
        WHEN 'gold' THEN
            license_num := (SELECT COALESCE(MAX(license_number), 10) + 1 FROM validator_nodes WHERE license_number BETWEEN 11 AND 100);
            multiplier := 2.0;
        WHEN 'silver' THEN
            license_num := (SELECT COALESCE(MAX(license_number), 100) + 1 FROM validator_nodes WHERE license_number BETWEEN 101 AND 500);
            multiplier := 1.5;
        ELSE -- bronze
            license_num := (SELECT COALESCE(MAX(license_number), 500) + 1 FROM validator_nodes WHERE license_number BETWEEN 501 AND 1000);
            multiplier := 1.0;
    END CASE;
    
    -- Insert validator node
    INSERT INTO validator_nodes (
        wallet_address,
        license_number,
        payment_amount,
        payment_tx_hash,
        payment_timestamp,
        tier,
        reward_multiplier
    ) VALUES (
        p_wallet_address,
        license_num,
        p_payment_amount,
        p_payment_tx_hash,
        NOW(),
        p_tier,
        multiplier
    );
    
    -- Update user to validator status
    INSERT INTO users (wallet_address, is_validator, validator_license_paid)
    VALUES (p_wallet_address, TRUE, TRUE)
    ON CONFLICT (wallet_address)
    DO UPDATE SET
        is_validator = TRUE,
        validator_license_paid = TRUE;
    
    -- Update network stats
    UPDATE network_stats
    SET total_validators = total_validators + 1,
        active_validators = active_validators + 1
    WHERE id = 1;
    
    RETURN license_num;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION purchase_validator_node TO anon;
GRANT EXECUTE ON FUNCTION purchase_validator_node TO authenticated;

-- ============================================
-- DONE! YOUR COMPLETE DATABASE IS READY!
-- ============================================

-- Quick test:
-- SELECT submit_motion('TEST', '[2,2,2]'::jsonb, '[0,0,0]'::jsonb, gen_random_uuid(), 1);
