-- ============================================
-- WEEKLY LEADERBOARD WITH PRIZES
-- Drives 3x engagement + FOMO!
-- ============================================

-- 1. CREATE LEADERBOARD TABLE
CREATE TABLE IF NOT EXISTS leaderboard_weekly (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    wallet_address TEXT NOT NULL,
    week_start DATE NOT NULL,
    total_vectors BIGINT DEFAULT 0,
    earned_hix DECIMAL(20, 6) DEFAULT 0,
    rank INTEGER,
    prize_amount DECIMAL(20, 6) DEFAULT 0,
    prize_type TEXT, -- 'hix', 'validator_node', 'hardware'
    prize_claimed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(wallet_address, week_start)
);

CREATE INDEX IF NOT EXISTS idx_leaderboard_week ON leaderboard_weekly(week_start, rank);
CREATE INDEX IF NOT EXISTS idx_leaderboard_wallet ON leaderboard_weekly(wallet_address);

-- Enable RLS
ALTER TABLE leaderboard_weekly ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read leaderboard" ON leaderboard_weekly;
CREATE POLICY "Anyone can read leaderboard" ON leaderboard_weekly
    FOR SELECT TO anon, authenticated
    USING (true);

-- 2. FUNCTION TO UPDATE LEADERBOARD (Run hourly)
CREATE OR REPLACE FUNCTION update_weekly_leaderboard()
RETURNS void AS $$
DECLARE
    v_week_start DATE;
BEGIN
    -- Get start of current week (Monday)
    v_week_start := DATE_TRUNC('week', NOW())::DATE;
    
    -- Calculate weekly stats
    WITH week_stats AS (
        SELECT 
            m.wallet_address,
            COUNT(*) as vectors,
            u.earned_hix,
            ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) as rank
        FROM motion_data m
        LEFT JOIN users u ON u.wallet_address = m.wallet_address
        WHERE m.created_at >= v_week_start
        AND m.is_suspicious = FALSE
        GROUP BY m.wallet_address, u.earned_hix
    )
    INSERT INTO leaderboard_weekly (
        wallet_address, 
        week_start, 
        total_vectors, 
        earned_hix,
        rank
    )
    SELECT 
        wallet_address, 
        v_week_start, 
        vectors,
        earned_hix,
        rank
    FROM week_stats
    ON CONFLICT (wallet_address, week_start)
    DO UPDATE SET
        total_vectors = EXCLUDED.total_vectors,
        earned_hix = EXCLUDED.earned_hix,
        rank = EXCLUDED.rank,
        updated_at = NOW();
    
    -- Assign prizes
    UPDATE leaderboard_weekly
    SET 
        prize_amount = CASE
            WHEN rank = 1 THEN 1000  -- $1,000 value
            WHEN rank BETWEEN 2 AND 5 THEN 100
            WHEN rank BETWEEN 6 AND 10 THEN 50
            WHEN rank BETWEEN 11 AND 100 THEN 10
            ELSE 0
        END,
        prize_type = CASE
            WHEN rank = 1 THEN 'validator_node'
            WHEN rank BETWEEN 2 AND 100 THEN 'hix'
            ELSE NULL
        END
    WHERE week_start = v_week_start
    AND prize_claimed = FALSE;
END;
$$ LANGUAGE plpgsql;

-- Grant execute
GRANT EXECUTE ON FUNCTION update_weekly_leaderboard TO anon;
GRANT EXECUTE ON FUNCTION update_weekly_leaderboard TO authenticated;

-- 3. FUNCTION TO GET CURRENT WEEK LEADERBOARD
CREATE OR REPLACE FUNCTION get_current_leaderboard(p_limit INTEGER DEFAULT 100)
RETURNS TABLE (
    wallet_address TEXT,
    total_vectors BIGINT,
    rank INTEGER,
    prize_amount DECIMAL,
    prize_type TEXT
) AS $$
DECLARE
    v_week_start DATE;
BEGIN
    v_week_start := DATE_TRUNC('week', NOW())::DATE;
    
    RETURN QUERY
    SELECT 
        l.wallet_address,
        l.total_vectors,
        l.rank,
        l.prize_amount,
        l.prize_type
    FROM leaderboard_weekly l
    WHERE l.week_start = v_week_start
    ORDER BY l.rank ASC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION get_current_leaderboard TO anon;
