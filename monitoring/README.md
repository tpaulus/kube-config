Source: https://github.com/techiescamp/kubernetes-prometheus/tree/master

## MetalLB external probes

Install [the HA Blackbox Exporter add-on](https://github.com/tpaulus/ha-blackbox-exporter)
before deploying the external scrape jobs and alerts. Copy its generic
`blackbox.yml` to `/share/blackbox_exporter/blackbox.yml` on HA.
The exporter address is configured once in `prometheus.yml`, shared by the
probe and exporter scrape jobs. Restrict its unauthenticated TCP 9115 API to
trusted monitoring clients; do not expose it to the Internet.

Prometheus discovers MetalLB-allocated LoadBalancer services and probes every
TCP port from HA through the router. VIPs and ports come from Kubernetes, not
a static inventory. The current IPv4 services are supported; only the first
IPv4 VIP is probed if a service has multiple ingress addresses.
Scraping HA's direct LAN address is independent of MetalLB. UDP, application
semantics and mTLS authentication are not verified by TCP probes.
`up` means the exporter answered; `probe_success` means the connection worked.

The `metallb-pods` job includes the separate FRR-K8s controller and BGP exporter.
Graph `frrk8s_bgp_session_up`, `frrk8s_bgp_announced_prefixes_total` (a gauge,
despite its name), and `metallb_speaker_announced` alongside the external probes.
Traefik's existing request/latency metrics and JSON access logs show requests
that reach HTTP ingress; its configured access log currently keeps only HTTP
errors. Neither HTTP logs nor BGP session health show packets dropped before
Traefik.

During an outage, preserve evidence before restarting speakers:

1. On OPNsense compare `vtysh -c 'show bgp ipv4 unicast <VIP>/32'`,
   `vtysh -c 'show ip route <VIP>/32'`, `route -n get <VIP>` and `arp -an`.
   Established sessions do not prove the kernel FIB matches the BGP RIB.
2. Compare the selected next hop with ready local EndpointSlices and
   `metallb_speaker_announced`. Local-policy services must not route to nodes
   without a ready local endpoint. Check FRRNodeState reload/conversion results
   and actual advertisements using `vtysh` in the **FRR-K8s** pod, not the speaker.
3. Capture the same external TCP attempt on the router, selected node and
   endpoint. SYN missing at the node points upstream; arriving at the node but
   not the endpoint points to service forwarding; missing replies require
   return-route, reverse-path filter and firewall-state investigation.
   Compare a manually discovered NodePort on a node with a local endpoint.
   Standard Prometheus service discovery does not expose NodePort fields, so
   no static NodePort controls are installed.

The supplied router export shows graceful restart enabled, no explicit eBGP
multipath limit, inconsistent neighbor source settings and kernel redistribution.
These warrant review, not a root-cause claim. The live RIB/FIB during failure
is still needed. Normalize peer sources to a stable address matching BGPPeer;
review redistribution and graceful restart if evidence shows stale paths.
Enable ECMP only after verifying all next hops: it is not a health check.
Do not automate restarts or tune BFD to mask a still-unidentified forwarding fault.

## Non-K3s reboot monitoring

Ansible exports `node_reboot_required` through the node-exporter textfile
collector on non-K3s Debian compute/storage hosts every minute: `1` when
`/run/reboot-required` exists, otherwise `0`. The `netbox-devices` scrape job
discovers active devices via NetBox and retains all metrics, including this gauge.
Hosts must already be registered for node-exporter discovery in NetBox.

`NodeRebootRequired` in `_alerts/node-exporter.yaml` evaluates
`node_reboot_required == 1` per host with `for: 24h`. It uses `severity: warning`
and `notify: todoist email-tom`, matching the existing Kured reboot alert's
routing. A zero or stale metric clears the alert and resets its pending timer;
missing metrics do not indicate a healthy host (the existing `Node down` rule
handles unreachable exporters). The existing Kured `RebootRequired` alert is
unchanged.

## NAS Restic integrity checks

`ShareIntegrity` in `_alerts/nas.yaml` monitors the scheduled NAS Restic checks.
Ansible installs `b2_check_expected{share,bucket_name}=1` independently of check
results for each backup-enabled repository (currently Photos, Docs, Mel, Tom,
Archive, Jellyfin, Prometheus and WebDAV in `brickyard-woodlandpark-restic`).
Each run atomically replaces its result textfile with either
`b2_check_completed` (Unix timestamp of success) or `b2_check_failed` (Unix
timestamp of failure), never both.

Checks run weekly on Sunday at 02:00 with up to 30 minutes of jitter, share the
backup lock and read a rotating quarter of repository data. The alerts are:

| Alert | Condition |
| --- | --- |
| Share Integrity Check Failed | A positive failure timestamp remains present. |
| Share Integrity Check Overdue | The success timestamp is more than 8 days old. |
| Share Integrity Check Missing | An expected repository has neither result, including before its first run. |

All three wait 10 minutes and use `severity: high` and `notify: todoist email-tom`.
They match on `netbox_device_name`, `share` and `bucket_name`, aggregating away
scrape-specific labels, and require a healthy node-exporter target using the
existing NetBox host and port-9100 discovery pattern. An exporter outage or
removed target is covered by the existing `Node down` / `NAS Maintenance Target
Missing` alerts instead. A later success clears a failure; a failed-only result
raises the failure alert, not the missing or overdue alert. Missing-result
detection depends on the independently installed expectation metric.

## Ansible run freshness

`tpaulus/ansible`'s `site.yml` ends by writing
`ansible_last_run_timestamp_seconds` (Unix time of the last successful run) to
the node-exporter textfile directory on every inventory host.
`AnsibleRunStale` in `_alerts/ansible-runner.yaml` fires per
`netbox_device_name` when that timestamp is more than seven days old for
10 minutes, using `severity: warning` and `notify: todoist email-tom`. The
runner's schedule leaves at most about six days between runs. Hosts that have
never published the metric, or whose exporter is down, do not raise this alert;
the existing `Node down` rule covers unreachable exporters.
