// DNS records for paulusfamily.org
// Ported from terraform-cloudflare/paulusfamily_org.tf
local ep = import 'lib/dns_endpoint.libsonnet';
local fastmail = import 'lib/fastmail.libsonnet';

local zone = 'paulusfamily.org';
local namespace = 'external-records';

ep.new('paulusfamily-org', namespace,
  fastmail.endpoints(
    zone,
    dmarcReportAddress='mailto:d0be62b94fa648a59381e4712859e610@dmarc-reports.cloudflare.net',
    createWildcardMxRecords=true,
    createClientConfigurationRecords=false,
  )
)