GRANT EXECUTE ON FUNCTION get_current_leaderboard TO authenticated;

-- 4. FUNCTION TO CLAIM PRIZE
CREATE OR REPLACE FUNCTION claim_weekly_prize(p_wallet TEXT)
RETURNS JSONB AS $$
DECLARE
    v_week_start DATE;
    v_prize_amount DECIMAL;
    v_prize_type TEXT;
    v_rank INTEGER;
BEGIN
    v_week_start := DATE_TRUNC('week', NOW() - INTERVAL '1 week')::DATE;  -- Last week
    
    -- Get prize info
    SELECT prize_amount, prize_type, rank
    INTO v_prize_amount, v_prize_type, v_rank
    FROM leaderboard_weekly
    WHERE wallet_address = p_wallet
    AND week_start = v_week_start
    AND prize_claimed = FALSE;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'message', 'No unclaimed prize found'
        );
    END IF;
    
    -- Mark as claimed
    UPDATE leaderboard_weekly
    SET prize_claimed = TRUE
    WHERE wallet_address = p_wallet
    AND week_start = v_week_start;
    
    -- Award prize
    IF v_prize_type = 'hix' THEN
        -- Add HIX to user account
        UPDATE users
        SET earned_hix = earned_hix + v_prize_amount
        WHERE wallet_address = p_wallet;
    ELSIF v_prize_type = 'validator_node' THEN
        -- Give free validator node (manual process, just flag it)
        UPDATE users
        SET is_validator = TRUE
        WHERE wallet_address = p_wallet;
    END IF;
    
    RETURN jsonb_build_object(
        'success', TRUE,
        'prize_amount', v_prize_amount,
        'prize_type', v_prize_type,
        'rank', v_rank
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION claim_weekly_prize TO anon;
GRANT EXECUTE ON FUNCTION claim_weekly_prize TO authenticated;

-- 5. DAILY STREAKS
ALTER TABLE users ADD COLUMN IF NOT EXISTS current_streak INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS longest_streak INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_mine_date DATE;

CREATE OR REPLACE FUNCTION get_streak_multiplier(p_wallet TEXT)
RETURNS DECIMAL AS $$
DECLARE
    v_streak INTEGER;
BEGIN
    SELECT current_streak INTO v_streak
    FROM users WHERE wallet_address = p_wallet;
    
    RETURN CASE
        WHEN v_streak >= 100 THEN 5.0
        WHEN v_streak >= 30 THEN 3.0
        WHEN v_streak >= 14 THEN 2.0
        WHEN v_streak >= 7 THEN 1.5
        WHEN v_streak >= 3 THEN 1.2
        ELSE 1.0
    END;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION get_streak_multiplier TO anon;
GRANT EXECUTE ON FUNCTION get_streak_multiplier TO authenticated;

CREATE OR REPLACE FUNCTION update_user_streak(p_wallet TEXT)
RETURNS void AS $$
DECLARE
    v_last_mine DATE;
    v_current_streak INTEGER;
BEGIN
    SELECT last_mine_date, current_streak 
    INTO v_last_mine, v_current_streak
    FROM users WHERE wallet_address = p_wallet;
    
    -- Check if already mined today
    IF v_last_mine = CURRENT_DATE THEN
        RETURN;
    END IF;
    
    -- Check if streak continues
    IF v_last_mine = CURRENT_DATE - 1 THEN
        -- Continue streak
        UPDATE users
        SET current_streak = current_streak + 1,
            longest_streak = GREATEST(longest_streak, current_streak + 1),
            last_mine_date = CURRENT_DATE
        WHERE wallet_address = p_wallet;
    ELSE
        -- Streak broken
        UPDATE users
        SET current_streak = 1,
            last_mine_date = CURRENT_DATE
        WHERE wallet_address = p_wallet;
    END IF;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION update_user_streak TO anon;
GRANT EXECUTE ON FUNCTION update_user_streak TO authenticated;

-- ============================================
-- DONE! LEADERBOARD + STREAKS ACTIVE!
-- ============================================

-- Test it:
-- SELECT update_weekly_leaderboard();
-- SELECT * FROM get_current_leaderboard(10);

-- Run this hourly via cron:
-- SELECT cron.schedule('update-leaderboard', '0 * * * *', 'SELECT update_weekly_leaderboard()');
