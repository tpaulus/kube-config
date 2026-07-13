// DNS records for runabout.space
// Ported from terraform-cloudflare/runabout_space.tf
local ep = import 'lib/dns_endpoint.libsonnet';
local fastmail = import 'lib/fastmail.libsonnet';

local zone = 'runabout.space';
local namespace = 'external-records';

ep.new('runabout-space', namespace,
  fastmail.endpoints(
    zone,
    dmarcReportAddress='mailto:58a029c6907a487e89a1bbc2830bf93d@dmarc-reports.cloudflare.net',
  )
  +
  [
    // Keybase domain verification
    ep.endpoint(zone, 'TXT', ['keybase-site-verification=RsL-7roB3x2Sv1GoI3MzZ8APh3Gt88CMBw_DTL1LKvk']),
  ]
)
