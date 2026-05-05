# make-nodes-paytm

[![Make](https://img.shields.io/badge/Make-Custom%20App-blue)](https://www.make.com)
[![Paytm API](https://img.shields.io/badge/Paytm-Merchant%20API%20v2-blue)](https://developer.paytm.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Official Paytm custom app for [Make](https://www.make.com) (formerly Integromat).  
14 modules covering Order, Payment Link, Refund, Settlement, Subscription, and Universal API calls.

---

## Architecture

All modules call the **merchant-adapter signing proxy**, not Paytm directly.

```
Make module  →  proxy /make/{functionName}?mid=XXX  →  Paytm API
              [HMAC-SHA256 inbound auth]           [AES checksum outbound]
```

Paytm's checksum algorithm (`AES-128-CBC(SHA256(sorted_values + salt) + salt, keySecret, IV)`) cannot be computed in Make IML — there is no `aes()` or `encrypt()` function. The proxy handles all Paytm signing server-side. Make modules only need to authenticate to the proxy via HMAC-SHA256, which IML can compute.

**Proxy base URLs:**

| Environment | Proxy URL |
|-------------|-----------|
| Production | `https://paytm-make-proxy.paytmpayments.com` |
| Staging | `https://paytm-make-proxy-staging.paytmpayments.com` |

**Every module follows this request pattern:**
```jsonc
{
    "url": "{{connection.baseUrl}}/make/{functionName}?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{uuid()}}",
        "timestamp": "{{toTimestamp(now)}}",
        "params": { ...module-specific params... }
    }
}
```

---

## Modules

### Order
| Module | Type | Description | Downstream |
|--------|------|-------------|------------|
| `fetchOrderList` | Search | List transactions within a date range | `POST /merchant-passbook/search/list/order/v2` |
| `orderDetail` | Action | Detailed info for a single order | RTDD via proxy |

### Payment Link
| Module | Type | Description | Downstream |
|--------|------|-------------|------------|
| `fetchPaymentLinks` | Search | List all payment links | `POST /link/fetch` |
| `fetchTransactionsForLink` | Search | Transactions for a specific payment link | `POST /link/fetchTransaction` |
| `createPaymentLink` | Action | Create a new payment link | `POST /link/create` |

### Refund
| Module | Type | Description | Downstream |
|--------|------|-------------|------------|
| `fetchRefundList` | Search | List refunds for a date range | `POST /merchant-passbook/api/v1/refundList` |
| `checkRefundStatus` | Action | Check the status of a specific refund | `POST /v2/refund/status` |
| `initiateRefund` | Action | Initiate a new refund | `POST /refund/apply` |

### Settlement
| Module | Type | Description | Downstream |
|--------|------|-------------|------------|
| `settlementTxnListByDate` | Search | List settled transactions by date range | RTDD via proxy |
| `settlementBillList` | Search | List settlement bills / payouts | RTDD via proxy |

### Subscription
| Module | Type | Description | Downstream |
|--------|------|-------------|------------|
| `fetchSubscriptionStatus` | Action | Get status of a subscription | `POST /subscription/subscription/checkStatus` |
| `pauseResumeSubscription` | Action | Pause or resume an active subscription | `POST /subscription/subscription/status/modify` |
| `cancelSubscription` | Action | Cancel a subscription | `POST /subscription/subscription/cancel` |

### Universal
| Module | Type | Description |
|--------|------|-------------|
| `makeApiCall` | Universal | Custom Paytm API call for endpoints not covered by other modules. Accepts a relative path — proxy prepends the base URL. Required by Make platform. |

---

## Connection

The connection stores three fields:

| Field | Label | Type | Purpose |
|-------|-------|------|---------|
| `merchantId` | Merchant ID | text | Paytm MID — passed as `?mid=` on every proxy call |
| `keySecret` | Key Secret | password | Used for HMAC inbound auth to the proxy and by the proxy to sign the downstream Paytm checksum. Never logged or sent to Paytm directly. |
| `baseUrl` | Environment | select | Proxy base URL — determines the Paytm environment downstream |

Connection validation sends a lightweight signed request to `/make/fetchPaymentLinks`. HTTP 200 means the HMAC was accepted — credentials are valid at the proxy level.

---

## Repository Structure

```
make-nodes-paytm/
├── app/
│   ├── connections/
│   │   └── paytm.jsonc             # Connection (credential) definition
│   ├── modules/
│   │   ├── fetchOrderList.jsonc
│   │   ├── orderDetail.jsonc
│   │   ├── fetchPaymentLinks.jsonc
│   │   ├── fetchTransactionsForLink.jsonc
│   │   ├── createPaymentLink.jsonc
│   │   ├── fetchRefundList.jsonc
│   │   ├── checkRefundStatus.jsonc
│   │   ├── initiateRefund.jsonc
│   │   ├── settlementTxnListByDate.jsonc
│   │   ├── settlementBillList.jsonc
│   │   ├── fetchSubscriptionStatus.jsonc
│   │   ├── pauseResumeSubscription.jsonc
│   │   ├── cancelSubscription.jsonc
│   │   └── makeApiCall.jsonc
│   └── remote-procedures/          # Dynamic dropdown data loaders
│       └── listCurrencies.jsonc
├── docs/
│   ├── api-mapping.md              # Full parameter mapping for all modules
│   └── checksum-algorithm.md       # Paytm checksum deep-dive + proxy rationale
├── scripts/
│   └── validate-jsonc.sh           # CI helper: strips comments, validates JSON
└── README.md
```

---

## How to Use

> **Make does not support importing JSONC files directly.** These files are the source of truth for version control. To update the live app, copy the relevant section into Make's Apps Editor (JSON tab) after stripping JSONC comments.

1. In [Make Apps Editor](https://www.make.com/en/integrations), open the **Paytm** app.
2. Navigate to the relevant Module or Connection.
3. Copy the content from the corresponding `.jsonc` file.
4. Strip JSONC comments (the `scripts/validate-jsonc.sh` helper does this) before pasting.
5. Save in Make.

---

## Development

### Adding a new module

1. Create `app/modules/<moduleName>.jsonc` using the standard proxy pattern:
   ```jsonc
   {
       "url": "{{connection.baseUrl}}/make/<functionName>?mid={{connection.merchantId}}",
       "method": "POST",
       "headers": {
           "Content-Type": "application/json",
           "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
       },
       "body": {
           "requestId": "{{uuid()}}",
           "timestamp": "{{toTimestamp(now)}}",
           "params": {
               // module-specific params
           }
       },
       "response": { ... }
   }
   ```
2. `<functionName>` must match the function name registered in the merchant-adapter proxy.
3. Do **not** compute any checksum in IML — the proxy handles all Paytm signing server-side.
4. Add the module to the tables in this README and in `docs/api-mapping.md`.
5. Open a PR referencing the corresponding PG Jira ticket.

---

## Compatibility

| Dimension | Value |
|-----------|-------|
| Make API | Custom Apps v2 |
| Paytm Merchant API | v2 (Production + Staging) |
| IML version | Make IML (semicolon separator) |

---

## License

MIT © Paytm Payments Services Ltd.
