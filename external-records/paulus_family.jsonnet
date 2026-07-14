// DNS records for paulus.family
// Ported from terraform-cloudflare/paulus_family.tf
local ep = import 'lib/dns_endpoint.libsonnet';
local fastmail = import 'lib/fastmail.libsonnet';

local zone = 'paulus.family';
local namespace = 'external-records';

ep.new('paulus-family', namespace,
  fastmail.endpoints(
    zone,
    dmarcReportAddress='mailto:d6b6ea49728e40aabe6f5d3b65646b12@dmarc-reports.cloudflare.net',
    allowedSenders=['include:spf.mtasv.net'],
    createWildcardMxRecords=true,
    createClientConfigurationRecords=false,
  )
  +
  [
    // Postmark DKIM key
    ep.endpoint('20240619041211pm._domainkey.' + zone, 'TXT', ['k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDNQxj6/H4/+X1gbz0khrP5c+LI7JMZNW/FC4laAJsuLThYh48ENFDH/6lW5MmjDdQcERbDYF6qm9bLmUjZzKkrXRQsPigf9+VSufKE4OU5QeT8zGZ/JdDKfHQLvIT6rqXgmPTd/7/SADQ6NSZSBN5NP30/z85EcEEJGzhD4FypVwIDAQAB']),
    // Postmark bounce handling CNAME
    ep.endpoint('pm-bounces.' + zone, 'CNAME', ['pm.mtasv.net']),
    // Paperless-ngx via Cloudflare Tunnel (proxied)
    ep.endpoint('paperless.' + zone, 'CNAME', ['paperless.auth-ing.k3s.brickyard.whitestar.systems'], providerSpecific=ep.cloudflareProxied),
  ]
)
