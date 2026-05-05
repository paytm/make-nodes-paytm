# Make UI — Paytm connection (`paytm.jsonc`)

How to configure the **Paytm Merchant** connection in the **Make Custom Apps** editor so it matches `[app/connections/paytm.jsonc](../app/connections/paytm.jsonc)`.

---

## Connection type

1. Open your app → **Connections** → create or edit `**paytmConnection`** (or the name referenced as `"connection"` in modules).
2. Set the connection **type** to **Basic** or **API key** (whatever your Apps Editor labels for *non‑OAuth credential storage*) — **not OAuth 2.0**.

OAuth is unnecessary: the merchant pastes `**merchantId`** + `**keySecret`** + chooses `**baseUrl`**.

---

## Parameters tab

Add **exactly three** mappable/form parameters. Their `**name`** values must match these strings so IML resolves correctly:

**Important:** Make only accepts `**type`** as lowercase slugs (e.g. `"text"`), not `"Text"`. Allowed values include: `text`, `password`, `select`, `email`, `boolean`, `date`, `number`, `integer`, `timestamp`, … (see Apps Editor validation error list if paste fails).


| Parameter `name` | Label (your choice)      | `type` (exact) | Required |
| ---------------- | ------------------------ | -------------- | -------- |
| `merchantId`     | Merchant ID (MID)        | `**text`**     | Yes      |
| `keySecret`      | Key Secret               | `**password`** | Yes      |
| `baseUrl`        | Environment / Proxy base | `**select`**   | Yes      |


**Example parameter definitions (JSON):**

```json
[
  { "name": "merchantId", "label": "Merchant ID", "type": "text", "required": true },
  { "name": "keySecret", "label": "Key Secret", "type": "password", "required": true },
  {
    "name": "baseUrl",
    "label": "Environment",
    "type": "select",
    "required": true,
    "options": [
      { "label": "Production", "value": "https://paytm-make-proxy.paytmpayments.com" },
      { "label": "Staging", "value": "https://paytm-make-proxy-staging.paytmpayments.com" }
    ]
  }
]
```

### `baseUrl` select options


| Label      | Value                                                |
| ---------- | ---------------------------------------------------- |
| Production | `https://paytm-make-proxy.paytmpayments.com`         |
| Staging    | `https://paytm-make-proxy-staging.paytmpayments.com` |


Use the URLs your team deploys (`paytm.jsonc` comments). Until DNS/Lambda exists, swap in a staging API Gateway URL for testing.

---

## Communication tab (save / validation)

When the merchant clicks **Save connection**, Make runs one HTTP request defined here.

**Important naming rule:** During this **validation request only**, secrets are `**parameters.<field>`** (what the user just typed — not `**connection.`**).

Paste the JSON below **without** the `//` comment lines:

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

### What this does


| Piece             | Behaviour                                                                                                                         |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| **URL**           | Lightweight read to proxy: `**fetchPaymentLinks`** with empty `**params`** (allowed by API).                                      |
| `**?mid=`**       | Same pattern as modules: MID in query string.                                                                                     |
| `**X-Signature`** | HMAC‑SHA256 of `**createJSON(body)**` with the **Key Secret** the user entered — proves possession of `**keySecret`**.            |
| `**body`**        | Same envelope as modules: `**requestId`**, `**timestamp`**, `**params**`. Empty `**params**` is fine for `**fetchPaymentLinks**`. |
| `**valid**`       | Connection is marked **valid** only if HTTP **status is 200** (proxy accepted HMAC and responded OK).                             |


**401:** wrong `**keySecret`** or HMAC mismatch. **404 / connection refused:** `**baseUrl`** or route wrong; proxy not deployed.

---

## After save: modules use `connection.*`

Saved connections expose:

- `**{{connection.merchantId}}`**
- `**{{connection.keySecret}}`**
- `**{{connection.baseUrl}}`**

All module JSONCs under `app/modules/` use `**connection.***` in URLs and `**X-Signature**` — not `**parameters.***`.

---

## Checklist before testing Save


| Check          | Detail                                                                                                                                                                                   |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Proxy deployed | `**POST /make/fetchPaymentLinks**` exists behind `**baseUrl**`.                                                                                                                          |
| HMAC parity    | Proxy verifies **same canonical body** Make signs (`createJSON(body)` + encoding).                                                                                                       |
| MID            | Real test MID allowed on that proxy path.                                                                                                                                                |
| IML helpers    | `**formatDate(now; 'x')**` (epoch ms for `requestId` / `timestamp`; `uuid()` / `toTimestamp(now)` not supported everywhere), `**createJSON(body)**`, `**sha256(createJSON(body); parameters.keySecret)**` (HMAC-SHA256; no `hmac()` in IML). |


---

## If validation must be skipped temporarily

Until the proxy responds with **200**, Make will not mark the connection valid. Options:

1. Deploy proxy + `**fetchPaymentLinks`** first with HMAC verification.
2. Or use a stub endpoint that returns **200** **only for development** (not for production merchants).
3. Or adjust `**valid`** in agreement with Make’s rules (prefer fixing infrastructure over weakening validation).

---

## Security notes (from `paytm.jsonc`)

- `**keySecret`**: password type; never map it to module outputs or logs.  
- `**keySecret`**: used for **inbound HMAC** and (server-side on proxy) **Paytm AES checksum** — not sent raw to Paytm from Make after HMAC verification is implemented downstream as designed.

---

## Related docs

- [api-mapping.md](./api-mapping.md) — proxy URLs and inbound HMAC summary  
- [make-ui-modules-communication-and-parameters.md](./make-ui-modules-communication-and-parameters.md) — module communications using `**connection.`***

