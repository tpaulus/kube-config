// Generates DNSEndpoint spec.endpoints for AWS SES domain verification.
// Mirrors the terraform-cloudflare //modules/ses_dns module.
local ep = import 'dns_endpoint.libsonnet';

{
  endpoints(zone, dkimIds, txtVerification):: (
    // SES DKIM CNAME records
    [
      ep.endpoint('%s._domainkey.%s' % [id, zone], 'CNAME', ['%s.dkim.amazonses.com' % id])
      for id in dkimIds
    ]
    +
    // SES domain verification TXT records (multiple values → multiple targets)
    [ep.endpoint('_amazonses.' + zone, 'TXT', txtVerification)]
  ),
}
