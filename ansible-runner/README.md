# GitOps Ansible runner

Argo CD owns this namespace, CronJob, webhook, RBAC and Secret references.
No workflow runs `kubectl` or changes cluster configuration. The webhook's
namespaced service account creates execution Jobs from the GitOps-managed
CronJob template; it does not deploy configuration.

## Execution

The CronJob runs at 03:00 UTC on days 1, 6, 11, 16, 21, 26 and 31 where
present (`0 3 */5 * *`). Cron resets at each month boundary, so the gap to
the next month's first run can be shorter than five days. This is a calendar
schedule, not five days after the last success; missed windows are not
replayed. Webhook and manual runs do not reset it.

Jobs created manually from the CronJob in the Argo CD UI execute immediately.
There is no date guard in the runner; every invocation applies configuration,
subject to the same shared concurrency lock.

Each execution clones `tpaulus/ansible`'s `main` branch, installs its pinned
Galaxy dependencies and applies `playbooks/site.yml` without `--limit`.
The existing NetBox production inventory and playbook host scopes remain
authoritative. Network provisioning, maintenance, migrations and decommission
playbooks are **not** added to `site.yml`. The resolved commit is logged.
Unparseable or empty inventory fails rather than reporting a successful no-op.

Both trigger paths acquire the same Kubernetes Lease with an atomic
resource-version update. A competing run fails visibly rather than running
concurrently or waiting indefinitely. Jobs have a four-hour total deadline and
no automatic retries; the Lease expires after five hours if a pod dies before
releasing it. Keep `activeDeadlineSeconds` at or below 14400 and the Lease
duration above that deadline plus termination grace. Do not shorten the Lease
while a run is active. Argo ignores runtime Lease state, including during sync.
The four-hour deadline also includes dependency installation and pending time.

Runs can modify the K3s cluster hosting the runner. Node reboots, upgrades or
network changes may interrupt it; an external controller is preferable for
cluster-wide disruptive maintenance. A successful webhook response means a
Job was submitted, **not** that Ansible succeeded. Inspect Job results and pod
logs in Argo CD/your existing observability. Completed Jobs expire after a day.

### Kured reboot protection

`AnsibleConfigurationInProgress` fires without a pending delay while any
`ansible` container in this namespace is running, covering scheduled and
webhook-created Jobs but not the idle webhook Deployment. Kured's existing
Prometheus blocker pauses reboots for this alert; it must stay out of Kured's
alert-name **ignore** expression. The first Alertmanager child route sends it
only to the `noop` receiver, with no email, Todoist or webhook notifications.
It resolves when no runner containers are running. Protection is subject to
kube-state-metrics scrape/evaluation latency and cannot cancel a reboot that
Kured has already started.

## Provisioning through GitOps

1. Merge the image sources and build workflow. GitHub Actions publishes
   `ghcr.io/tpaulus/ansible-runner:gitops` and `sha-<commit>` on `main`
   for both amd64 and arm64 nodes.
   Make the GHCR package public, or provision an image-pull Secret through your
   secret manager and reference it in both pod specifications.
   Before enabling the application, replace **both** image references with the
   published immutable `sha-<commit>` tag. For subsequent image updates, build
   first and change those references in a Git commit; do not restart workloads
   imperatively or rely on a mutable tag refreshing an existing pod.
2. Use the shared SSH key from `K3S/Applier SSH Key` (field `private key`) as
   the read-only GitHub deploy key for `tpaulus/ansible` and authorize its public
   key on every production inventory node.
   The remote account needs the playbooks' privilege-escalation permissions:
   passwordless sudo, or existing vaulted `ansible_become_password` variables.
   An SSH passphrase prompt is unsupported; use an unencrypted key
   protected by the secret manager.
3. Create the following 1Password items; the existing operator materializes
   the Secrets from the committed `OnePasswordItem` resources. Do **not**
   commit plaintext credentials or generated Secret YAML.
4. Merge/enable `argocd/applications/ansible-runner.yaml` once the image and
   credentials exist. Its parent application discovers it like the existing
   applications. Argo CD performs all reconciliation.

| 1Password item in `K3S` | Fields (exact names) |
| --- | --- |
| `Applier SSH Key` | `private key` (operator Secret key: `private-key`) |
| `Ansible-Runner` | `vault_password`, `NETBOX_TOKEN`, `ANSIBLE_REMOTE_USER` |
| `Ansible-Webhook` | `WEBHOOK_SECRET` (at least 32 random characters) |

