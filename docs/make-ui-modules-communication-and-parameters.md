# Make UI — modules: communication and parameters

Use when wiring modules in **Apps Editor**: define **mappable parameters** first, then **Communication**. Each module includes a **reference table**, **paste-ready parameter `json`**, **Communication `jsonc`** aligned with [`app/modules/*.jsonc`](../app/modules/), and **Communication `json`** with `//` lines removed.

**Canonical long-form tables:** [`api-mapping.md`](./api-mapping.md) § *Parameter Mapping*.

**Typical paste order**

1. Parameter definitions — **`json`** array (`name`, `label`, `type`, `required`, `options`, `default` where needed).
2. Communication — **`json`** block below. Use **`jsonc`** when your editor accepts it (exact repo copy).

**IML**

- **`X-Signature` (modules):** `{{sha256(createJSON(body); connection.keySecret)}}`
- **`timestamp`:** `{{formatDate(now; 'x')}}`
- **`requestId`:** `{{formatDate(now; 'x')}}` — use the same epoch-ms pattern as `timestamp`; `uuid()` is not available in this Make IML runtime.

**Naming:** modules use **`connection.*`**; connection **save validation** uses **`parameters.*`** (see [make-connection-paytm.md](./make-connection-paytm.md)).

---

## Table of contents

