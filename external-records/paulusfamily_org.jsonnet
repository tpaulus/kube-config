// DNS records for paulusfamily.org
// Ported from terraform-cloudflare/paulusfamily_org.tf
local ep = import 'lib/dns_endpoint.libsonnet';
local fastmail = import 'lib/fastmail.libsonnet';

local zone = 'paulusfamily.org';
local namespace = 'external-records';

ep.new('paulusfamily-org', namespace,
  fastmail.endpoints(
    zone,
    createWildcardMxRecords=true,
    createClientConfigurationRecords=false,
  )
)
