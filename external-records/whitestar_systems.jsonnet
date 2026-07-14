// DNS records for whitestar.systems
// Ported from terraform-cloudflare/whitestar_systems.tf
//
// NOTE: The following record groups are intentionally omitted here because
// they are sourced from Netbox and will be managed by a dedicated Netbox→DNSRecord
// sync job (see problem statement for details):
//   - *.brickyard.whitestar.systems  (brickyard host IPs)
//   - *.brickyard.ipmi.whitestar.systems  (IPMI management IPs)
//   - k3s.brickyard.whitestar.systems  (k3s primary node IPs)
local ep = import 'lib/dns_endpoint.libsonnet';
local cfEmailRouting = import 'lib/cloudflare_email_routing.libsonnet';

local zone = 'whitestar.systems';
local namespace = 'external-records';

ep.new('whitestar-systems', namespace,
  cfEmailRouting.endpoints(zone, allowedSenders=['include:amazonses.com'])
  +
  [
    // Keybase domain verification
    ep.endpoint(zone, 'TXT', ['keybase-site-verification=ZMKzMIfHqDIUV4SrGSCCRP09C0TSada5zNxdosjudGA']),
    // GitHub organisation domain verification
    ep.endpoint('_github-challenge-ws-systems-org.' + zone, 'TXT', ['5a889d68b4']),
    // DMARC
    ep.endpoint('_dmarc.' + zone, 'TXT', ['v=DMARC1; p=quarantine; rua=mailto:64203f8a3e304420b20686d30874ffc9@dmarc-reports.cloudflare.net']),
    // UniFi controller alias
    ep.endpoint('ubnt.brickyard.' + zone, 'CNAME', ['unifi-controller.brickyard.' + zone], ttl=30),
    // K3s ingress wildcard (MetalLB VIP)
    ep.endpoint('*.ing.k3s.brickyard.' + zone, 'A', ['10.30.0.0']),
    // K3s auth-ingress wildcard via Cloudflare Tunnel (proxied)
    ep.endpoint('*.auth-ing.k3s.brickyard.' + zone, 'CNAME', ['6bd25c6e-9222-43e6-bdb3-f989da6cbdb2.cfargotunnel.com'], providerSpecific=ep.cloudflareProxied),
  ]
)
