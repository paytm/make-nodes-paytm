# Make UI — modules: communication and parameters

Use when wiring modules in **Apps Editor**: define **mappable parameters** first, then **Communication**. Each section mirrors the repo JSONC sources under `app/`.

**Parameter definitions source:** [`make-module-parameters.json`](./make-module-parameters.json) (regenerate this doc after editing).

**Canonical long-form tables:** [`api-mapping.md`](./api-mapping.md) § *Parameter Mapping*.

**Typical paste order**

1. **Base** — [`app/base.jsonc`](../app/base.jsonc) (Content-Type, default error, log sanitize).
2. **Connection** — parameters JSON + Communication from [`app/connections/paytm.jsonc`](../app/connections/paytm.jsonc).
3. **Per module** — **Mappable parameters (`JSON`, paste)** then **Communication (`JSON`, paste)**.

**IML (current repo)**

| Context | `X-Signature` |
|--------|----------------|
| **Connection save** | `{{sha256(parameters.merchantId; 'hex'; parameters.keySecret; 'utf8')}}` |
| **All modules** | `{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}` |

- Use **4-argument** `sha256(message; 'hex'; keySecret; 'utf8')`. Two-arg `sha256(message; key)` is **not** HMAC in Make IML.
- **URL:** `{{connection.baseUrl}}/integration/{functionName}?mid={{connection.merchantId}}`
- **Modules:** `requestId` and `timestamp` = `{{formatDate(now; 'X')}}000`
- **Connection validation body:** `requestId` = `{{formatDate(now; 'X')}}`, `timestamp` = `{{formatDate(now; 'x')}}`, empty `params`
- **Content-Type** only in **Base** — modules omit it
- **Naming:** modules → `connection.*`; connection save → `parameters.*`

**Public Make hosts:** use routable merchant-adapter URLs (e.g. `https://secure.paytmpayments.com/merchant-adapter`). Avoid `secure-int` (private IP). Add `&env=production` or `&env=staging` on module URLs when required.

---

## Table of contents

