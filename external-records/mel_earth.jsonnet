// DNS records for mel.earth
// Ported from terraform-cloudflare/mel_earth.tf
local ep = import 'lib/dns_endpoint.libsonnet';
local fastmail = import 'lib/fastmail.libsonnet';

local zone = 'mel.earth';
local namespace = 'external-records';

ep.new('mel-earth', namespace,
  fastmail.endpoints(
    zone,
    dmarcReportAddress='mailto:f36e4edc4151420abb491d4495fc879c@dmarc-reports.cloudflare.net',
    createClientConfigurationRecords=true,
  )
)
