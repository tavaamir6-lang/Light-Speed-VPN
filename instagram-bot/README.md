# Instagram Comment → Private Reply Bot

This service receives Instagram webhook events and sends a private reply when a comment contains the configured keyword.

## Environment variables

- `META_VERIFY_TOKEN` — any secret string you choose for Meta webhook verification.
- `INSTAGRAM_ACCESS_TOKEN` — the Meta/Instagram access token. Never commit it to GitHub.
- `GRAPH_API_VERSION` — Graph API version, for example `v24.0`; change it to the version supported by your Meta app.
- `COMMENT_KEYWORD` — keyword to detect (default: `کانفیگ`).
- `REPLY_TEXT` — private reply text.
- `PORT` — supplied automatically by most hosts.

## Webhook URL

After deployment, use:

`https://YOUR-DOMAIN/webhook`

Meta first calls GET `/webhook` for verification, then POSTs comment events to the same endpoint.

## Important

The Instagram app must have the required Instagram professional-account permissions and webhook subscription configured in Meta. Do not put an access token in source code or GitHub.
