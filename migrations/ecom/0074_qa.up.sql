-- 0074_qa.up.sql — product Q&A (catalog_schema, decision Tranche 3 §2.2).
-- user_id is plain BIGINT (no cross-schema FK to identity, matching product_reviews).

CREATE TABLE IF NOT EXISTS catalog_schema.product_questions (
    id               BIGSERIAL   PRIMARY KEY,
    product_id       BIGINT      NOT NULL REFERENCES catalog_schema.products(id) ON DELETE CASCADE,
    user_id          BIGINT      NOT NULL,
    author_name      TEXT        NOT NULL DEFAULT '',
    body             TEXT        NOT NULL,
    status           TEXT        NOT NULL DEFAULT 'published',
    submitted_locale TEXT        NOT NULL DEFAULT 'tr',
    answer_count     INTEGER     NOT NULL DEFAULT 0,  -- denormalized; product_answers authoritative
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_product_questions_product
    ON catalog_schema.product_questions (product_id, created_at DESC) WHERE status = 'published';
CREATE INDEX IF NOT EXISTS idx_product_questions_user
    ON catalog_schema.product_questions (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS catalog_schema.product_answers (
    id               BIGSERIAL   PRIMARY KEY,
    question_id      BIGINT      NOT NULL REFERENCES catalog_schema.product_questions(id) ON DELETE CASCADE,
    user_id          BIGINT      NOT NULL,
    author_name      TEXT        NOT NULL DEFAULT '',
    is_seller        BOOLEAN     NOT NULL DEFAULT false,
    body             TEXT        NOT NULL,
    status           TEXT        NOT NULL DEFAULT 'published',
    submitted_locale TEXT        NOT NULL DEFAULT 'tr',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_product_answers_question
    ON catalog_schema.product_answers (question_id, created_at ASC) WHERE status = 'published';
