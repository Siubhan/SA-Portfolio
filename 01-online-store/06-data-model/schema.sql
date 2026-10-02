-- ============================================================
-- Схема БД: Интернет-магазин
-- СУБД: PostgreSQL 14+
-- Источник: 06-data-model/erd (Lucid) — см. ссылку в README проекта
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto"; -- для gen_random_uuid()

-- ------------------------------------------------------------
-- ENUM-типы статусов (вместо VARCHAR + CHECK — чище и быстрее)
-- ------------------------------------------------------------

CREATE TYPE order_status AS ENUM (
    'new',              -- Новый
    'awaiting_payment', -- Ожидает оплаты
    'paid',             -- Оплачен
    'processing',       -- В обработке
    'shipped',          -- Отправлен
    'completed',        -- Выполнен
    'cancelled'         -- Отменён
);

CREATE TYPE payment_status AS ENUM (
    'pending',          -- Ожидает
    'succeeded',        -- Успешно
    'failed',           -- Отклонён
    'refund_pending',   -- Возврат в обработке
    'refunded'          -- Возврат выполнен
);

CREATE TYPE reservation_status AS ENUM (
    'active',           -- Активна
    'fulfilled',        -- Реализована (оформлен заказ)
    'expired',          -- Истёк срок
    'cancelled'         -- Отменена
);

-- ------------------------------------------------------------
-- customers
-- ------------------------------------------------------------
CREATE TABLE customers (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name          VARCHAR(150) NOT NULL,
    email         VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    phone         VARCHAR(30),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------
-- admins
-- ------------------------------------------------------------
CREATE TABLE admins (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email         VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role          VARCHAR(50)  NOT NULL DEFAULT 'admin'
);

-- ------------------------------------------------------------
-- categories
-- ------------------------------------------------------------
CREATE TABLE categories (
    id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL UNIQUE
);

-- ------------------------------------------------------------
-- products
-- ------------------------------------------------------------
CREATE TABLE products (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id    UUID NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
    name           VARCHAR(200) NOT NULL,
    description    TEXT,
    price          DECIMAL(10,2) NOT NULL CHECK (price >= 0),
    stock_quantity INT NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    photo_url      VARCHAR(500),
    is_active      BOOLEAN NOT NULL DEFAULT true  -- для деактивации вместо удаления (см. UC-07)
);

CREATE INDEX idx_products_category ON products(category_id);

-- ------------------------------------------------------------
-- carts (1:0..1 с customers)
-- ------------------------------------------------------------
CREATE TABLE carts (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL UNIQUE REFERENCES customers(id) ON DELETE CASCADE
);

-- ------------------------------------------------------------
-- cart_items
-- ------------------------------------------------------------
CREATE TABLE cart_items (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cart_id    UUID NOT NULL REFERENCES carts(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    quantity   INT  NOT NULL CHECK (quantity > 0),
    UNIQUE (cart_id, product_id) -- один товар — одна строка, количество суммируется
);

CREATE INDEX idx_cart_items_cart ON cart_items(cart_id);

-- ------------------------------------------------------------
-- orders
-- ------------------------------------------------------------
CREATE TABLE orders (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id            UUID REFERENCES customers(id) ON DELETE SET NULL, -- NULL = гостевой заказ
    processed_by_admin_id  UUID REFERENCES admins(id) ON DELETE SET NULL,
    status                 order_status NOT NULL DEFAULT 'new',
    total_amount           DECIMAL(10,2) NOT NULL CHECK (total_amount >= 0),
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    guest_name             VARCHAR(150),
    guest_contact          VARCHAR(255),
    shipping_address       TEXT NOT NULL,
    CONSTRAINT chk_order_owner CHECK (
        customer_id IS NOT NULL OR (guest_name IS NOT NULL AND guest_contact IS NOT NULL)
    ) -- заказ обязан иметь либо customer_id, либо гостевые контакты (FR-09)
);

CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_orders_status   ON orders(status);

-- ------------------------------------------------------------
-- order_items
-- ------------------------------------------------------------
CREATE TABLE order_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id        UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id      UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    quantity        INT NOT NULL CHECK (quantity > 0),
    price_at_order  DECIMAL(10,2) NOT NULL CHECK (price_at_order >= 0) -- цена на момент заказа, не актуальная из products
);

CREATE INDEX idx_order_items_order ON order_items(order_id);

-- ------------------------------------------------------------
-- payments
-- ------------------------------------------------------------
CREATE TABLE payments (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id                UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    status                  payment_status NOT NULL DEFAULT 'pending',
    amount                  DECIMAL(10,2) NOT NULL CHECK (amount >= 0),
    method                  VARCHAR(50) NOT NULL,
    gateway_transaction_id  VARCHAR(255),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_payments_order ON payments(order_id);

-- ------------------------------------------------------------
-- reservations
-- ------------------------------------------------------------
CREATE TABLE reservations (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    product_id  UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    status      reservation_status NOT NULL DEFAULT 'active',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at  TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_reservations_customer ON reservations(customer_id);
CREATE INDEX idx_reservations_product  ON reservations(product_id);

-- ------------------------------------------------------------
-- favorites
-- ------------------------------------------------------------
CREATE TABLE favorites (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    product_id  UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    UNIQUE (customer_id, product_id)
);

CREATE INDEX idx_favorites_customer ON favorites(customer_id);
