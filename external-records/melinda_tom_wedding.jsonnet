// DNS records for melinda-tom.wedding
// Ported from terraform-cloudflare/melinda_tom_wedding.tf
// Note: Cloudflare Rulesets (WAF, rate limiting, redirects) cannot be represented
// as standard DNS records and are not included here.
local ep = import 'lib/dns_endpoint.libsonnet';
local fastmail = import 'lib/fastmail.libsonnet';

local zone = 'melinda-tom.wedding';
local namespace = 'external-records';

ep.new('melinda-tom-wedding', namespace,
  fastmail.endpoints(
    zone,
    dmarcReportAddress='mailto:9782f98c803c4a17afc4d07788d2af87@dmarc-reports.cloudflare.net',
    allowedSenders=['include:amazonses.com'],
    createClientConfigurationRecords=false,
  )
  +
  [
    // WWW AAAA placeholder (proxied; required for Cloudflare redirect rule targeting www)
    ep.endpoint('www.' + zone, 'AAAA', ['100::'], providerSpecific=ep.cloudflareProxied),
    // Apex CNAME to Cloudflare Pages (proxied)
    ep.endpoint(zone, 'CNAME', ['melinda-tom-wedding.pages.dev'], providerSpecific=ep.cloudflareProxied),
  ]
)
