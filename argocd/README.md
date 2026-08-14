# Argo CD GitHub webhooks

The GitHub webhook endpoint is exposed at
`https://argocd-webhook.ing.k3s.brickyard.whitestar.systems/api/webhook` on
Traefik's `web-mtls` listener. The route uses a dedicated TLS option without
client authentication, while the rest of `web-mtls` continues to require
mTLS. It is limited to GitHub's `hooks` CIDR list by the
`github-webhook-ip-allowlist` middleware.

`github-webhook-ip-sync` runs every six hours and fetches
`https://api.github.com/meta`. It replaces the middleware only when the
response contains a non-empty `hooks` list; a failed or malformed fetch leaves
the last known-good list in place. GitHub documents this endpoint as the
source for webhook IP ranges, so the job should be monitored for failures.

Add a `webhook.github.secret` field to the existing OnePassword item
`vaults/K3S/items/argocd`. The OnePassword operator then exposes it through
the existing `argocd-secret`, which Argo CD uses to validate GitHub webhook
signatures. Configure the GitHub webhook with the same value, HTTPS, and only
the required events.
