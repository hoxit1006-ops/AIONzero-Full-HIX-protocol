-- ============================================
-- PREMIUM MINING PASSES - COMPLETE IMPLEMENTATION
-- Add this to your existing database
-- Instant $50K+ revenue potential!
-- ============================================

-- 1. CREATE MINING PASSES TABLE
CREATE TABLE IF NOT EXISTS mining_passes (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    wallet_address TEXT NOT NULL,
    pass_tier TEXT NOT NULL, -- bronze, silver, gold, diamond
    multiplier DECIMAL(4,2) NOT NULL,
    purchase_amount DECIMAL(10, 2) NOT NULL,
    purchase_tx_hash TEXT,
    payment_provider TEXT DEFAULT 'lemon_squeezy',
    is_active BOOLEAN DEFAULT TRUE,
    expires_at TIMESTAMPTZ, -- NULL = lifetime
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(wallet_address, pass_tier)
);

CREATE INDEX IF NOT EXISTS idx_passes_wallet ON mining_passes(wallet_address);
CREATE INDEX IF NOT EXISTS idx_passes_active ON mining_passes(is_active, expires_at);

-- Enable RLS
ALTER TABLE mining_passes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own passes" ON mining_passes;
CREATE POLICY "Users can read own passes" ON mining_passes
    FOR SELECT TO anon, authenticated
    USING (wallet_address = current_setting('request.jwt.claim.sub', true));

-- 2. FUNCTION TO GET USER'S BEST MULTIPLIER
CREATE OR REPLACE FUNCTION get_user_pass_multiplier(p_wallet TEXT)
RETURNS DECIMAL AS $$
DECLARE
    best_multiplier DECIMAL;
BEGIN
    SELECT COALESCE(MAX(multiplier), 1.0)
    INTO best_multiplier
    FROM mining_passes
    WHERE wallet_address = p_wallet
    AND is_active = TRUE
    AND (expires_at IS NULL OR expires_at > NOW());
    
    RETURN best_multiplier;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_user_pass_multiplier TO anon;
GRANT EXECUTE ON FUNCTION get_user_pass_multiplier TO authenticated;

-- 3. FUNCTION TO PURCHASE PASS
CREATE OR REPLACE FUNCTION purchase_mining_pass(
    p_wallet_address TEXT,
    p_tier TEXT,
    p_amount DECIMAL,
    p_tx_hash TEXT
)
RETURNS UUID AS $$
DECLARE
    v_pass_id UUID;
    v_multiplier DECIMAL;
BEGIN
    -- Determine multiplier by tier
    v_multiplier := CASE p_tier
        WHEN 'bronze' THEN 1.5
        WHEN 'silver' THEN 2.0
        WHEN 'gold' THEN 3.0
        WHEN 'diamond' THEN 5.0
        ELSE 1.0
    END;
    
    -- Insert the pass
    INSERT INTO mining_passes (
        wallet_address,
        pass_tier,
        multiplier,
        purchase_amount,
        purchase_tx_hash,
        expires_at
    ) VALUES (
        p_wallet_address,
        p_tier,
        v_multiplier,
        p_amount,
        p_tx_hash,
        NULL  -- Lifetime pass
    )
    RETURNING id INTO v_pass_id;
    
    RETURN v_pass_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION purchase_mining_pass TO anon;
GRANT EXECUTE ON FUNCTION purchase_mining_pass TO authenticated;

-- 4. UPDATE submit_motion TO USE PASS MULTIPLIER
-- Replace the existing submit_motion function with this enhanced version:

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
    v_pass_multiplier DECIMAL;
    v_total_multiplier DECIMAL;
BEGIN
    -- Extract physics data
    v_acc_x := (p_acceleration->>0)::DECIMAL;
    v_acc_y := (p_acceleration->>1)::DECIMAL;
    v_acc_z := (p_acceleration->>2)::DECIMAL;
    
    -- Calculate magnitude
    v_magnitude := SQRT(v_acc_x^2 + v_acc_y^2 + v_acc_z^2);
    
    -- Anti-cheat checks
    IF v_magnitude > 20 OR v_magnitude < 0.1 THEN
        v_is_suspicious := TRUE;
        v_reason := 'Impossible acceleration magnitude';
    END IF;

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
        wallet_address, acceleration, rotation, session_id, 
        device_tier, magnitude, is_suspicious, suspension_reason,
        is_validated, device_type, activity_type, task_name, timestamp
    ) VALUES (
        p_wallet_address, p_acceleration, p_rotation, p_session_id,
        p_device_tier, v_magnitude, v_is_suspicious, v_reason,
        FALSE, 'mobile', 'general', 'Continuous Mining', NOW()
    );

    -- Reward user (only if not suspicious)
    IF NOT v_is_suspicious THEN
        -- GET PASS MULTIPLIER! 🚀
        v_pass_multiplier := get_user_pass_multiplier(p_wallet_address);
        v_total_multiplier := p_device_tier::DECIMAL * v_pass_multiplier;
        
        PERFORM increment_user_vectors(p_wallet_address, 1, v_total_multiplier);
        PERFORM increment_network_stats();
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE, 
        'is_suspicious', v_is_suspicious,
        'vector_counted', NOT v_is_suspicious,
        'reason', v_reason,
        'multiplier', v_total_multiplier  -- Return multiplier to frontend
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION submit_motion TO anon;
GRANT EXECUTE ON FUNCTION submit_motion TO authenticated;

-- 5. FUNCTION TO GET USER PASS INFO
CREATE OR REPLACE FUNCTION get_user_pass_info(p_wallet TEXT)
RETURNS TABLE (
    pass_tier TEXT,
    multiplier DECIMAL,
    purchase_date TIMESTAMPTZ,
    is_active BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        mp.pass_tier,
        mp.multiplier,
        mp.created_at,
        mp.is_active
    FROM mining_passes mp
    WHERE mp.wallet_address = p_wallet
    AND mp.is_active = TRUE
    AND (mp.expires_at IS NULL OR mp.expires_at > NOW())
    ORDER BY mp.multiplier DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_user_pass_info TO anon;
GRANT EXECUTE ON FUNCTION get_user_pass_info TO authenticated;

-- ============================================
-- DONE! PREMIUM PASSES ARE NOW ACTIVE!
-- ============================================

-- Test it:
-- SELECT purchase_mining_pass('TEST_WALLET', 'gold', 199, 'test-tx-001');
-- SELECT get_user_pass_multiplier('TEST_WALLET');
-- Should return: 3.0

-- Now when TEST_WALLET mines, they get 3x rewards! 💰
