Kubernetes Manifests
====================

## Home Assistant certificate pull

Cert-manager already renews `home.paulus.family` in the `home-assistant-tls`
Secret. The manifests in `home-assistant/cert-reader-rbac.yaml` give the external
HA Core instance permission to get only that Secret, without list/watch or token
creation permissions. No SSH or HAOS host access is needed.

### Host setup

1. Sync the Home Assistant Argo CD application. Confirm the TLS Secret is ready.
2. From an administrator workstation, verify the RBAC:

   ```sh
   kubectl auth can-i get secret/home-assistant-tls -n home-assistant --as=system:serviceaccount:home-assistant:home-assistant-cert-reader
   kubectl auth can-i list secrets -n home-assistant --as=system:serviceaccount:home-assistant:home-assistant-cert-reader
   kubectl auth can-i get secret/other -n home-assistant --as=system:serviceaccount:home-assistant:home-assistant-cert-reader
   ```

   Only the first command should return `yes`.
3. Copy `home-assistant/host/cert_sync.py` into
   `/config/cert-sync/cert_sync.py` on HAOS using your existing file-access
   mechanism. It runs inside Core, using Python and Core's existing
   `cryptography` library; no additional packages are installed.
4. Put the Kubernetes API's CA certificate in `/config/cert-sync/cluster-ca.crt`.
   Use an API address reachable from Core and covered by the API certificate's
   SANs, not a Kubernetes-only service address. Do not disable TLS verification.
5. Request an expiring credential on the administrator workstation:

   ```sh
   umask 077
   kubectl -n home-assistant create token home-assistant-cert-reader --duration=720h > ha-cert-reader.token
   ```

   Transfer the token securely to `/config/cert-sync/token` and remove the
   workstation copy. Keep it out of Git, shell arguments, and logs. Set the
   directory to mode `0700` and credential files to `0600`. Protect HA backups,
   which may contain this credential and the TLS private key.
6. Create `/config/cert-sync/config.json` locally on HA:

   ```json
   {
     "api_url": "https://YOUR-REACHABLE-KUBERNETES-API:6443",
     "ca_file": "/config/cert-sync/cluster-ca.crt",
     "token_file": "/config/cert-sync/token"
   }
   ```

7. HAOS mounts `/ssl` read-only inside Core, so the script stores its managed
   pair under the writable `/config/cert-sync/tls` instead (see
   [Supervisor's Core mounts](https://github.com/home-assistant/supervisor/blob/main/supervisor/docker/homeassistant.py)).
   Run the script once **inside Core**, before
   changing Core's TLS paths. Confirm it returns `changed`, and a second run
   returns `unchanged`. Files are validated for hostname, validity, matching
   key, and TLS chain loading before a single atomic symlink switch publishes
   the pair. Failed fetches/validation leave the active generation untouched.
8. Point the existing `http` configuration at:

   ```yaml
   http:
     ssl_certificate: /config/cert-sync/tls/current/fullchain.pem
     ssl_key: /config/cert-sync/tls/current/privkey.pem
   ```

   Preserve any other existing HTTP settings. Restart Core manually for this
   initial configuration change.
9. Enable HA packages (`homeassistant: packages: !include_dir_named packages`,
   merged into the existing configuration), then copy
   `home-assistant/host/cert-sync-package.yaml.example` to
   `/config/packages/cert_sync.yaml`. This example is intentionally not a
   Kubernetes manifest. Check HA configuration and reload automations/restart
   Core to register the shell command. The automation polls every six hours
   and at startup, restarting Core only on a successful changed result.

The script rejects redirects, uses one bounded Secret fetch, and has a
45-second deadline within `shell_command`'s 60-second limit. Certificate
generations are retained for rollback; periodically remove old generations,
never the directory targeted by `current`, while no sync is running.

### Credential rotation and verification

The API server may shorten the requested token lifetime. Check the issued
token's expiration locally and schedule administrator rotation before that
expiration (for example, weekly for a confirmed 30-day token). Request a new
token using the command above, transfer it as a separate file, and atomically
replace `/config/cert-sync/token`. Run the shell command to verify access.
The HA identity cannot renew its own credential; failures raise a persistent
notification. For emergency revocation, remove its RoleBinding to cut off
Secret access immediately, or delete/recreate the ServiceAccount to invalidate
its tokens.

Before disabling the old Let's Encrypt add-on:

- Trigger the HA shell command and check the response and HTTPS connectivity.
- Test an invalid token, unavailable API, and incorrect CA: each must return
  nonzero, leave `current` unchanged, and avoid a restart. Restore the valid
  configuration afterward.
- Renew with `cmctl renew -n home-assistant home-assistant`, wait for issuance,
  then trigger the automation. Confirm one restart, the new served certificate,
  and no further restart on the next unchanged poll.
- Check hostname mismatch, expired certificates, and mismatched keys using the
  offline unit tests, never by corrupting the production Secret.
- Keep the old TLS files and add-on available for rollback until successful
  end-to-end verification. This repository does not disable that add-on.

Run the offline tests from the repository with Core's existing Python
`cryptography` dependency available:

```sh
python3 -m unittest discover -s home-assistant/host -p 'test_*.py' -v
```
