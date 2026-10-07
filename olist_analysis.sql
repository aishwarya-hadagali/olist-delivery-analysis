-- =====================================================
-- Olist Delivery Performance Analysis (PostgreSQL)
-- =====================================================

-- ---------- 0. Tables ----------
CREATE TABLE IF NOT EXISTS customers (
    customer_id VARCHAR(50),
    customer_unique_id VARCHAR(50),
    customer_zip_code_prefix VARCHAR(10),
    customer_city VARCHAR(100),
    customer_state VARCHAR(5)
);

CREATE TABLE IF NOT EXISTS orders (
    order_id VARCHAR(50),
    customer_id VARCHAR(50),
    order_status VARCHAR(20),
    order_purchase_timestamp TIMESTAMP,
    order_approved_at TIMESTAMP,
    order_delivered_carrier_date TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP
);

CREATE TABLE IF NOT EXISTS order_items (
    order_id VARCHAR(50),
    order_item_id INT,
    product_id VARCHAR(50),
    seller_id VARCHAR(50),
    shipping_limit_date TIMESTAMP,
    price NUMERIC(10,2),
    freight_value NUMERIC(10,2)
);

CREATE TABLE IF NOT EXISTS order_reviews (
    review_id VARCHAR(50),
    order_id VARCHAR(50),
    review_score INT,
    review_comment_title TEXT,
    review_comment_message TEXT,
    review_creation_date TIMESTAMP,
    review_answer_timestamp TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sellers (
    seller_id VARCHAR(50),
    seller_zip_code_prefix VARCHAR(10),
    seller_city VARCHAR(100),
    seller_state VARCHAR(5)
);

-- ---------- Row-count check after importing the CSVs ----------
SELECT 'customers' AS tbl, COUNT(*) FROM customers
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'order_reviews', COUNT(*) FROM order_reviews
UNION ALL SELECT 'sellers', COUNT(*) FROM sellers;

-- ---------- 1. Order status profile ----------
SELECT order_status, COUNT(*) AS total_orders
FROM orders
GROUP BY order_status
ORDER BY total_orders DESC;

-- ---------- 2. Delay in days (negative = early, positive = late) ----------
SELECT
    order_id,
    order_delivered_customer_date,
    order_estimated_delivery_date,
    EXTRACT(DAY FROM (order_delivered_customer_date - order_estimated_delivery_date)) AS delay_days
FROM orders
WHERE order_status = 'delivered'
LIMIT 10;

-- ---------- 3. Late vs on-time (timestamps compared directly) ----------
SELECT
    CASE
        WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 'Late'
        ELSE 'On time or early'
    END AS delivery_status,
    COUNT(*) AS total_orders
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
GROUP BY delivery_status
ORDER BY total_orders DESC;

-- ---------- 4. Review score: late vs on time ----------
SELECT
    CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 'Late'
        ELSE 'On time or early'
    END AS delivery_status,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(AVG(r.review_score), 2) AS avg_review_score
FROM orders o
JOIN order_reviews r
    ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY delivery_status
ORDER BY total_orders DESC;

-- ---------- 5. Late-delivery rate by customer state ----------
SELECT
    c.customer_state,
    COUNT(*) AS delivered_orders,
    SUM(CASE
            WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1
            ELSE 0
        END) AS late_orders,
    ROUND(100.0 * SUM(CASE
            WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1
            ELSE 0
        END) / COUNT(*), 2) AS late_pct
FROM orders o
JOIN customers c
    ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY late_pct DESC;

-- ---------- 6. Same-state vs cross-state shipping ----------
SELECT
    CASE
        WHEN s.seller_state = c.customer_state THEN 'Same state'
        ELSE 'Different state'
    END AS shipping_type,
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    ROUND(
        100.0 * COUNT(DISTINCT CASE
                    WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
                    THEN o.order_id
                END) / COUNT(DISTINCT o.order_id), 2
    ) AS late_pct
FROM orders o
JOIN customers c    ON o.customer_id = c.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN sellers s      ON oi.seller_id = s.seller_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY shipping_type
ORDER BY late_pct DESC;

-- ---------- 7. Reporting view for Power BI (one row per delivered order) ----------
CREATE VIEW delivered_orders_analysis AS
SELECT
    o.order_id,
    o.order_purchase_timestamp::date AS purchase_date,
    c.customer_state,
    (o.order_delivered_customer_date::date
        - o.order_estimated_delivery_date::date) AS delay_days,
    CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 'Late'
        ELSE 'On time or early'
    END AS delivery_status,
    r.review_score
FROM orders o
JOIN customers c
    ON o.customer_id = c.customer_id
LEFT JOIN (
    SELECT order_id, AVG(review_score) AS review_score
    FROM order_reviews
    GROUP BY order_id
) r
    ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL;

-- Expected: 96470 rows
SELECT COUNT(*) FROM delivered_orders_analysis;
