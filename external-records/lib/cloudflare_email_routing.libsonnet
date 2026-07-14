// Generates DNSEndpoint spec.endpoints for Cloudflare Email Routing.
// Mirrors the terraform-cloudflare //modules/cloudflare_email_routing module.
local ep = import 'dns_endpoint.libsonnet';

local mxServers = [
  { name: 'isaac.mx.cloudflare.net', priority: 41 },
  { name: 'linda.mx.cloudflare.net', priority: 57 },
  { name: 'amir.mx.cloudflare.net', priority: 6 },
];

{
  endpoints(zone, allowedSenders=[]):: (
    // MX records
    [ep.endpoint(zone, 'MX', ['%d %s' % [s.priority, s.name] for s in mxServers], ttl=1)]
    +
    // SPF TXT record
    [ep.endpoint(zone, 'TXT', [
      'v=spf1 ' + std.join(' ', ['include:_spf.mx.cloudflare.net'] + allowedSenders) + ' -all',
    ])]
  ),
}