The shared SSH key is projected as `/secrets/ssh_key` and copied with mode
0600 to `/work/.ssh/ssh_key` for both Git and Ansible.

`vault_password` is the existing Ansible Vault password stored in
`op://Infra/Ansible/password`, delivered as a read-only file. This avoids
interactive 1Password login and preserves the repository's Vault identity.
The NetBox token should be read-only. The webhook pod does not mount runner
credentials, and its HMAC secret is not injected into Ansible Jobs.

Initial provisioning should be supervised: `site.yml` applies real changes
to **all** inventory hosts, including the existing appliance-protection checks.
This configuration does not perform a live run or validate host readiness.

### SSH trust

Node SSH uses OpenSSH's `StrictHostKeyChecking=accept-new`: unknown keys are
trusted on first use and recorded in `/work/.ssh/known_hosts` on the Job's
existing `emptyDir` volume. No PVC or persistent host-key storage is used.
Changed keys are rejected within that run, but every new Job starts with an
empty node trust store and trusts the first key it sees again. No node
fingerprints need to be collected ahead of time. TOFU assumes the first
connection in each run is not intercepted.

GitHub is different: `image/github_known_hosts` contains its published Ed25519,
ECDSA and RSA keys, copied from
[GitHub's SSH key documentation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints).
Git uses **strict** checking against that bundled file, not TOFU. Update the
file and rebuild the image if GitHub rotates its keys.

## Native GitHub webhook

In `tpaulus/ansible`, open **Settings > Webhooks > Add webhook** and configure:

| Setting | Value |
| --- | --- |
| Payload URL | `https://ansible-webhook.ing.k3s.brickyard.whitestar.systems/hooks/ansible` |
| Content type | `application/json` |
| Secret | The `WEBHOOK_SECRET` value from `K3S/Ansible-Webhook` |
| SSL verification | Enabled |
| Events | Just the push event |
| Active | Enabled |

The endpoint uses ordinary HTTPS on port **443**, with an explicit
`NoClientCert` TLS option on both `websecure` and `web-mtls`. The public
`traefik-mtls` LoadBalancer maps port 443 to `web-mtls`, so the Ingress must
include that entrypoint even though this webhook does not require mTLS.
No mTLS certificates, SSH keys or trigger workflow
are needed in GitHub Actions. DNS and the endpoint must be publicly reachable
by GitHub. Other ingress routes keep their existing client-certificate policy.

`adnanh/webhook` verifies GitHub's `X-Hub-Signature-256` HMAC, repository and
event. Signed setup pings are acknowledged without submitting a Job. Only
non-deletion pushes to `tpaulus/ansible`'s `main` branch submit Jobs. Request
fields cannot select a repository, playbook, command, image or arbitrary Git
revision. Job names use the signed push payload's commit SHA to deduplicate
redeliveries while the Job exists. GitHub does not sign a delivery timestamp,
so there is no fabricated five-minute timestamp requirement; an old signed
payload can be replayed after the completed Job expires. The Job always applies
the latest `main`, not necessarily the triggering SHA. Push hooks do not wait
for Actions lint checks to finish.

After rotating the shared HMAC secret, update the repository webhook and the
1Password item, then change the Deployment pod template in Git to reload its
environment. The receiver creates execution Jobs only; cluster configuration
continues to be reconciled by Argo CD.

## Image publishing and validation

The image workflow follows
[GitHub's GHCR publishing example](https://docs.github.com/en/actions/tutorials/publish-packages/publish-docker-images#publishing-images-to-github-packages):
registry login with `GITHUB_TOKEN`, Docker metadata-generated tags and OCI
labels, multi-architecture build/push, and a GitHub artifact attestation of the
published digest. Actions are pinned to commit SHAs. It does not trigger
Ansible or run unit tests.

Use the existing manifest/schema, YAML and workflow linters for configuration
validation. Alert rules and Alertmanager configuration can be checked with
`promtool check rules` and `amtool check-config`. There is no runner unit-test
suite. Real SSH, NetBox, Vault and external webhook reachability remain
deployment-time checks once credentials have been provisioned.
