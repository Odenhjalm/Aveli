CREATE TABLE IF NOT EXISTS app.billing_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    event_type TEXT NOT NULL DEFAULT 'billing_log',
    payload JSONB,
    related_order_id UUID,
    user_id UUID,
    step TEXT NOT NULL,
    info JSONB NOT NULL DEFAULT '{}'::jsonb
);
