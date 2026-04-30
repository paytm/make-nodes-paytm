# make-nodes-paytm

[![Make](https://img.shields.io/badge/Make-Custom%20App-blue)](https://www.make.com)
[![Paytm API](https://img.shields.io/badge/Paytm-Merchant%20API%20v2-blue)](https://developer.paytm.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Official Paytm custom app for [Make](https://www.make.com) (formerly Integromat).  
Provides full API parity with the [n8n-nodes-paytm](https://github.com/paytm/n8n-nodes-paytm) package — 13 modules across Order, Payment Link, Refund, Settlement, and Subscription.

---

## Modules

### Order
| Module | Description | Paytm API |
|--------|-------------|-----------|
| `fetchOrderList` | List transactions within a date range | `POST /merchant-passbook/search/list/order/v2` |
| `orderDetail` | Detailed info for a single order | `POST /merchant-adapter/internal/ORDER_DETAIL` |

### Payment Link
| Module | Description | Paytm API |
|--------|-------------|-----------|
| `fetchPaymentLinks` | List all payment links | `POST /link/fetch` |
| `fetchTransactionsForLink` | Transactions for a specific payment link | `POST /link/fetchTransaction` |
| `createPaymentLink` | Create a new payment link | `POST /link/create` |

### Refund
| Module | Description | Paytm API |
|--------|-------------|-----------|
| `fetchRefundList` | List refunds for a date range | `POST /merchant-passbook/api/v1/refundList` |
| `checkRefundStatus` | Check the status of a specific refund | `POST /v2/refund/status` |
| `initiateRefund` | Initiate a new refund | `POST /refund/apply` |

### Settlement
| Module | Description | Paytm API |
|--------|-------------|-----------|
| `settlementTxnListByDate` | List settled transactions by date range | `POST /merchant-adapter/internal/TxnListByDate` |
| `settlementBillList` | List settlement bills / payouts | `POST /merchant-adapter/internal/BILL_LIST` |

### Subscription
| Module | Description | Paytm API |
|--------|-------------|-----------|
| `fetchSubscriptionStatus` | Get status of a subscription | `POST /subscription/subscription/checkStatus` |
| `pauseResumeSubscription` | Pause or resume an active subscription | `POST /subscription/subscription/status/modify` |
| `cancelSubscription` | Cancel a subscription | `POST /subscription/subscription/cancel` |

---

## Authentication

Most modules use **Paytm Checksum** (HMAC-SHA256) in a `head`/`body` request envelope:

```json
{
  "body": { "mid": "...", "...": "request params" },
  "head": { "tokenType": "AES", "signature": "<checksum>", "channelId": "WEB" }
}
```

Checksum algorithm:
1. Sort body parameter **keys** alphabetically.
2. Concatenate their **values** in sorted-key order, each suffixed with `|`.
3. Append the merchant's **Key Secret**.
4. Compute `SHA-256` and Base64-encode the result.

Settlement modules (Order Detail, Settlement Txn List, Settlement Bill List) use a separate **Settlement Envelope** with a different signature pattern.

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
│   │   └── cancelSubscription.jsonc
│   └── remote-procedures/          # Dynamic dropdown data loaders
│       └── listCurrencies.jsonc
├── docs/
│   ├── api-mapping.md              # n8n → Make module mapping
│   └── checksum-algorithm.md       # Paytm checksum deep-dive
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

1. Create `app/modules/<moduleName>.jsonc` following the pattern of an existing module.
2. Determine the alphabetical key-sort order for the endpoint's body params — this governs the checksum signing string. Document it in the file header comment.
3. Build the `temp` block: one entry per body param that needs formatting or defaulting, each value suffixed with `|`.
4. Assemble the `sha256()` call using only `temp.*` references — no nested function calls inside `sha256()` (Make IML parser limitation).
5. Add the module to the table in this README.
6. Open a PR referencing the corresponding PG Jira ticket.

### Checksum signing string — key sort reference

Every `.jsonc` module file documents the exact signing string order in its file-header comment. Always verify against:
- Paytm's official Node SDK: `lib/utils/PaytmChecksum.js`
- Paytm Merchant API documentation for the specific endpoint.

---

## Compatibility

| Dimension | Value |
|-----------|-------|
| Make API | Custom Apps v2 |
| Paytm Merchant API | v2 (Production + Staging) |
| n8n parity | v1.6.1 (`n8n-nodes-paytm`) |
| IML version | Make IML (semicolon separator) |

---

## License

MIT © Paytm Payments Services Ltd.
