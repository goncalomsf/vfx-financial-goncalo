# vfx_goncalo — E-commerce Master Data Layer

dbt (Fusion engine) project on BigQuery that turns a flat e-commerce export
into a governed, canonical "master" layer.

Source dataset: [Kaggle e-commerce dataset](https://www.kaggle.com/datasets/steve1215rogg/e-commerce-dataset)
(`ecommerce_dataset_updated` — one row = one user's one purchase).

## Running instructions

1. Set up `~/.dbt/profiles.yml` with a BigQuery service-account target for
   profile `vfx_goncalo` (see `dbt_project.yml` for the profile name).
   The raw source table must exist in `<target.schema>`.
2. Install packages:
   ```
   dbt deps
   ```
3. Build the FX rate seed:
   ```
   dbt seed
   ```
4. Build everything (staging views + master tables) and run all tests:
   ```
   dbt build
   ```

## Architecture / layers

- **raw** (schema `<target.schema>`, e.g. `test_gf`) — `ecommerce_dataset_updated`,
  landed by an external tool. Defined in `models/staging/__sources.yml`.
- **staging** (schema `<target.schema>`, views) — `stg_ecom__orders`: a single
  1:1 model over the one source table. Renames to snake_case, casts, and
  normalizes `category`/`payment_method` (lowercase, spaces → underscores).
- **master** (schema **`master`**, tables) — `master_users`, `master_products`,
  `master_orders`: the canonical layer. Deterministic surrogate keys, deduped,
  contracts enforced.

The `master` schema is a literal dataset (not `<target.schema>_master`) via a
`generate_schema_name` override in `macros/generate_schema_name.sql` — this is
dbt's documented "alternative pattern" for giving each layer its own dataset.

## Assumptions made

- Per assignment instructions, source columns `Price_Rs` / `Final_Price_Rs`
  are treated as **USD**, despite the "Rs" naming.
- Each source row is one user's one purchase, and in this dataset every
  `User_ID` and `Product_ID` is unique across the ~3,660 rows (no repeat
  customers/products). `master_users`/`master_products` still `select distinct`
  as a defensive dedup, even though it's a no-op on this data.
- `usd_to_gbp_rate` seed: a fixed 0.75 rate for every day of 2024 (per "0.75
  fixed rate is fine"). Dates were reformatted to ISO `YYYY-MM-DD` and typed
  as `DATE` (BigQuery requires ISO format for `DATE` columns) so it can be
  joined directly on `order_date`.

## Design choices

- **dbt-recommended CTE structure.** Every model follows the standard dbt
  style guide pattern: an import CTE per `source`/`ref` (named after what it
  selects from), one logical transformation per CTE, a final `final` CTE, and
  a trailing `select * from final`.
- **One staging model.** There's a single flat source table at order grain —
  splitting it into per-entity staging models (users/products/orders) would
  duplicate renaming/casting logic three times. Entity-splitting, dedup, and
  key generation belong in the master layer, which is exactly what this
  exercise asks the master layer to do.
- **Deterministic surrogate keys.** `*_master_id` columns are
  `dbt_utils.generate_surrogate_key` (md5) hashes of natural keys. Per Kimball,
  fact↔dimension joins use warehouse-generated keys, not raw source IDs.
  Natural keys (`user_id`, `product_id`) are retained alongside for
  traceability.
- **Frozen master schemas.** All three master models have
  `config.contract.enforced: true` with explicit `data_type` per column — any
  column added/removed/retyped without updating `schema.yml` fails the build.
- **Reusable macro.** Currency conversion (`amount * usd_to_gpb_rate`) is
  duplicated for `price_gbp` and `final_price_gbp` in `master_orders`, so it's
  extracted into `macros/convert_to_gbp.sql`.
- **Data quality.** 27 tests across the master layer: `unique`/`not_null` on
  every key, `relationships` for FK validation (`master_orders` →
  `master_users`/`master_products`), `accepted_values` on `payment_method` and
  `product_category`, and positive-value checks on every price/GBP column.

## GDPR delete handling (master_users)

**Chosen approach: anonymize-in-place, preserve the surrogate key** — the
standard "right to erasure" pattern for warehouse dimensions. A
`deletion_requests` table (`user_id`, `requested_at`) would be LEFT JOINed into
`master_users`; for matched users, PII columns get nulled/redacted while
`user_master_id` is preserved. This keeps `master_orders`'s FK valid and
historical aggregates (revenue, order counts) correct — you erase *personal
data*, not the *entity*.

**Not implemented here**: `master_users` currently only has `user_master_id`
(hash) and `user_id` (an opaque source identifier — not name/email/address),
so there's nothing to redact in this dataset. The join point for
`deletion_requests` would sit in `master_users.sql`, at exactly the spot where
PII columns would be scrubbed once they exist.

## Freshness & anomaly metrics (proposed, not implemented)

- **Freshness**: dbt's `freshness:` block needs a load timestamp (e.g.
  Fivetran's `_fivetran_synced`). The source has no such column — only
  `Purchase_Date`, a business date — so configuring freshness against it would
  be measuring the wrong thing. Proposal once a sync-timestamp column exists:
  ```yaml
  freshness:
    warn_after: {count: 12, period: hour}
    error_after: {count: 24, period: hour}
  loaded_at_field: _fivetran_synced
  ```
- **Anomalies**:
  - Daily row-count check vs. a rolling average (catch silent load failures).
  - `discount_percentage` outside `[0, 100]`.
  - `final_price_usd > price_usd` (final price shouldn't exceed list price).

## SCD2 note (master_products)

Best candidate attributes: **`product_category`** and **`price_usd`** — both
could legitimately change for the same `product_id` over time. Approach: a
dbt snapshot with the `check` strategy on these two columns over a
products-grain source, producing `dbt_valid_from`/`dbt_valid_to` for historical
category/pricing analysis.

Not implemented: the source is a single static load with no repeated extracts
to diff, so a snapshot today would only capture one version — there's no
history to demonstrate.

## What I'd extend with double the time

- Multiple source systems feeding `master_users`/`master_products` — the
  actual "unify entities across sources" scenario, with match/merge logic.
- A real `deletion_requests` seed + anonymization `CASE WHEN` in
  `master_users`, demoed end-to-end.
- dbt snapshots for SCD2 on `master_products`, simulating two source loads to
  show `dbt_valid_from`/`dbt_valid_to` in action.
- Incremental `master_orders` instead of full-refresh tables, with a
  late-arriving-updates strategy (merge on `order_master_id`, track
  status/cancellations/refunds via an `is_current`/`status` column).
- CI running `dbt build` + tests on PRs, and a generated dbt docs site.
