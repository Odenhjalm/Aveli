-- 20260119000000_order_type_bundle.sql
-- Allow bundle checkouts to reuse the orders table.

alter type app.order_type add value if not exists 'bundle';