0. [Base communication](#base-communication)
1. [Connection](#connection-parameters-not-modules)
2. [`createPaymentLink`](#2-createpaymentlink) — Action
3. [`fetchPaymentLinks`](#3-fetchpaymentlinks) — Search
4. [`fetchTransactionsForLink`](#4-fetchtransactionsforlink) — Search
5. [`fetchOrderList`](#5-fetchorderlist) — Search
6. [`orderDetail`](#6-orderdetail) — Action (RTDD / settlement via proxy)
7. [`initiateRefund`](#7-initiaterefund) — Action
8. [`checkRefundStatus`](#8-checkrefundstatus) — Action
9. [`fetchRefundList`](#9-fetchrefundlist) — Search
10. [`settlementBillList`](#10-settlementbilllist) — Search (RTDD)
11. [`settlementTxnListByDate`](#11-settlementtxnlistbydate) — Search (RTDD)
12. [`fetchSubscriptionStatus`](#12-fetchsubscriptionstatus) — Action
13. [`pauseResumeSubscription`](#13-pauseresumesubscription) — Action
14. [`cancelSubscription`](#14-cancelsubscription) — Action
15. [`makeApiCall`](#15-makeapicall) — Universal

---

## Base communication

**Source:** [`app/base.jsonc`](../app/base.jsonc)

### Base — Communication reference (`jsonc`)

```jsonc
/**
 * BASE COMMUNICATION — inherited by every module in this app.
 *
 * Defines:
 *   headers      — Content-Type applied to every outbound request (modules do NOT repeat this).
 *   response.error — Default error message shown in Make when a request fails.
 *   log.sanitize — Prevents X-Signature from appearing in Make's request logs.
 *
 * HOW TO USE IN MAKE
 *   Apps Editor → [App] → Base → Communications → paste the JSON below (strip JSONC comments first).
 */
{
    "headers": {
        "Content-Type": "application/json"
    },
    "response": {
        "error": {
            "message": "[{{statusCode}}] {{body.error}}"
        }
    },
    "log": {
        "sanitize": ["request.headers.X-Signature"]
    }
}
```

### Base — Communication (`JSON`, paste)

```json
{
    "headers": {
        "Content-Type": "application/json"
    },
    "response": {
        "error": {
            "message": "[{{statusCode}}] {{body.error}}"
        }
    },
    "log": {
        "sanitize": [
            "request.headers.X-Signature"
        ]
    }
}
```

---

## Connection parameters (not modules)

**Source:** [`app/connections/paytm.jsonc`](../app/connections/paytm.jsonc)

| Parameter `name` | Make `type` | Required |
|---|---|---|
| `merchantId` | `text` | Yes |
| `keySecret` | `password` | Yes |
| `baseUrl` | `select` | Yes |

### Connection — parameters (`JSON`, paste)

```json
[
  { "name": "merchantId", "label": "Merchant ID (MID)", "type": "text", "required": true },
  { "name": "keySecret", "label": "Key Secret", "type": "password", "required": true },
  {
    "name": "baseUrl",
    "label": "Environment",
    "type": "select",
    "required": true,
    "options": [
      { "label": "Production", "value": "https://securegw.paytm.in" },
      { "label": "Staging", "value": "https://securegw-stage.paytm.in" },
      { "label": "QA", "value": "https://pgp-qa5.paytm.in/merchant-adapter" }
    ]
  }
]
```

### Connection — Communication reference (`jsonc`)

```jsonc
/**
 * CONNECTION: Paytm Merchant
 * TYPE: apikey (API key / credential pair)
 *
 * Stores credentials for all Paytm API calls routed through the
 * merchant-adapter signing proxy. The proxy handles Paytm's AES-128-CBC
 * checksum — this cannot be computed in Make IML.
 *
 * FIELDS
 *   merchantId  – MID assigned by Paytm. Passed as ?mid= on every proxy call.
 *   keySecret   – Used for two things:
 *                   1. HMAC-SHA256 inbound auth to the proxy (X-Signature header).
 *                   2. The proxy uses it to sign the Paytm AES checksum downstream.
 *                 Marked password:true — Make never displays it after save.
 *   baseUrl     – Proxy base URL. Determines the Paytm environment downstream.
 *                 Production : https://securegw.paytm.in
 *                 Staging    : https://securegw-stage.paytm.in
 *                 QA         : https://pgp-qa5.paytm.in/merchant-adapter
 *
 * HOW AUTHENTICATION WORKS
 *   Make IML requires the 4-argument form of sha256 for proper HMAC-SHA256:
 *     sha256(message; 'hex'; key; 'utf8')
 *   The 2-argument form sha256(message; key) treats the second arg as the output
 *   encoding (not the HMAC key), producing plain SHA256 — NOT HMAC.
 *
 *   Connection validation signs merchantId (static, no timing issues since
 *   body cannot be accessed from connection headers in Make IML):
 *     X-Signature = HMAC-SHA256(merchantId, keySecret) — hex output
 *
 *   Every module request signs body.requestId:
 *     X-Signature = HMAC-SHA256(requestId, keySecret) — hex output
 *
 *   The proxy accepts either form and verifies before forwarding to Paytm.
 *   keySecret never travels to Paytm — only the HMAC header does.
 *
 * HOW TO COPY INTO MAKE
 *   Apps Editor → Connections → [your connection] → Communication tab → paste below.
 *   Parameters go into the separate Parameters tab as form fields.
 *
 * PARAMETERS TAB (define these as form fields)
 *   - name: merchantId  | label: Merchant ID  | type: text     | required: true
 *   - name: keySecret   | label: Key Secret    | type: password | required: true
 *   - name: baseUrl     | label: Environment   | type: select   | required: true
 *       options:
 *         - label: Production  | value: https://securegw.paytm.in
 *         - label: Staging     | value: https://securegw-stage.paytm.in
 *         - label: QA          | value: https://pgp-qa5.paytm.in/merchant-adapter
 */
{
    // Validation call — send a minimal signed request to the proxy.
    // Any HTTP 200 (even a downstream FAILED from Paytm) means the HMAC was
    // accepted and the credentials are valid at the proxy level.
    "url": "{{parameters.baseUrl}}/integration/fetchOrderList?mid={{parameters.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(parameters.merchantId; 'hex'; parameters.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
        "params": {}
    },
    "response": {
        // HTTP 200 from proxy = HMAC accepted = credentials valid.
        // HTTP 401 = wrong keySecret. HTTP 404 = proxy not enabled.
        "valid": "{{statusCode == 200}}",
        "error": {
            "message": "[{{statusCode}}] {{body.error}}"
        }
    },
    "log": {
        "sanitize": ["request.headers.X-Signature"]
    }
}
```

### Connection — Communication (`JSON`, paste)

```json
{
    "url": "{{parameters.baseUrl}}/integration/fetchOrderList?mid={{parameters.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(parameters.merchantId; 'hex'; parameters.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
        "params": {}
    },
    "response": {
        "valid": "{{statusCode == 200}}",
        "error": {
            "message": "[{{statusCode}}] {{body.error}}"
        }
    },
    "log": {
        "sanitize": [
            "request.headers.X-Signature"
        ]
    }
}
```

---

## 1. `createPaymentLink` (Action)

**Source:** [`app/modules/createPaymentLink.jsonc`](../app/modules/createPaymentLink.jsonc) · parameters: [`make-module-parameters.json`](./make-module-parameters.json) → `createPaymentLink`

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default |
|---|---|---|---|
| `linkName` | `text` | Yes | — |
| `linkDescription` | `text` | Yes | — |
| `linkType` | `select` | Yes | — |
| `amount` | `number` | No | — |
| `partialPayment` | `boolean` | No | — |
| `bindLinkIdMobile` | `boolean` | No | — |
| `maxPaymentsAllowed` | `integer` | No | — |
| `customerName` | `text` | No | — |
| `customerEmail` | `text` | No | — |
| `customerMobile` | `text` | No | — |
| `expiryDate` | `date` | No | — |
| `sendSms` | `boolean` | No | — |
| `sendEmail` | `boolean` | No | — |
| `merchantRequestId` | `text` | No | — |
| `customerId` | `text` | No | — |
| `linkNotes` | `text` | No | — |
| `statusCallbackUrl` | `text` | No | — |

### Mappable parameters (`JSON`, paste into Make)

`name` must match `parameters.<name>` in Communication.

```json
[
  {
    "name": "linkName",
    "label": "Link name",
    "type": "text",
    "required": true
  },
  {
    "name": "linkDescription",
    "label": "Link description",
    "type": "text",
    "required": true
  },
  {
    "name": "linkType",
    "label": "Link type",
    "type": "select",
    "required": true,
    "options": [
      {
        "label": "Fixed amount",
        "value": "FIXED"
      },
      {
        "label": "Generic (any amount)",
        "value": "GENERIC"
      }
    ]
  },
  {
    "name": "amount",
    "label": "Amount",
    "type": "number",
    "required": false
  },
  {
    "name": "partialPayment",
    "label": "Partial payment allowed",
    "type": "boolean",
    "required": false
  },
  {
    "name": "bindLinkIdMobile",
    "label": "Bind link to mobile",
    "type": "boolean",
    "required": false
  },
  {
    "name": "maxPaymentsAllowed",
    "label": "Max payments allowed",
    "type": "integer",
    "required": false
  },
  {
    "name": "customerName",
    "label": "Customer name",
    "type": "text",
    "required": false
  },
  {
    "name": "customerEmail",
    "label": "Customer email",
    "type": "text",
    "required": false
  },
  {
    "name": "customerMobile",
    "label": "Customer mobile",
    "type": "text",
    "required": false
  },
  {
    "name": "expiryDate",
    "label": "Expiry date",
    "type": "date",
    "required": false
  },
  {
    "name": "sendSms",
    "label": "Send SMS",
    "type": "boolean",
    "required": false
  },
  {
    "name": "sendEmail",
    "label": "Send email",
    "type": "boolean",
    "required": false
  },
  {
    "name": "merchantRequestId",
    "label": "Merchant request ID",
    "type": "text",
    "required": false
  },
  {
    "name": "customerId",
    "label": "Customer ID",
    "type": "text",
    "required": false
  },
  {
    "name": "linkNotes",
    "label": "Link notes",
    "type": "text",
    "required": false
  },
  {
    "name": "statusCallbackUrl",
    "label": "Status callback URL",
    "type": "text",
    "required": false
  }
]
```

### Response mapping

| `output` | `{{body.data}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: createPaymentLink
 * TYPE: Action (single-item response)
 * PAYTM ENDPOINT: POST /link/create (via proxy)
 * PROXY FUNCTION: createPaymentLink
 *
 * amount is required when linkType = FIXED; optional for GENERIC.
 * expiryDate format expected by Paytm: DD/MM/YYYY
 * customerContact is a nested object — customerName/Email/Mobile go inside it.
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   data.body.linkId contains the created link ID on success.
 */
{
    "url": "{{connection.baseUrl}}/integration/createPaymentLink?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "mid": "{{connection.merchantId}}",
            "linkName": "{{parameters.linkName}}",
            "linkDescription": "{{parameters.linkDescription}}",
            "linkType": "{{parameters.linkType}}",
            "amount": "{{parameters.amount}}",
            "partialPayment": "{{parameters.partialPayment}}",
            "bindLinkIdMobile": "{{parameters.bindLinkIdMobile}}",
            "maxPaymentsAllowed": "{{parameters.maxPaymentsAllowed}}",
            "customerContact": {
                "customerName": "{{parameters.customerName}}",
                "customerEmail": "{{parameters.customerEmail}}",
                "customerMobile": "{{parameters.customerMobile}}"
            },
            "sendSms": "{{parameters.sendSms}}",
            "sendEmail": "{{parameters.sendEmail}}",
            "expiryDate": "{{formatDate(parameters.expiryDate; 'DD/MM/YYYY')}}",
            "merchantRequestId": "{{parameters.merchantRequestId}}",
            "customerId": "{{parameters.customerId}}",
            "linkNotes": "{{parameters.linkNotes}}",
            "statusCallbackUrl": "{{parameters.statusCallbackUrl}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/createPaymentLink?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "mid": "{{connection.merchantId}}",
            "linkName": "{{parameters.linkName}}",
            "linkDescription": "{{parameters.linkDescription}}",
            "linkType": "{{parameters.linkType}}",
            "amount": "{{parameters.amount}}",
            "partialPayment": "{{parameters.partialPayment}}",
            "bindLinkIdMobile": "{{parameters.bindLinkIdMobile}}",
            "maxPaymentsAllowed": "{{parameters.maxPaymentsAllowed}}",
            "customerContact": {
                "customerName": "{{parameters.customerName}}",
                "customerEmail": "{{parameters.customerEmail}}",
                "customerMobile": "{{parameters.customerMobile}}"
            },
            "sendSms": "{{parameters.sendSms}}",
            "sendEmail": "{{parameters.sendEmail}}",
            "expiryDate": "{{formatDate(parameters.expiryDate; 'DD/MM/YYYY')}}",
            "merchantRequestId": "{{parameters.merchantRequestId}}",
            "customerId": "{{parameters.customerId}}",
            "linkNotes": "{{parameters.linkNotes}}",
            "statusCallbackUrl": "{{parameters.statusCallbackUrl}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

---

## 2. `fetchPaymentLinks` (Search)

**Source:** [`app/modules/fetchPaymentLinks.jsonc`](../app/modules/fetchPaymentLinks.jsonc) · parameters: [`make-module-parameters.json`](./make-module-parameters.json) → `fetchPaymentLinks`

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default |
|---|---|---|---|
| `paymentStatus` | `select` | No | — |
| `merchantRequestId` | `text` | No | — |
| `linkId` | `text` | No | — |
| `customerName` | `text` | No | — |
| `customerEmail` | `text` | No | — |
| `customerPhone` | `text` | No | — |
| `filterFromDate` | `date` | No | — |
| `filterToDate` | `date` | No | — |
| `filterIsActive` | `boolean` | No | — |

### Mappable parameters (`JSON`, paste into Make)

`name` must match `parameters.<name>` in Communication.

```json
[
  {
    "name": "paymentStatus",
    "label": "Payment status",
    "type": "select",
    "required": false,
    "options": [
      {
        "label": "Expired",
        "value": "EXPIRED"
      },
      {
        "label": "Initiated",
        "value": "INIT"
      },
      {
        "label": "Paid",
        "value": "PAID"
      },
      {
        "label": "Pending",
        "value": "PENDING"
      }
    ]
  },
  {
    "name": "merchantRequestId",
    "label": "Merchant request ID",
    "type": "text",
    "required": false
  },
  {
    "name": "linkId",
    "label": "Link ID",
    "type": "text",
    "required": false
  },
  {
    "name": "customerName",
    "label": "Customer name",
    "type": "text",
    "required": false
  },
  {
    "name": "customerEmail",
    "label": "Customer email",
    "type": "text",
    "required": false
  },
  {
    "name": "customerPhone",
    "label": "Customer phone",
    "type": "text",
    "required": false
  },
  {
    "name": "filterFromDate",
    "label": "Filter from date",
    "type": "date",
    "required": false
  },
  {
    "name": "filterToDate",
    "label": "Filter to date",
    "type": "date",
    "required": false
  },
  {
    "name": "filterIsActive",
    "label": "Filter active links only",
    "type": "boolean",
    "required": false
  }
]
```

### Response mapping

| `output` | `{{body.data}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: fetchPaymentLinks
 * TYPE: Search (returns payment links bundle)
 * PROXY FUNCTION: fetchPaymentLinks
 * DOWNSTREAM: POST /link/fetch
 *
 * KEY NOTES (Zapier parity):
 *   - All params are optional; mid is always sent
 *   - Dates go inside searchFilterRequestBody as DD/MM/YYYY
 *   - paymentStatus choices: EXPIRED / INIT / PAID / PENDING
 *   - X-Signature = HMAC-SHA256(merchantId, connection.keySecret)
 */
{
    "url": "{{connection.baseUrl}}/integration/fetchPaymentLinks?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "mid": "{{connection.merchantId}}",
            "paymentStatus": "{{parameters.paymentStatus}}",
            "merchantRequestId": "{{parameters.merchantRequestId}}",
            "linkId": "{{parameters.linkId}}",
            "customerName": "{{parameters.customerName}}",
            "customerEmail": "{{parameters.customerEmail}}",
            "customerPhone": "{{parameters.customerPhone}}",
            "searchFilterRequestBody": {
                "fromDate": "{{formatDate(parameters.filterFromDate; 'DD/MM/YYYY')}}",
                "toDate": "{{formatDate(parameters.filterToDate; 'DD/MM/YYYY')}}",
                "isActive": "{{parameters.filterIsActive}}"
            }
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/fetchPaymentLinks?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "mid": "{{connection.merchantId}}",
            "paymentStatus": "{{parameters.paymentStatus}}",
            "merchantRequestId": "{{parameters.merchantRequestId}}",
            "linkId": "{{parameters.linkId}}",
            "customerName": "{{parameters.customerName}}",
            "customerEmail": "{{parameters.customerEmail}}",
            "customerPhone": "{{parameters.customerPhone}}",
            "searchFilterRequestBody": {
                "fromDate": "{{formatDate(parameters.filterFromDate; 'DD/MM/YYYY')}}",
                "toDate": "{{formatDate(parameters.filterToDate; 'DD/MM/YYYY')}}",
                "isActive": "{{parameters.filterIsActive}}"
            }
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

---

## 3. `fetchTransactionsForLink` (Search)

**Source:** [`app/modules/fetchTransactionsForLink.jsonc`](../app/modules/fetchTransactionsForLink.jsonc) · parameters: [`make-module-parameters.json`](./make-module-parameters.json) → `fetchTransactionsForLink`

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default |
|---|---|---|---|
| `linkId` | `text` | Yes | — |
| `searchStartDate` | `date` | No | — |
| `searchEndDate` | `date` | No | — |
| `fetchAllTxns` | `boolean` | No | — |
| `limit` | `integer` | No | 20 |

### Mappable parameters (`JSON`, paste into Make)

`name` must match `parameters.<name>` in Communication.

```json
[
  {
    "name": "linkId",
    "label": "Link ID",
    "type": "text",
    "required": true
  },
  {
    "name": "searchStartDate",
    "label": "Search start date",
    "type": "date",
    "required": false
  },
  {
    "name": "searchEndDate",
    "label": "Search end date",
    "type": "date",
    "required": false
  },
  {
    "name": "fetchAllTxns",
    "label": "Fetch all transactions",
    "type": "boolean",
    "required": false
  },
  {
    "name": "limit",
    "label": "Page size",
    "type": "integer",
    "required": false,
    "default": 20
  }
]
```

### Response mapping (Search)

| Field | Expression |
|-------|------------|
| `iterate` | `{{body.data.txnDetailsList}}` |
| `output` | `{{item}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: fetchTransactionsForLink
 * TYPE: Search (returns a list of transactions for a payment link)
 * PAYTM ENDPOINT: POST /link/fetchTransaction (via proxy)
 * PROXY FUNCTION: fetchTransactionsForLink
 *
 * linkId is required. Date range and fetchAllTxns are optional filters.
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Verify body.data.txnDetailsList iterate path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/integration/fetchTransactionsForLink?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "linkId": "{{parameters.linkId}}",
            "searchStartDate": "{{formatDate(parameters.searchStartDate; 'YYYY-MM-DD')}}",
            "searchEndDate": "{{formatDate(parameters.searchEndDate; 'YYYY-MM-DD')}}",
            "fetchAllTxns": "{{parameters.fetchAllTxns}}",
            "pageSize": "{{ifempty(parameters.limit; 20)}}"
        }
    },
    "response": {
        // Verify body.data.txnDetailsList is the correct iterate path during E2E testing.
        "iterate": "{{body.data.txnDetailsList}}",
        "output": "{{item}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/fetchTransactionsForLink?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "linkId": "{{parameters.linkId}}",
            "searchStartDate": "{{formatDate(parameters.searchStartDate; 'YYYY-MM-DD')}}",
            "searchEndDate": "{{formatDate(parameters.searchEndDate; 'YYYY-MM-DD')}}",
            "fetchAllTxns": "{{parameters.fetchAllTxns}}",
            "pageSize": "{{ifempty(parameters.limit; 20)}}"
        }
    },
    "response": {
        "iterate": "{{body.data.txnDetailsList}}",
        "output": "{{item}}"
    }
}
```

---

## 4. `fetchOrderList` (Search)

**Source:** [`app/modules/fetchOrderList.jsonc`](../app/modules/fetchOrderList.jsonc) · parameters: [`make-module-parameters.json`](./make-module-parameters.json) → `fetchOrderList`

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default |
|---|---|---|---|
| `startDate` | `date` | Yes | — |
| `endDate` | `date` | Yes | — |
| `orderSearchStatus` | `select` | No | SUCCESS |
| `orderSearchType` | `select` | No | ALL |
| `pageNumber` | `integer` | No | 1 |
| `limit` | `integer` | No | 20 |

### Mappable parameters (`JSON`, paste into Make)

`name` must match `parameters.<name>` in Communication.

```json
[
  {
    "name": "startDate",
    "label": "Start date",
    "type": "date",
    "required": true
  },
  {
    "name": "endDate",
    "label": "End date",
    "type": "date",
    "required": true
  },
  {
    "name": "orderSearchStatus",
    "label": "Order search status",
    "type": "select",
    "required": false,
    "default": "SUCCESS",
    "options": [
      {
        "label": "All (maps to SUCCESS|FAILURE|PENDING)",
        "value": "ALL"
      },
      {
        "label": "Success",
        "value": "SUCCESS"
      },
      {
        "label": "Failure",
        "value": "FAILURE"
      },
      {
        "label": "Pending",
        "value": "PENDING"
      }
    ]
  },
  {
    "name": "orderSearchType",
    "label": "Order search type",
    "type": "select",
    "required": false,
    "default": "ALL",
    "options": [
      {
        "label": "All",
        "value": "ALL"
      },
      {
        "label": "Transaction",
        "value": "TRANSACTION"
      }
    ]
  },
  {
    "name": "pageNumber",
    "label": "Page number",
    "type": "integer",
    "required": false,
    "default": 1
  },
  {
    "name": "limit",
    "label": "Page size",
    "type": "integer",
    "required": false,
    "default": 20
  }
]
```

### Response mapping

| `output` | `{{body.data}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: fetchOrderList
 * TYPE: Search (returns order list bundle)
 * PROXY FUNCTION: fetchOrderList
 * DOWNSTREAM: POST /merchant-passbook/search/list/order/v2
 *
 * KEY NOTES (from Zapier parity):
 *   - orderSearchStatus "ALL" is INVALID at Paytm; map to "SUCCESS|FAILURE|PENDING"
 *   - Dates must be IST datetime: "YYYY-MM-DDTHH:mm:ss+05:30"
 *   - isSort must be boolean true
 *   - X-Signature = HMAC-SHA256(merchantId, connection.keySecret)
 */
{
    "url": "{{connection.baseUrl}}/integration/fetchOrderList?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "mid": "{{connection.merchantId}}",
            "fromDate": "{{formatDate(parameters.startDate; 'YYYY-MM-DD')}}T00:00:00+05:30",
            "toDate": "{{formatDate(parameters.endDate; 'YYYY-MM-DD')}}T23:59:59+05:30",
            "orderSearchStatus": "{{if(parameters.orderSearchStatus == 'ALL'; 'SUCCESS|FAILURE|PENDING'; ifempty(parameters.orderSearchStatus; 'SUCCESS'))}}",
            "orderSearchType": "{{ifempty(parameters.orderSearchType; 'ALL')}}",
            "pageNumber": "{{ifempty(parameters.pageNumber; 1)}}",
            "pageSize": "{{ifempty(parameters.limit; 20)}}",
            "isSort": true
        }
    },
    "response": {
        // Returns full response as one bundle: { resultInfo, orderList[], totalCount }
        "output": "{{body.data}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/fetchOrderList?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "mid": "{{connection.merchantId}}",
            "fromDate": "{{formatDate(parameters.startDate; 'YYYY-MM-DD')}}T00:00:00+05:30",
            "toDate": "{{formatDate(parameters.endDate; 'YYYY-MM-DD')}}T23:59:59+05:30",
            "orderSearchStatus": "{{if(parameters.orderSearchStatus == 'ALL'; 'SUCCESS|FAILURE|PENDING'; ifempty(parameters.orderSearchStatus; 'SUCCESS'))}}",
            "orderSearchType": "{{ifempty(parameters.orderSearchType; 'ALL')}}",
            "pageNumber": "{{ifempty(parameters.pageNumber; 1)}}",
            "pageSize": "{{ifempty(parameters.limit; 20)}}",
            "isSort": true
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

---

## 5. `orderDetail` (Action (RTDD / settlement via proxy))

**Source:** [`app/modules/orderDetail.jsonc`](../app/modules/orderDetail.jsonc) · parameters: [`make-module-parameters.json`](./make-module-parameters.json) → `orderDetail`

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default |
|---|---|---|---|
| `bizOrderId` | `text` | Yes | — |
| `isSettlementInfo` | `boolean` | No | `false` |
| `excludePaymentsData` | `boolean` | No | `false` |

### Mappable parameters (`JSON`, paste into Make)

`name` must match `parameters.<name>` in Communication.

```json
[
  {
    "name": "bizOrderId",
    "label": "Business order ID",
    "type": "text",
    "required": true
  },
  {
    "name": "isSettlementInfo",
    "label": "Include settlement info",
    "type": "boolean",
    "required": false,
    "default": false
  },
  {
    "name": "excludePaymentsData",
    "label": "Exclude payments data",
    "type": "boolean",
    "required": false,
    "default": false
  }
]
```

### Response mapping

| `output` | `{{body.data}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: orderDetail
 * TYPE: Action (single-item response)
 * PAYTM ENDPOINT: RTDD via proxy
 * PROXY FUNCTION: orderDetail
 *
 * RTDD/Settlement envelope — proxy builds the signed downstream body.
 * No checksum logic in IML.
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Verify body.data path against actual Paytm response during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/integration/orderDetail?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "bizOrderId": "{{parameters.bizOrderId}}",
            "isSettlementInfo": "{{ifempty(parameters.isSettlementInfo; false)}}",
            "excludePaymentsData": "{{ifempty(parameters.excludePaymentsData; false)}}"
        }
    },
    "response": {
        // Verify body.data is the correct output path during E2E testing.
        "output": "{{body.data}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/orderDetail?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "bizOrderId": "{{parameters.bizOrderId}}",
            "isSettlementInfo": "{{ifempty(parameters.isSettlementInfo; false)}}",
            "excludePaymentsData": "{{ifempty(parameters.excludePaymentsData; false)}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

---

## 6. `initiateRefund` (Action)

**Source:** [`app/modules/initiateRefund.jsonc`](../app/modules/initiateRefund.jsonc) · parameters: [`make-module-parameters.json`](./make-module-parameters.json) → `initiateRefund`

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default |
|---|---|---|---|
| `orderId` | `text` | Yes | — |
| `txnId` | `text` | Yes | — |
| `refId` | `text` | Yes | — |
| `refundAmount` | `number` | Yes | — |
| `comments` | `text` | No | — |

### Mappable parameters (`JSON`, paste into Make)

`name` must match `parameters.<name>` in Communication.

```json
[
  {
    "name": "orderId",
    "label": "Order ID",
    "type": "text",
    "required": true
  },
  {
    "name": "txnId",
    "label": "Transaction ID",
    "type": "text",
    "required": true
  },
  {
    "name": "refId",
    "label": "Refund reference ID",
    "type": "text",
    "required": true
  },
  {
    "name": "refundAmount",
    "label": "Refund amount",
    "type": "number",
    "required": true
  },
  {
    "name": "comments",
    "label": "Comments",
    "type": "text",
    "required": false
  }
]
```

### Response mapping

| `output` | `{{body.data}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: initiateRefund
 * TYPE: Action (single-item response)
 * PAYTM ENDPOINT: POST /refund/apply (via proxy)
 * PROXY FUNCTION: initiateRefund
 *
 * All four IDs (orderId, txnId, refId, refundAmount) are required.
 * refId must be unique per refund request (idempotency key).
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Verify body.data path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/integration/initiateRefund?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "orderId": "{{parameters.orderId}}",
            "txnId": "{{parameters.txnId}}",
            "refId": "{{parameters.refId}}",
            "refundAmount": "{{parameters.refundAmount}}",
            "comments": "{{parameters.comments}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/initiateRefund?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "orderId": "{{parameters.orderId}}",
            "txnId": "{{parameters.txnId}}",
            "refId": "{{parameters.refId}}",
            "refundAmount": "{{parameters.refundAmount}}",
            "comments": "{{parameters.comments}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

---

## 7. `checkRefundStatus` (Action)

**Source:** [`app/modules/checkRefundStatus.jsonc`](../app/modules/checkRefundStatus.jsonc) · parameters: [`make-module-parameters.json`](./make-module-parameters.json) → `checkRefundStatus`

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default |
|---|---|---|---|
| `orderId` | `text` | Yes | — |
| `refId` | `text` | Yes | — |

### Mappable parameters (`JSON`, paste into Make)

`name` must match `parameters.<name>` in Communication.

```json
[
  {
    "name": "orderId",
    "label": "Order ID",
    "type": "text",
    "required": true
  },
  {
    "name": "refId",
    "label": "Refund reference ID",
    "type": "text",
    "required": true
  }
]
```

### Response mapping

| `output` | `{{body.data}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: checkRefundStatus
 * TYPE: Action (single-item response)
 * PAYTM ENDPOINT: POST /v2/refund/status (via proxy)
 * PROXY FUNCTION: checkRefundStatus
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Verify body.data path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/integration/checkRefundStatus?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "orderId": "{{parameters.orderId}}",
            "refId": "{{parameters.refId}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/checkRefundStatus?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "orderId": "{{parameters.orderId}}",
            "refId": "{{parameters.refId}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

---

## 8. `fetchRefundList` (Search)

**Source:** [`app/modules/fetchRefundList.jsonc`](../app/modules/fetchRefundList.jsonc) · parameters: [`make-module-parameters.json`](./make-module-parameters.json) → `fetchRefundList`

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default |
|---|---|---|---|
| `startDate` | `date` | Yes | — |
| `endDate` | `date` | Yes | — |
| `pageNum` | `integer` | No | 1 |
| `limit` | `integer` | No | 20 |
| `isSort` | `boolean` | No | `true` |

### Mappable parameters (`JSON`, paste into Make)

`name` must match `parameters.<name>` in Communication.

```json
[
  {
    "name": "startDate",
    "label": "Start date",
    "type": "date",
    "required": true
  },
  {
    "name": "endDate",
    "label": "End date",
    "type": "date",
    "required": true
  },
  {
    "name": "pageNum",
    "label": "Page number",
    "type": "integer",
    "required": false,
    "default": 1
  },
  {
    "name": "limit",
    "label": "Page size",
    "type": "integer",
    "required": false,
    "default": 20
  },
  {
    "name": "isSort",
    "label": "Sort results",
    "type": "boolean",
    "required": false,
    "default": true
  }
]
```

### Response mapping (Search)

| Field | Expression |
|-------|------------|
| `iterate` | `{{body.data.refundDetailList}}` |
| `output` | `{{item}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: fetchRefundList
 * TYPE: Search (returns a list of refunds)
 * PAYTM ENDPOINT: POST /merchant-passbook/api/v1/refundList (via proxy)
 * PROXY FUNCTION: fetchRefundList
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Verify body.data.refundDetailList iterate path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/integration/fetchRefundList?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "startDate": "{{formatDate(parameters.startDate; 'YYYY-MM-DD')}}",
            "endDate": "{{formatDate(parameters.endDate; 'YYYY-MM-DD')}}",
            "pageNum": "{{ifempty(parameters.pageNum; 1)}}",
            "pageSize": "{{ifempty(parameters.limit; 20)}}",
            "isSort": "{{ifempty(parameters.isSort; true)}}"
        }
    },
    "response": {
        // Verify body.data.refundDetailList is the correct iterate path during E2E testing.
        "iterate": "{{body.data.refundDetailList}}",
        "output": "{{item}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/fetchRefundList?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "startDate": "{{formatDate(parameters.startDate; 'YYYY-MM-DD')}}",
            "endDate": "{{formatDate(parameters.endDate; 'YYYY-MM-DD')}}",
            "pageNum": "{{ifempty(parameters.pageNum; 1)}}",
            "pageSize": "{{ifempty(parameters.limit; 20)}}",
            "isSort": "{{ifempty(parameters.isSort; true)}}"
        }
    },
    "response": {
        "iterate": "{{body.data.refundDetailList}}",
        "output": "{{item}}"
    }
}
```

---

## 9. `settlementBillList` (Search (RTDD))

**Source:** [`app/modules/settlementBillList.jsonc`](../app/modules/settlementBillList.jsonc) · parameters: [`make-module-parameters.json`](./make-module-parameters.json) → `settlementBillList`

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default |
|---|---|---|---|
| `settlementStartTime` | `date` | Yes | — |
| `settlementEndTime` | `date` | Yes | — |
| `pageNum` | `integer` | No | 1 |
| `limit` | `integer` | No | 20 |
| `settlementBillId` | `text` | No | — |
| `settleStatus` | `select` | No | — |
| `utrNo` | `text` | No | — |

### Mappable parameters (`JSON`, paste into Make)

`name` must match `parameters.<name>` in Communication.

```json
[
  {
    "name": "settlementStartTime",
    "label": "Settlement start time",
    "type": "date",
    "required": true
  },
  {
    "name": "settlementEndTime",
    "label": "Settlement end time",
    "type": "date",
    "required": true
  },
  {
    "name": "pageNum",
    "label": "Page number",
    "type": "integer",
    "required": false,
    "default": 1
  },
  {
    "name": "limit",
    "label": "Page size (max 50)",
    "type": "integer",
    "required": false,
    "default": 20
  },
  {
    "name": "settlementBillId",
    "label": "Settlement bill ID",
    "type": "text",
    "required": false
  },
  {
    "name": "settleStatus",
    "label": "Settlement status",
    "type": "select",
    "required": false,
    "options": [
      {
        "label": "Bank initiated",
        "value": "BANK_INITIATED"
      },
      {
        "label": "Payout settled",
        "value": "PAYOUT_SETTLED"
      },
      {
        "label": "Payout unsettled",
        "value": "PAYOUT_UNSETTLED"
      },
      {
        "label": "Wait for settle",
        "value": "WAIT_FOR_SETTLE"
      }
    ]
  },
  {
    "name": "utrNo",
    "label": "UTR number",
    "type": "text",
    "required": false
  }
]
```

### Response mapping (Search)

| Field | Expression |
|-------|------------|
| `iterate` | `{{body.data.body.settleBillList}}` |
| `output` | `{{item}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: settlementBillList
 * TYPE: Search (returns a list of settlement bills / payouts)
 * PAYTM ENDPOINT: RTDD via proxy
 * PROXY FUNCTION: settlementBillList
 *
 * RTDD/Settlement envelope — proxy builds the signed downstream body.
 * No checksum logic in IML.
 *
 * NOTE ON PARAMS
 *   settlementStartTime / settlementEndTime — NOT startDate / endDate.
 *   pageSize max is 50.
 *   settleStatus valid values: BANK_INITIATED / PAYOUT_SETTLED / PAYOUT_UNSETTLED / WAIT_FOR_SETTLE
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Verify body.data.body.settleBillList iterate path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/integration/settlementBillList?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "settlementStartTime": "{{formatDate(parameters.settlementStartTime; 'YYYY-MM-DD HH:mm:ss')}}",
            "settlementEndTime": "{{formatDate(parameters.settlementEndTime; 'YYYY-MM-DD HH:mm:ss')}}",
            "pageNum": "{{ifempty(parameters.pageNum; 1)}}",
            "pageSize": "{{ifempty(parameters.limit; 20)}}",
            "settlementBillId": "{{parameters.settlementBillId}}",
            "settleStatus": "{{parameters.settleStatus}}",
            "utrNo": "{{parameters.utrNo}}"
        }
    },
    "response": {
        // Verify body.data.body.settleBillList is the correct iterate path during E2E testing.
        "iterate": "{{body.data.body.settleBillList}}",
        "output": "{{item}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/settlementBillList?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "settlementStartTime": "{{formatDate(parameters.settlementStartTime; 'YYYY-MM-DD HH:mm:ss')}}",
            "settlementEndTime": "{{formatDate(parameters.settlementEndTime; 'YYYY-MM-DD HH:mm:ss')}}",
            "pageNum": "{{ifempty(parameters.pageNum; 1)}}",
            "pageSize": "{{ifempty(parameters.limit; 20)}}",
            "settlementBillId": "{{parameters.settlementBillId}}",
            "settleStatus": "{{parameters.settleStatus}}",
            "utrNo": "{{parameters.utrNo}}"
        }
    },
    "response": {
        "iterate": "{{body.data.body.settleBillList}}",
        "output": "{{item}}"
    }
}
```

---

## 10. `settlementTxnListByDate` (Search (RTDD))

**Source:** [`app/modules/settlementTxnListByDate.jsonc`](../app/modules/settlementTxnListByDate.jsonc) · parameters: [`make-module-parameters.json`](./make-module-parameters.json) → `settlementTxnListByDate`

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default |
|---|---|---|---|
| `startDate` | `date` | Yes | — |
| `endDate` | `date` | Yes | — |
| `pageNum` | `integer` | No | 1 |
| `limit` | `integer` | No | 20 |
| `settlementOrderId` | `text` | No | — |

### Mappable parameters (`JSON`, paste into Make)

`name` must match `parameters.<name>` in Communication.

```json
[
  {
    "name": "startDate",
    "label": "Start date/time",
    "type": "date",
    "required": true
  },
  {
    "name": "endDate",
    "label": "End date/time",
    "type": "date",
    "required": true
  },
  {
    "name": "pageNum",
    "label": "Page number",
    "type": "integer",
    "required": false,
    "default": 1
  },
  {
    "name": "limit",
    "label": "Page size",
    "type": "integer",
    "required": false,
    "default": 20
  },
  {
    "name": "settlementOrderId",
    "label": "Settlement order ID",
    "type": "text",
    "required": false
  }
]
```

### Response mapping (Search)

| Field | Expression |
|-------|------------|
| `iterate` | `{{body.data.body.txnList}}` |
| `output` | `{{item}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: settlementTxnListByDate
 * TYPE: Search (returns a list of settled transactions)
 * PAYTM ENDPOINT: RTDD via proxy
 * PROXY FUNCTION: settlementTxnListByDate
 *
 * RTDD/Settlement envelope — proxy builds the signed downstream body.
 * No checksum logic in IML.
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Verify body.data.body.txnList iterate path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/integration/settlementTxnListByDate?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "startDate": "{{formatDate(parameters.startDate; 'YYYY-MM-DD HH:mm:ss')}}",
            "endDate": "{{formatDate(parameters.endDate; 'YYYY-MM-DD HH:mm:ss')}}",
            "pageNum": "{{ifempty(parameters.pageNum; 1)}}",
            "pageSize": "{{ifempty(parameters.limit; 20)}}",
            "settlementOrderId": "{{parameters.settlementOrderId}}"
        }
    },
    "response": {
        // Verify body.data.body.txnList is the correct iterate path during E2E testing.
        "iterate": "{{body.data.body.txnList}}",
        "output": "{{item}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/settlementTxnListByDate?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "startDate": "{{formatDate(parameters.startDate; 'YYYY-MM-DD HH:mm:ss')}}",
            "endDate": "{{formatDate(parameters.endDate; 'YYYY-MM-DD HH:mm:ss')}}",
            "pageNum": "{{ifempty(parameters.pageNum; 1)}}",
            "pageSize": "{{ifempty(parameters.limit; 20)}}",
            "settlementOrderId": "{{parameters.settlementOrderId}}"
        }
    },
    "response": {
        "iterate": "{{body.data.body.txnList}}",
        "output": "{{item}}"
    }
}
```

---

## 11. `fetchSubscriptionStatus` (Action)

**Source:** [`app/modules/fetchSubscriptionStatus.jsonc`](../app/modules/fetchSubscriptionStatus.jsonc) · parameters: [`make-module-parameters.json`](./make-module-parameters.json) → `fetchSubscriptionStatus`

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default |
|---|---|---|---|
| `subsId` | `text` | No | — |
| `orderId` | `text` | No | — |
| `linkId` | `text` | No | — |
| `custId` | `text` | No | — |

### Mappable parameters (`JSON`, paste into Make)

`name` must match `parameters.<name>` in Communication.

```json
[
  {
    "name": "subsId",
    "label": "Subscription ID",
    "type": "text",
    "required": false
  },
  {
    "name": "orderId",
    "label": "Order ID",
    "type": "text",
    "required": false
  },
  {
    "name": "linkId",
    "label": "Link ID",
    "type": "text",
    "required": false
  },
  {
    "name": "custId",
    "label": "Customer ID",
    "type": "text",
    "required": false
  }
]
```

### Response mapping

| `output` | `{{body.data}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: fetchSubscriptionStatus
 * TYPE: Action (single-item response)
 * PAYTM ENDPOINT: POST /subscription/subscription/checkStatus (via proxy)
 * PROXY FUNCTION: fetchSubscriptionStatus
 *
 * At least one of subsId / orderId / linkId / custId should be provided.
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Verify body.data path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/integration/fetchSubscriptionStatus?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "subsId": "{{parameters.subsId}}",
            "orderId": "{{parameters.orderId}}",
            "linkId": "{{parameters.linkId}}",
            "custId": "{{parameters.custId}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/fetchSubscriptionStatus?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "subsId": "{{parameters.subsId}}",
            "orderId": "{{parameters.orderId}}",
            "linkId": "{{parameters.linkId}}",
            "custId": "{{parameters.custId}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

---

## 12. `pauseResumeSubscription` (Action)

**Source:** [`app/modules/pauseResumeSubscription.jsonc`](../app/modules/pauseResumeSubscription.jsonc) · parameters: [`make-module-parameters.json`](./make-module-parameters.json) → `pauseResumeSubscription`

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default |
|---|---|---|---|
| `subsId` | `text` | Yes | — |
| `status` | `select` | Yes | — |

### Mappable parameters (`JSON`, paste into Make)

`name` must match `parameters.<name>` in Communication.

```json
[
  {
    "name": "subsId",
    "label": "Subscription ID",
    "type": "text",
    "required": true
  },
  {
    "name": "status",
    "label": "Status",
    "type": "select",
    "required": true,
    "options": [
      {
        "label": "Suspended (pause)",
        "value": "SUSPENDED"
      },
      {
        "label": "Active (resume)",
        "value": "ACTIVE"
      }
    ]
  }
]
```

### Response mapping

| `output` | `{{body.data}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: pauseResumeSubscription
 * TYPE: Action (single-item response)
 * PAYTM ENDPOINT: POST /subscription/subscription/status/modify (via proxy)
 * PROXY FUNCTION: pauseResumeSubscription
 *
 * status: SUSPENDED (pause) / ACTIVE (resume)
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Verify body.data path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/integration/pauseResumeSubscription?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "subsId": "{{parameters.subsId}}",
            "status": "{{parameters.status}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/pauseResumeSubscription?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "subsId": "{{parameters.subsId}}",
            "status": "{{parameters.status}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

---

## 13. `cancelSubscription` (Action)

**Source:** [`app/modules/cancelSubscription.jsonc`](../app/modules/cancelSubscription.jsonc) · parameters: [`make-module-parameters.json`](./make-module-parameters.json) → `cancelSubscription`

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default |
|---|---|---|---|
| `subsId` | `text` | Yes | — |

### Mappable parameters (`JSON`, paste into Make)

`name` must match `parameters.<name>` in Communication.

```json
[
  {
    "name": "subsId",
    "label": "Subscription ID",
    "type": "text",
    "required": true
  }
]
```

### Response mapping

| `output` | `{{body.data}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: cancelSubscription
 * TYPE: Action (single-item response)
 * PAYTM ENDPOINT: POST /subscription/subscription/cancel (via proxy)
 * PROXY FUNCTION: cancelSubscription
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Verify body.data path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/integration/cancelSubscription?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "subsId": "{{parameters.subsId}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/cancelSubscription?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "subsId": "{{parameters.subsId}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

---

## 14. `makeApiCall` (Universal)

**Source:** [`app/modules/makeApiCall.jsonc`](../app/modules/makeApiCall.jsonc) · parameters: [`make-module-parameters.json`](./make-module-parameters.json) → `makeApiCall`

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default |
|---|---|---|---|
| `method` | `select` | Yes | — |
| `url` | `text` | Yes | — |
| `headers` | `collection` | No | — |
| `body` | `text` | No | — |

### Mappable parameters (`JSON`, paste into Make)

`name` must match `parameters.<name>` in Communication.

```json
[
  {
    "name": "method",
    "label": "HTTP method",
    "type": "select",
    "required": true,
    "options": [
      {
        "label": "GET",
        "value": "GET"
      },
      {
        "label": "POST",
        "value": "POST"
      },
      {
        "label": "PUT",
        "value": "PUT"
      },
      {
        "label": "PATCH",
        "value": "PATCH"
      },
      {
        "label": "DELETE",
        "value": "DELETE"
      }
    ]
  },
  {
    "name": "url",
    "label": "Relative URL path (e.g. /link/fetch)",
    "type": "text",
    "required": true
  },
  {
    "name": "headers",
    "label": "Additional headers",
    "type": "collection",
    "required": false
  },
  {
    "name": "body",
    "label": "Request body (JSON)",
    "type": "text",
    "required": false
  }
]
```

### Response mapping

| `output` | `{{body.data}}` |

### Module Communication — reference (`jsonc`)

```jsonc
/**
 * MODULE: makeApiCall
 * TYPE: Universal (required by Make platform — one per app)
 * PURPOSE: Custom Paytm API call for endpoints not covered by other modules.
 *
 * IMPORTANT — RELATIVE PATHS ONLY
 *   The `url` parameter must be a relative path, e.g. /link/fetch
 *   The proxy prepends the Paytm base URL server-side.
 *   Make will reject absolute URLs (https://...) in Universal modules.
 *
 * PROXY FUNCTION: makeApiCall
 *   The proxy forwards params.url + params.method + params.body to the
 *   corresponding Paytm endpoint, applying the correct AES checksum.
 */
{
    "url": "{{connection.baseUrl}}/integration/makeApiCall?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "method": "{{parameters.method}}",
            "url": "{{parameters.url}}",
            "headers": "{{parameters.headers}}",
            "body": "{{parameters.body}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

### Module Communication (`JSON`, paste)

```json
{
    "url": "{{connection.baseUrl}}/integration/makeApiCall?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "X-Signature": "{{sha256(connection.merchantId; 'hex'; connection.keySecret; 'utf8')}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'X')}}000",
        "timestamp": "{{formatDate(now; 'X')}}000",
        "params": {
            "method": "{{parameters.method}}",
            "url": "{{parameters.url}}",
            "headers": "{{parameters.headers}}",
            "body": "{{parameters.body}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

---

## Related

- [`make-module-parameters.json`](./make-module-parameters.json) — editable parameter definitions for this doc
- [`make-connection-paytm.md`](./make-connection-paytm.md)
- [`api-mapping.md`](./api-mapping.md)
- [`checksum-algorithm.md`](./checksum-algorithm.md)
- [`e2e-integration-testing.md`](./e2e-integration-testing.md)
