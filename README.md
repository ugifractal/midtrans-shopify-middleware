# Midtrans Shopify Middleware

Custom Shopify app proxy middleware that powers a hosted **Midtrans** (Snap)
checkout. It quotes cart totals/shipping via the Shopify Storefront API, snaps
the checkout into `midtrans_checkouts`, creates a Midtrans Snap transaction and
redirects the buyer to the Midtrans-hosted payment page, and — when the Midtrans
HTTP(S) notification reports a successful capture/settlement — creates the
Shopify order via the Admin GraphQL API.

## Setup

Copy the environment template and fill in your values. Real secrets are never
committed — `.env.development` and `.env.production` are gitignored (see
`.gitignore`), and `.env.example` only holds placeholders.

```sh
cp .env.example .env.development   # local development
# or, for a production deploy:
cp .env.example .env.production
```

Then install dependencies and boot the app:

```sh
bin/setup          # or: bundle install && bin/rails db:prepare
bin/dev            # dev server (Puma + JS bundling)
```

`HOST` must be a public URL reachable by both Shopify webhooks and the Midtrans
HTTP(S) Notification URL (use a tunnel in development, e.g.
`https://your-tunnel.example.com`).

## Environment variables

All values are loaded from `.env.development` / `.env.production` via
`dotenv-rails`. `.env.example` is the single source of placeholder keys.

| Variable | Required | Where used | Notes |
| --- | --- | --- | --- |
| `SHOPIFY_API_KEY` | yes | Shopify app auth | Partners dashboard app key |
| `SHOPIFY_API_SECRET` | yes | Shopify app auth + proxy/HMAC signing | Partners dashboard app secret |
| `HOST` | yes | Shopify `Context.setup` | Public URL of the app |
| `MIDTRANS_SERVER_KEY` | yes | Snap API Basic auth + notification `signature_key` verify | Midtrans dashboard server key |
| `MIDTRANS_IS_PRODUCTION` | no | Snap API endpoint select | `true` → production; empty/false → sandbox |
| `MIDTRANS_CLIENT_KEY` | no | (future) snap.js popup | Only needed if switching from redirect mode |

## Midtrans Notification URL

Midtrans notifies this app on transaction status changes (capture, settlement,
pending, deny, cancel, expire, …). In the Midtrans dashboard set the **Payment
Notification URL** to:

```
https://<HOST>/api/midtrans/hooks
```

The hook verifies `signature_key`
(`SHA512(order_id + status_code + gross_amount + MIDTRANS_SERVER_KEY)`),
integrity-checks `gross_amount` against the stored snapshot, correlates via
`order_id` (== our `custom_reference`), marks the matching `MidtransCheckout`
paid on `capture`/`settlement`, and enqueues `MidtransCreateOrderJob`, which
creates the Shopify order via the Admin `orderCreate` mutation with a `CUSTOM`
payment referencing the Midtrans transaction. `pending`/`challenge` statuses are
recorded but do **not** create an order.

## Create a Snap transaction

The middleware calls the Snap API (`POST /snap/v1/transactions`) with the
server key using Basic auth. The response's `redirect_url` is where the buyer is
redirected. Snap locks the amount at transaction-creation time, so the buyer
cannot alter it.

Midtrans natively supports IDR, so amounts are charged directly in the store's
currency (IDR) with no FX conversion layer.

## Ruby version

Stated in `.ruby-version`. Developed against Ruby 3.4.x.

## System dependencies

* Ruby (see `.ruby-version`)
* PostgreSQL
* Node.js + Bun (JS bundling via `jsbundling-rails`)
* Shopify CLI (for app auth/tunneling)

## Database creation

```sh
bin/rails db:create
bin/rails db:migrate
```

The middleware uses a single `midtrans_checkouts` table (plus the stock Shopify
app tables). Shopify orders are created via the Admin API; the local `orders`
table is populated by the `orders/create` webhook.

## How to run the test suite

```sh
bin/rails test
bundle exec rubocop
```

## Services

* **Solid Queue** (Active Job) — processes `MidtransCreateOrderJob` and webhook
  jobs.