1. [Connection](#connection-parameters-not-modules) — `merchantId`, `keySecret`, `baseUrl`
2. [`createPaymentLink`](#1-createpaymentlink-action)
3. [`fetchPaymentLinks`](#2-fetchpaymentlinks-search)
4. [`fetchTransactionsForLink`](#3-fetchtransactionsforlink-search)
5. [`fetchOrderList`](#4-fetchorderlist-search)
6. [`orderDetail`](#5-orderdetail-action-rtdd--settlement-via-proxy)
7. [`initiateRefund`](#6-initiaterefund-action)
8. [`checkRefundStatus`](#7-checkrefundstatus-action)
9. [`fetchRefundList`](#8-fetchrefundlist-search)
10. [`settlementBillList`](#9-settlementbilllist-search-rtdd)
11. [`settlementTxnListByDate`](#10-settlementtxnlistbydate-search-rtdd)
12. [`fetchSubscriptionStatus`](#11-fetchsubscriptionstatus-action)
13. [`pauseResumeSubscription`](#12-pauseresumesubscription-action)
14. [`cancelSubscription`](#13-cancelsubscription-action)
15. [`makeApiCall`](#14-makeapicall-universal)

---

## Connection parameters (not modules)

Stored on the **Connection**, not modules. Repo file: [`app/connections/paytm.jsonc`](../app/connections/paytm.jsonc).

| Parameter `name` | Make `type` | Required |
|---|---|---|
| `merchantId` | `text` | Yes |
| `keySecret` | `password` | Yes |
| `baseUrl` | `select` | Yes |

### Connection — parameters (`JSON`, paste)

```json
[
  {
    "name": "merchantId",
    "label": "Merchant ID (MID)",
    "type": "text",
    "required": true
  },
  {
    "name": "keySecret",
    "label": "Key Secret",
    "type": "password",
    "required": true
  },
  {
    "name": "baseUrl",
    "label": "Environment",
    "type": "select",
    "required": true,
    "options": [
      {
        "label": "Production",
        "value": "https://paytm-make-proxy.paytmpayments.com"
      },
      {
        "label": "Staging",
        "value": "https://paytm-make-proxy-staging.paytmpayments.com"
      }
    ]
  }
]
```

### Connection — Communication reference (`paytm.jsonc`)

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
 *                 Production : https://paytm-make-proxy.paytmpayments.com
 *                 Staging    : https://paytm-make-proxy-staging.paytmpayments.com
 *
 * HOW AUTHENTICATION WORKS
 *   Every module request includes:
 *     X-Signature: HMAC-SHA256(createJSON(body), keySecret)
 *   The proxy verifies this before forwarding to Paytm.
 *   keySecret never travels to Paytm — only the HMAC of the body does.
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
 *         - label: Production  | value: https://paytm-make-proxy.paytmpayments.com
 *         - label: Staging     | value: https://paytm-make-proxy-staging.paytmpayments.com
 */
{
    // Validation call — send a minimal signed request to the proxy.
    // Any HTTP 200 (even a downstream FAILED from Paytm) means the HMAC was
    // accepted and the credentials are valid at the proxy level.
    "url": "{{parameters.baseUrl}}/make/fetchPaymentLinks?mid={{parameters.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); parameters.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
        "params": {}
    },
    "response": {
        // HTTP 200 from proxy = HMAC accepted = credentials valid.
        // HTTP 401 = wrong keySecret. HTTP 404 = proxy not enabled.
        "valid": "{{statusCode == 200}}"
    }
}
```

### Connection — Communication (`JSON`, paste into Make)

If the Apps Editor rejects `//`, use this cleaned copy from the same file.

```json
{
    "url": "{{parameters.baseUrl}}/make/fetchPaymentLinks?mid={{parameters.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); parameters.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
        "params": {}
    },
    "response": {
        "valid": "{{statusCode == 200}}"
    }
}
```

---

## 1. `createPaymentLink` (Action)

**Source:** [`app/modules/createPaymentLink.jsonc`](../app/modules/createPaymentLink.jsonc)

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default | Notes |
| ---------------- | ----------- | -------- | ------- | ----- |
| `linkName` | `text` | Yes | — | — |
| `linkDescription` | `text` | Yes | — | — |
| `linkType` | `select` | Yes | — | `FIXED` / `GENERIC` |
| `amount` | `number` | No¹ | — | ¹ Required when `linkType` = `FIXED` |
| `customerName` | `text` | No | — | — |
| `customerEmail` | `text` | No | — | — |
| `customerMobile` | `text` | No | — | — |
| `expiryDate` | `date` | No | — | Serialized as `YYYY-MM-DD HH:mm:ss` |
| `sendSms` | `boolean` | No | — | — |
| `sendEmail` | `boolean` | No | — | — |

### Mappable parameters (`JSON`, paste)

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
  }
]
```

### Module Communication — reference (`jsonc`, matches `createPaymentLink.jsonc`)

```jsonc
/**
 * MODULE: createPaymentLink
 * TYPE: Action (single-item response)
 * PAYTM ENDPOINT: POST /link/create (via proxy)
 * PROXY FUNCTION: createPaymentLink
 *
 * amount is required when linkType = FIXED; optional for GENERIC.
 * expiryDate format: YYYY-MM-DD HH:mm:ss
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Verify body.data path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/make/createPaymentLink?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
        "params": {
            "linkName": "{{parameters.linkName}}",
            "linkDescription": "{{parameters.linkDescription}}",
            "linkType": "{{parameters.linkType}}",
            "amount": "{{parameters.amount}}",
            "customerName": "{{parameters.customerName}}",
            "customerEmail": "{{parameters.customerEmail}}",
            "customerMobile": "{{parameters.customerMobile}}",
            "expiryDate": "{{formatDate(parameters.expiryDate; 'YYYY-MM-DD HH:mm:ss')}}",
            "sendSms": "{{parameters.sendSms}}",
            "sendEmail": "{{parameters.sendEmail}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

### Module Communication (`JSON`, paste into Make)

```json
{ status, function, requestId, data: <paytm_response> }
 *   Verify body.data path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/make/createPaymentLink?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
        "params": {
            "linkName": "{{parameters.linkName}}",
            "linkDescription": "{{parameters.linkDescription}}",
            "linkType": "{{parameters.linkType}}",
            "amount": "{{parameters.amount}}",
            "customerName": "{{parameters.customerName}}",
            "customerEmail": "{{parameters.customerEmail}}",
            "customerMobile": "{{parameters.customerMobile}}",
            "expiryDate": "{{formatDate(parameters.expiryDate; 'YYYY-MM-DD HH:mm:ss')}}",
            "sendSms": "{{parameters.sendSms}}",
            "sendEmail": "{{parameters.sendEmail}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

---

## 2. `fetchPaymentLinks` (Search)

**Source:** [`app/modules/fetchPaymentLinks.jsonc`](../app/modules/fetchPaymentLinks.jsonc)

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default | Notes |
| ---------------- | ----------- | -------- | ------- | ----- |
| `fromDate` | `date` | No | — | — |
| `toDate` | `date` | No | — | — |
| `linkId` | `text` | No | — | — |
| `merchantRequestId` | `text` | No | — | — |
| `linkType` | `select` | No | — | `FIXED` / `GENERIC` |
| `paymentStatus` | `select` | No | — | `CREATED` / `PENDING` / `SUCCESS` / `FAILED` / `EXPIRED` |
| `isActive` | `boolean` | No | — | — |

### Mappable parameters (`JSON`, paste)

`name` must match `parameters.<name>` in Communication.

```json
[
  {
    "name": "fromDate",
    "label": "From date",
    "type": "date",
    "required": false
  },
  {
    "name": "toDate",
    "label": "To date",
    "type": "date",
    "required": false
  },
  {
    "name": "linkId",
    "label": "Link ID",
    "type": "text",
    "required": false
  },
  {
    "name": "merchantRequestId",
    "label": "Merchant request ID",
    "type": "text",
    "required": false
  },
  {
    "name": "linkType",
    "label": "Link type",
    "type": "select",
    "required": false,
    "options": [
      {
        "label": "Fixed",
        "value": "FIXED"
      },
      {
        "label": "Generic",
        "value": "GENERIC"
      }
    ]
  },
  {
    "name": "paymentStatus",
    "label": "Payment status",
    "type": "select",
    "required": false,
    "options": [
      {
        "label": "Created",
        "value": "CREATED"
      },
      {
        "label": "Pending",
        "value": "PENDING"
      },
      {
        "label": "Success",
        "value": "SUCCESS"
      },
      {
        "label": "Failed",
        "value": "FAILED"
      },
      {
        "label": "Expired",
        "value": "EXPIRED"
      }
    ]
  },
  {
    "name": "isActive",
    "label": "Is active",
    "type": "boolean",
    "required": false
  }
]
```

### Response mapping (Search)

| Field | Expression |
| ----- | ----------- |
| `iterate` | `{{body.data.linkDetailsList}}` |
| `output` | `{{item}}` |

### Module Communication — reference (`jsonc`, matches `fetchPaymentLinks.jsonc`)

```jsonc
/**
 * MODULE: fetchPaymentLinks
 * TYPE: Search (returns a list of payment links)
 * PAYTM ENDPOINT: POST /link/fetch (via proxy)
 * PROXY FUNCTION: fetchPaymentLinks
 *
 * All parameters are optional — empty request returns all links.
 * linkType: FIXED / GENERIC
 * paymentStatus: CREATED / PENDING / SUCCESS / FAILED / EXPIRED
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Verify body.data.linkDetailsList iterate path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/make/fetchPaymentLinks?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
        "params": {
            "fromDate": "{{formatDate(parameters.fromDate; 'YYYY-MM-DD')}}",
            "toDate": "{{formatDate(parameters.toDate; 'YYYY-MM-DD')}}",
            "linkId": "{{parameters.linkId}}",
            "merchantRequestId": "{{parameters.merchantRequestId}}",
            "linkType": "{{parameters.linkType}}",
            "paymentStatus": "{{parameters.paymentStatus}}",
            "isActive": "{{parameters.isActive}}"
        }
    },
    "response": {
        // Verify body.data.linkDetailsList is the correct iterate path during E2E testing.
        "iterate": "{{body.data.linkDetailsList}}",
        "output": "{{item}}"
    }
}
```

### Module Communication (`JSON`, paste into Make)

```json
{ status, function, requestId, data: <paytm_response> }
 *   Verify body.data.linkDetailsList iterate path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/make/fetchPaymentLinks?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
        "params": {
            "fromDate": "{{formatDate(parameters.fromDate; 'YYYY-MM-DD')}}",
            "toDate": "{{formatDate(parameters.toDate; 'YYYY-MM-DD')}}",
            "linkId": "{{parameters.linkId}}",
            "merchantRequestId": "{{parameters.merchantRequestId}}",
            "linkType": "{{parameters.linkType}}",
            "paymentStatus": "{{parameters.paymentStatus}}",
            "isActive": "{{parameters.isActive}}"
        }
    },
    "response": {
        "iterate": "{{body.data.linkDetailsList}}",
        "output": "{{item}}"
    }
}
```

---

## 3. `fetchTransactionsForLink` (Search)

**Source:** [`app/modules/fetchTransactionsForLink.jsonc`](../app/modules/fetchTransactionsForLink.jsonc)

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default | Notes |
| ---------------- | ----------- | -------- | ------- | ----- |
| `linkId` | `text` | Yes | — | — |
| `searchStartDate` | `date` | No | — | — |
| `searchEndDate` | `date` | No | — | — |
| `fetchAllTxns` | `boolean` | No | — | — |

### Mappable parameters (`JSON`, paste)

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
  }
]
```

### Response mapping (Search)

| Field | Expression |
| ----- | ----------- |
| `iterate` | `{{body.data.txnDetailsList}}` |
| `output` | `{{item}}` |

### Module Communication — reference (`jsonc`, matches `fetchTransactionsForLink.jsonc`)

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
    "url": "{{connection.baseUrl}}/make/fetchTransactionsForLink?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
        "params": {
            "linkId": "{{parameters.linkId}}",
            "searchStartDate": "{{formatDate(parameters.searchStartDate; 'YYYY-MM-DD')}}",
            "searchEndDate": "{{formatDate(parameters.searchEndDate; 'YYYY-MM-DD')}}",
            "fetchAllTxns": "{{parameters.fetchAllTxns}}"
        }
    },
    "response": {
        // Verify body.data.txnDetailsList is the correct iterate path during E2E testing.
        "iterate": "{{body.data.txnDetailsList}}",
        "output": "{{item}}"
    }
}
```

### Module Communication (`JSON`, paste into Make)

```json
{ status, function, requestId, data: <paytm_response> }
 *   Verify body.data.txnDetailsList iterate path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/make/fetchTransactionsForLink?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
        "params": {
            "linkId": "{{parameters.linkId}}",
            "searchStartDate": "{{formatDate(parameters.searchStartDate; 'YYYY-MM-DD')}}",
            "searchEndDate": "{{formatDate(parameters.searchEndDate; 'YYYY-MM-DD')}}",
            "fetchAllTxns": "{{parameters.fetchAllTxns}}"
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

**Source:** [`app/modules/fetchOrderList.jsonc`](../app/modules/fetchOrderList.jsonc)

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default | Notes |
| ---------------- | ----------- | -------- | ------- | ----- |
| `startDate` | `date` | Yes | — | — |
| `endDate` | `date` | Yes | — | — |
| `orderSearchStatus` | `select` | No | `ALL` | `ifempty` |
| `orderSearchType` | `select` | No | `TRANSACTION` | `ifempty` |
| `pageNumber` | `integer` | No | `1` | `ifempty` |
| `pageSize` | `integer` | No | `20` | `ifempty` |
| `merchantOrderId` | `text` | No | — | — |
| `payMode` | `text` | No | — | — |

### Mappable parameters (`JSON`, paste)

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
    "default": "ALL",
    "options": [
      {
        "label": "All",
        "value": "ALL"
      },
      {
        "label": "Open",
        "value": "OPEN"
      },
      {
        "label": "Closed",
        "value": "CLOSED"
      },
      {
        "label": "Failed",
        "value": "FAILED"
      }
    ]
  },
  {
    "name": "orderSearchType",
    "label": "Order search type",
    "type": "select",
    "required": false,
    "default": "TRANSACTION",
    "options": [
      {
        "label": "Transaction",
        "value": "TRANSACTION"
      },
      {
        "label": "Order",
        "value": "ORDER"
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
    "name": "pageSize",
    "label": "Page size",
    "type": "integer",
    "required": false,
    "default": 20
  },
  {
    "name": "merchantOrderId",
    "label": "Merchant order ID",
    "type": "text",
    "required": false
  },
  {
    "name": "payMode",
    "label": "Pay mode",
    "type": "text",
    "required": false
  }
]
```

### Response mapping (Search)

| Field | Expression |
| ----- | ----------- |
| `iterate` | `{{body.data.body.txn}}` |
| `output` | `{{item}}` |

### Module Communication — reference (`jsonc`, matches `fetchOrderList.jsonc`)

```jsonc
/**
 * MODULE: fetchOrderList
 * TYPE: Search (returns a list of orders)
 * PAYTM ENDPOINT: POST /merchant-passbook/search/list/order/v2 (via proxy)
 * PROXY FUNCTION: fetchOrderList
 *
 * Standard Checksum API — proxy builds the AES-signed {body, head} envelope.
 * No checksum logic in IML.
 *
 * AUTH PATTERN (same for all modules)
 *   X-Signature = HMAC-SHA256(createJSON(body), connection.keySecret)
 *   The proxy verifies this, then signs the downstream Paytm request.
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Iterate path for the order list: body.data.body.txn
 *   Verify this path against the actual Paytm response during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/make/fetchOrderList?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
        "params": {
            "startDate": "{{formatDate(parameters.startDate; 'YYYY-MM-DD')}}",
            "endDate": "{{formatDate(parameters.endDate; 'YYYY-MM-DD')}}",
            "orderSearchStatus": "{{ifempty(parameters.orderSearchStatus; 'ALL')}}",
            "orderSearchType": "{{ifempty(parameters.orderSearchType; 'TRANSACTION')}}",
            "pageNumber": "{{ifempty(parameters.pageNumber; 1)}}",
            "pageSize": "{{ifempty(parameters.pageSize; 20)}}",
            "merchantOrderId": "{{parameters.merchantOrderId}}",
            "payMode": "{{parameters.payMode}}"
        }
    },
    "response": {
        // Iterate over the order list returned by Paytm.
        // Verify body.data.body.txn is the correct path during E2E testing.
        "iterate": "{{body.data.body.txn}}",
        "output": "{{item}}"
    }
}
```

### Module Communication (`JSON`, paste into Make)

```json
{body, head} envelope.
 * No checksum logic in IML.
 *
 * AUTH PATTERN (same for all modules)
 *   X-Signature = HMAC-SHA256(createJSON(body), connection.keySecret)
 *   The proxy verifies this, then signs the downstream Paytm request.
 *
 * RESPONSE STRUCTURE
 *   Proxy wraps Paytm response: { status, function, requestId, data: <paytm_response> }
 *   Iterate path for the order list: body.data.body.txn
 *   Verify this path against the actual Paytm response during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/make/fetchOrderList?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
        "params": {
            "startDate": "{{formatDate(parameters.startDate; 'YYYY-MM-DD')}}",
            "endDate": "{{formatDate(parameters.endDate; 'YYYY-MM-DD')}}",
            "orderSearchStatus": "{{ifempty(parameters.orderSearchStatus; 'ALL')}}",
            "orderSearchType": "{{ifempty(parameters.orderSearchType; 'TRANSACTION')}}",
            "pageNumber": "{{ifempty(parameters.pageNumber; 1)}}",
            "pageSize": "{{ifempty(parameters.pageSize; 20)}}",
            "merchantOrderId": "{{parameters.merchantOrderId}}",
            "payMode": "{{parameters.payMode}}"
        }
    },
    "response": {
        "iterate": "{{body.data.body.txn}}",
        "output": "{{item}}"
    }
}
```

---

## 5. `orderDetail` (Action, RTDD / settlement via proxy)

**Source:** [`app/modules/orderDetail.jsonc`](../app/modules/orderDetail.jsonc)

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default | Notes |
| ---------------- | ----------- | -------- | ------- | ----- |
| `bizOrderId` | `text` | Yes | — | Transaction-level id |
| `isSettlementInfo` | `boolean` | No | `false` | `ifempty` |
| `excludePaymentsData` | `boolean` | No | `false` | `ifempty` |

### Mappable parameters (`JSON`, paste)

`name` must match `parameters.<name>` in Communication.

```json
[
  {
    "name": "bizOrderId",
    "label": "Business order ID (bizOrderId)",
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

### Module Communication — reference (`jsonc`, matches `orderDetail.jsonc`)

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
    "url": "{{connection.baseUrl}}/make/orderDetail?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
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

### Module Communication (`JSON`, paste into Make)

```json
{ status, function, requestId, data: <paytm_response> }
 *   Verify body.data path against actual Paytm response during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/make/orderDetail?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
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

**Source:** [`app/modules/initiateRefund.jsonc`](../app/modules/initiateRefund.jsonc)

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default | Notes |
| ---------------- | ----------- | -------- | ------- | ----- |
| `orderId` | `text` | Yes | — | — |
| `txnId` | `text` | Yes | — | — |
| `refId` | `text` | Yes | — | Idempotent refund key |
| `refundAmount` | `number` | Yes | — | — |
| `comments` | `text` | No | — | — |

### Mappable parameters (`JSON`, paste)

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

### Module Communication — reference (`jsonc`, matches `initiateRefund.jsonc`)

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
    "url": "{{connection.baseUrl}}/make/initiateRefund?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
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

### Module Communication (`JSON`, paste into Make)

```json
{ status, function, requestId, data: <paytm_response> }
 *   Verify body.data path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/make/initiateRefund?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
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

**Source:** [`app/modules/checkRefundStatus.jsonc`](../app/modules/checkRefundStatus.jsonc)

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default | Notes |
| ---------------- | ----------- | -------- | ------- | ----- |
| `orderId` | `text` | Yes | — | — |
| `refId` | `text` | Yes | — | — |

### Mappable parameters (`JSON`, paste)

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

### Module Communication — reference (`jsonc`, matches `checkRefundStatus.jsonc`)

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
    "url": "{{connection.baseUrl}}/make/checkRefundStatus?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
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

### Module Communication (`JSON`, paste into Make)

```json
{ status, function, requestId, data: <paytm_response> }
 *   Verify body.data path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/make/checkRefundStatus?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
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

**Source:** [`app/modules/fetchRefundList.jsonc`](../app/modules/fetchRefundList.jsonc)

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default | Notes |
| ---------------- | ----------- | -------- | ------- | ----- |
| `startDate` | `date` | Yes | — | — |
| `endDate` | `date` | Yes | — | — |
| `pageNum` | `integer` | No | `1` | `ifempty` |
| `pageSize` | `integer` | No | `20` | `ifempty` |
| `isSort` | `boolean` | No | `true` | `ifempty` |

### Mappable parameters (`JSON`, paste)

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
    "name": "pageSize",
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
| ----- | ----------- |
| `iterate` | `{{body.data.refundDetailList}}` |
| `output` | `{{item}}` |

### Module Communication — reference (`jsonc`, matches `fetchRefundList.jsonc`)

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
    "url": "{{connection.baseUrl}}/make/fetchRefundList?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
        "params": {
            "startDate": "{{formatDate(parameters.startDate; 'YYYY-MM-DD')}}",
            "endDate": "{{formatDate(parameters.endDate; 'YYYY-MM-DD')}}",
            "pageNum": "{{ifempty(parameters.pageNum; 1)}}",
            "pageSize": "{{ifempty(parameters.pageSize; 20)}}",
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

### Module Communication (`JSON`, paste into Make)

```json
{ status, function, requestId, data: <paytm_response> }
 *   Verify body.data.refundDetailList iterate path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/make/fetchRefundList?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
        "params": {
            "startDate": "{{formatDate(parameters.startDate; 'YYYY-MM-DD')}}",
            "endDate": "{{formatDate(parameters.endDate; 'YYYY-MM-DD')}}",
            "pageNum": "{{ifempty(parameters.pageNum; 1)}}",
            "pageSize": "{{ifempty(parameters.pageSize; 20)}}",
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

## 9. `settlementBillList` (Search, RTDD)

**Source:** [`app/modules/settlementBillList.jsonc`](../app/modules/settlementBillList.jsonc)

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default | Notes |
| ---------------- | ----------- | -------- | ------- | ----- |
| `settlementStartTime` | `datetime` | Yes | — | RTDD field names |
| `settlementEndTime` | `datetime` | Yes | — | RTDD field names |
| `pageNum` | `integer` | No | `1` | — |
| `pageSize` | `integer` | No | `20` | Typical max `50` |
| `settlementBillId` | `text` | No | — | — |
| `settleStatus` | `select` | No | — | `BANK_INITIATED` / `PAYOUT_SETTLED` / `PAYOUT_UNSETTLED` / `WAIT_FOR_SETTLE` |
| `utrNo` | `text` | No | — | — |

### Mappable parameters (`JSON`, paste)

`name` must match `parameters.<name>` in Communication.

```json
[
  {
    "name": "settlementStartTime",
    "label": "Settlement start time",
    "type": "datetime",
    "required": true
  },
  {
    "name": "settlementEndTime",
    "label": "Settlement end time",
    "type": "datetime",
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
    "name": "pageSize",
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
| ----- | ----------- |
| `iterate` | `{{body.data.body.settleBillList}}` |
| `output` | `{{item}}` |

### Module Communication — reference (`jsonc`, matches `settlementBillList.jsonc`)

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
    "url": "{{connection.baseUrl}}/make/settlementBillList?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
        "params": {
            "settlementStartTime": "{{formatDate(parameters.settlementStartTime; 'YYYY-MM-DD HH:mm:ss')}}",
            "settlementEndTime": "{{formatDate(parameters.settlementEndTime; 'YYYY-MM-DD HH:mm:ss')}}",
            "pageNum": "{{ifempty(parameters.pageNum; 1)}}",
            "pageSize": "{{ifempty(parameters.pageSize; 20)}}",
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

### Module Communication (`JSON`, paste into Make)

```json
{ status, function, requestId, data: <paytm_response> }
 *   Verify body.data.body.settleBillList iterate path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/make/settlementBillList?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
        "params": {
            "settlementStartTime": "{{formatDate(parameters.settlementStartTime; 'YYYY-MM-DD HH:mm:ss')}}",
            "settlementEndTime": "{{formatDate(parameters.settlementEndTime; 'YYYY-MM-DD HH:mm:ss')}}",
            "pageNum": "{{ifempty(parameters.pageNum; 1)}}",
            "pageSize": "{{ifempty(parameters.pageSize; 20)}}",
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

## 10. `settlementTxnListByDate` (Search, RTDD)

**Source:** [`app/modules/settlementTxnListByDate.jsonc`](../app/modules/settlementTxnListByDate.jsonc)

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default | Notes |
| ---------------- | ----------- | -------- | ------- | ----- |
| `startDate` | `datetime` | Yes | — | `YYYY-MM-DD HH:mm:ss` |
| `endDate` | `datetime` | Yes | — | `YYYY-MM-DD HH:mm:ss` |
| `pageNum` | `integer` | No | `1` | — |
| `pageSize` | `integer` | No | `20` | — |
| `settlementOrderId` | `text` | No | — | — |

### Mappable parameters (`JSON`, paste)

`name` must match `parameters.<name>` in Communication.

```json
[
  {
    "name": "startDate",
    "label": "Start date/time",
    "type": "datetime",
    "required": true
  },
  {
    "name": "endDate",
    "label": "End date/time",
    "type": "datetime",
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
    "name": "pageSize",
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
| ----- | ----------- |
| `iterate` | `{{body.data.body.txnList}}` |
| `output` | `{{item}}` |

### Module Communication — reference (`jsonc`, matches `settlementTxnListByDate.jsonc`)

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
    "url": "{{connection.baseUrl}}/make/settlementTxnListByDate?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
        "params": {
            "startDate": "{{formatDate(parameters.startDate; 'YYYY-MM-DD HH:mm:ss')}}",
            "endDate": "{{formatDate(parameters.endDate; 'YYYY-MM-DD HH:mm:ss')}}",
            "pageNum": "{{ifempty(parameters.pageNum; 1)}}",
            "pageSize": "{{ifempty(parameters.pageSize; 20)}}",
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

### Module Communication (`JSON`, paste into Make)

```json
{ status, function, requestId, data: <paytm_response> }
 *   Verify body.data.body.txnList iterate path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/make/settlementTxnListByDate?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
        "params": {
            "startDate": "{{formatDate(parameters.startDate; 'YYYY-MM-DD HH:mm:ss')}}",
            "endDate": "{{formatDate(parameters.endDate; 'YYYY-MM-DD HH:mm:ss')}}",
            "pageNum": "{{ifempty(parameters.pageNum; 1)}}",
            "pageSize": "{{ifempty(parameters.pageSize; 20)}}",
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

**Source:** [`app/modules/fetchSubscriptionStatus.jsonc`](../app/modules/fetchSubscriptionStatus.jsonc)

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default | Notes |
| ---------------- | ----------- | -------- | ------- | ----- |
| `subsId` | `text` | No | — | Provide ≥1 identifier across this row |
| `orderId` | `text` | No | — | — |
| `linkId` | `text` | No | — | — |
| `custId` | `text` | No | — | — |

### Mappable parameters (`JSON`, paste)

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

### Module Communication — reference (`jsonc`, matches `fetchSubscriptionStatus.jsonc`)

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
    "url": "{{connection.baseUrl}}/make/fetchSubscriptionStatus?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
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

### Module Communication (`JSON`, paste into Make)

```json
{ status, function, requestId, data: <paytm_response> }
 *   Verify body.data path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/make/fetchSubscriptionStatus?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
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

**Source:** [`app/modules/pauseResumeSubscription.jsonc`](../app/modules/pauseResumeSubscription.jsonc)

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default | Notes |
| ---------------- | ----------- | -------- | ------- | ----- |
| `subsId` | `text` | Yes | — | — |
| `status` | `select` | Yes | — | `SUSPENDED` / `ACTIVE` |

### Mappable parameters (`JSON`, paste)

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
    "label": "Subscription status action",
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

### Module Communication — reference (`jsonc`, matches `pauseResumeSubscription.jsonc`)

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
    "url": "{{connection.baseUrl}}/make/pauseResumeSubscription?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
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

### Module Communication (`JSON`, paste into Make)

```json
{ status, function, requestId, data: <paytm_response> }
 *   Verify body.data path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/make/pauseResumeSubscription?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
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

**Source:** [`app/modules/cancelSubscription.jsonc`](../app/modules/cancelSubscription.jsonc)

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default | Notes |
| ---------------- | ----------- | -------- | ------- | ----- |
| `subsId` | `text` | Yes | — | — |

### Mappable parameters (`JSON`, paste)

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

### Module Communication — reference (`jsonc`, matches `cancelSubscription.jsonc`)

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
    "url": "{{connection.baseUrl}}/make/cancelSubscription?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
        "params": {
            "subsId": "{{parameters.subsId}}"
        }
    },
    "response": {
        "output": "{{body.data}}"
    }
}
```

### Module Communication (`JSON`, paste into Make)

```json
{ status, function, requestId, data: <paytm_response> }
 *   Verify body.data path during E2E testing.
 */
{
    "url": "{{connection.baseUrl}}/make/cancelSubscription?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
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

**Source:** [`app/modules/makeApiCall.jsonc`](../app/modules/makeApiCall.jsonc)

### Mappable parameters (reference table)

| Parameter `name` | Make `type` | Required | Default | Notes |
| ---------------- | ----------- | -------- | ------- | ----- |
| `method` | `select` | Yes | — | HTTP verb |
| `url` | `text` | Yes | — | Relative path only |
| `headers` | `collection` | No | — | — |
| `body` | `text` or app-specific | No | — | Raw JSON forwarded by proxy |

### Mappable parameters (`JSON`, paste)

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
    "label": "Relative URL path",
    "type": "text",
    "required": true
  },
  {
    "name": "headers",
    "label": "Extra headers",
    "type": "collection",
    "required": false
  },
  {
    "name": "body",
    "label": "Request body",
    "type": "text",
    "required": false
  }
]
```

### Module Communication — reference (`jsonc`, matches `makeApiCall.jsonc`)

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
    "url": "{{connection.baseUrl}}/make/makeApiCall?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
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

### Module Communication (`JSON`, paste into Make)

```json
{
    "url": "{{connection.baseUrl}}/make/makeApiCall?mid={{connection.merchantId}}",
    "method": "POST",
    "headers": {
        "Content-Type": "application/json",
        "X-Signature": "{{sha256(createJSON(body); connection.keySecret)}}"
    },
    "body": {
        "requestId": "{{formatDate(now; 'x')}}",
        "timestamp": "{{formatDate(now; 'x')}}",
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

- [`make-connection-paytm.md`](./make-connection-paytm.md)
- [`api-mapping.md`](./api-mapping.md)
