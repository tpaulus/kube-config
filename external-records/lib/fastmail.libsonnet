// Generates DNSEndpoint spec.endpoints for a Fastmail-hosted domain.
// Mirrors the terraform-cloudflare //modules/fastmail module.
local ep = import 'dns_endpoint.libsonnet';

local mxServers = [
  { name: 'in1-smtp.messagingengine.com', priority: 10 },
  { name: 'in2-smtp.messagingengine.com', priority: 20 },
];

{
  endpoints(
    zone,
    dmarcReportAddress='mailto:dmarcreports@whitestar.systems',
    allowedSenders=[],
    createWildcardMxRecords=false,
    createClientConfigurationRecords=false,
  ):: (
    // MX records
    [ep.endpoint(zone, 'MX', ['%d %s' % [s.priority, s.name] for s in mxServers], ttl=86400)]
    +
    // Optional wildcard MX records
    (if createWildcardMxRecords then
      [ep.endpoint('*.' + zone, 'MX', ['%d %s' % [s.priority, s.name] for s in mxServers], ttl=86400)]
    else [])
    +
    // DKIM CNAME records (mesmtp + fm1..fm3)
    [ep.endpoint('mesmtp._domainkey.' + zone, 'CNAME', ['mesmtp.' + zone + '.dkim.fmhosted.com'])]
    +
    [
      ep.endpoint('fm%d._domainkey.%s' % [i, zone], 'CNAME', ['fm%d.%s.dkim.fmhosted.com' % [i, zone]])
      for i in [1, 2, 3]
    ]
    +
    // DMARC TXT record
    [ep.endpoint('_dmarc.' + zone, 'TXT', ['v=DMARC1; p=quarantine; rua=' + dmarcReportAddress])]
    +
    // SPF TXT record
    [ep.endpoint(zone, 'TXT', [
      'v=spf1 ' + std.join(' ', ['include:spf.messagingengine.com'] + allowedSenders) + ' -all',
    ])]
    +
    // Optional client auto-configuration SRV records
    (if createClientConfigurationRecords then [
      ep.endpoint('_submission._tcp.' + zone, 'SRV', ['0 1 587 smtp.fastmail.com']),
      ep.endpoint('_imap._tcp.' + zone, 'SRV', ['0 0 0 .']),
      ep.endpoint('_imaps._tcp.' + zone, 'SRV', ['0 1 993 imap.fastmail.com']),
      ep.endpoint('_pop3._tcp.' + zone, 'SRV', ['0 0 0 .']),
      ep.endpoint('_pop3s._tcp.' + zone, 'SRV', ['10 1 995 pop.fastmail.com']),
      ep.endpoint('_jmap._tcp.' + zone, 'SRV', ['0 1 443 api.fastmail.com']),
      ep.endpoint('_cardav._tcp.' + zone, 'SRV', ['0 0 0 .']),
      ep.endpoint('_carddavs._tcp.' + zone, 'SRV', ['0 1 443 carddav.fastmail.com']),
      ep.endpoint('_caldav._tcp.' + zone, 'SRV', ['0 0 0 .']),
      ep.endpoint('_caldavs._tcp.' + zone, 'SRV', ['0 1 443 caldav.fastmail.com']),
    ] else [])
  ),
}
