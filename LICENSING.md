# SonVu CNC Plugins — Licensing deployment

The extension has a complete licensing client, but enforcement is intentionally
disabled in source development builds. Do not enable enforcement until a
production RSA public key is embedded and either manual token issuance or the
HTTPS activation API is ready.

## Runtime design

- A local 14-day trial starts the first time the extension loads with
  enforcement enabled. It grants `features: ["*"]`, so every module is usable.
- The original trial start is retained across SketchUp restarts. Clock rollback
  protection also applies during the trial.
- License checks occur when mortise or tenon creation starts and again before
  a placement tool begins.
- Cleanup remains available without a license.
- The local token is an RSA-SHA256 signed `base64url(payload).base64url(signature)`
  value stored with `Sketchup.write_default`.
- Tokens are bound to a hashed device ID and contain feature entitlements.
- `offline_until` is required. The client attempts an online refresh during the
  final three days or after offline expiry.
- A clock moving backwards by more than six hours blocks licensed commands.

The local trial is a customer-friendly first layer, not strong anti-tamper
protection: a determined user who removes SketchUp preferences may reset it.
Use server-issued trial tokens if reset-resistant trials become necessary.

## Enable a production build

1. Generate and securely back up a key pair. The private key must never enter
   the plugin folder, source repository, RBZ, or license server logs:

   ```powershell
   ruby sonvu_cnc_plugins\shared\licensing\tools\issuer.rb init C:\Secure\SonVuLicenseKeys
   ```

2. Copy the complete contents of `sonvu_license_public.pem` between the
   `PUBLIC_KEY_PEM` heredoc markers in `shared/licensing/config.rb`.
3. For online activation, set `SERVER_URL` to an HTTPS base URL. Do not add a
   trailing endpoint name.
4. Set `ENFORCEMENT_ENABLED = true`.
5. Run all tests and package `.rbe` production files. Exclude
   `shared/licensing/test/` and `shared/licensing/tools/` from the RBZ.

## Issue a manual offline token

The customer opens **Extensions > SonVu CNC Plugins > Quản lý giấy phép**, uses
**Sao chép**, and sends the full 64-character device ID. Then run:

```powershell
ruby sonvu_cnc_plugins\shared\licensing\tools\issuer.rb issue `
  C:\Secure\SonVuLicenseKeys\sonvu_license_private.pem `
  CUSTOMER_DEVICE_ID `
  C:\Secure\customer.token `
  "Customer name" 30 dogbone_joinery,furniture_builder
```

Send only the `.token` file contents to the customer. They paste it into the
License Manager. Manual tokens expire at `offline_until`; issue a replacement
when appropriate.

## HTTPS server contract

The configured base URL receives JSON POST requests:

- `POST /activate`: `license_key`, `product_id`, `device_id`, `plugin_version`,
  and `sketchup_version`.
- `POST /refresh`: current `token` plus the common device/product fields.
- `POST /deactivate`: current `token` plus the common device/product fields.

Successful activation and refresh responses return `{"token":"SIGNED_TOKEN"}`.
Errors use a non-2xx status and may return
`{"message":"Customer-facing Vietnamese error"}`.

The server enforces seat limits, revocation, ownership, and refresh policy. It
signs tokens with the private key; the plugin only verifies with the public key.

Required token payload fields:

```json
{
  "license_id": "SV-123",
  "product_id": "sonvu_cnc_plugins",
  "device_id": "64-character device hash",
  "features": ["dogbone_joinery", "furniture_builder"],
  "customer_name": "Customer",
  "license_type": "perpetual",
  "issued_at": 1783872000,
  "offline_until": 1786464000
}
```

Optional `not_before` is supported. `features: ["*"]` enables every module.

## Customer RBZ safety

- Exclude tests and licensing tools.
- Never package a private key, customer database, or server credentials.
- Convert sensitive Ruby code to `.rbe` and omit `.rb` extensions in loaders.
- Keep the public key in encrypted production Ruby code rather than a
  replaceable external PEM file.
