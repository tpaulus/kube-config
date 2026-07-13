// DNS records for tompaulus.com
// Ported from terraform-cloudflare/tompaulus_com.tf
local ep = import 'lib/dns_endpoint.libsonnet';
local fastmail = import 'lib/fastmail.libsonnet';
local sesDns = import 'lib/ses_dns.libsonnet';

local zone = 'tompaulus.com';
local namespace = 'external-records';

ep.new('tompaulus-com', namespace,
  fastmail.endpoints(
    zone,
    dmarcReportAddress='mailto:3f08cb85c9d54864871c1d8351cf31e6@dmarc-reports.cloudflare.net',
    allowedSenders=['include:amazonses.com'],
    createWildcardMxRecords=true,
    createClientConfigurationRecords=true,
  )
  +
  sesDns.endpoints(
    zone,
    dkimIds=[
      '2gdibe3uaozthsp3q7qytnf3umkkjkkd',
      '63ilntu2hvaqbeoiq4d5jbqxhnuqhkjh',
      'bhjfun4cius7vyvqhmsf7xpbtbxszem4',
      'mslyrhhosvow7b5z5vsnys4kztl2jcrq',
      'uqkwjnfnzjdopfoutf3ih4pwqihrfhsf',
      'wwilycvdedvkqqwnnl25cxjp3bakkxxy',
    ],
    txtVerification=[
      'nhnRt/X9SkDn/5ASMYURGpGaUEPBo0u/9daGoCa5zxU=',
      'A/J5kW0VuiyGR3Y1MdsnMQYq4yujQHGqzbsO7jwow9Y=',
    ],
  )
  +
  [
    // Keybase domain verification
    ep.endpoint(zone, 'TXT', ['keybase-site-verification=ANVrHna38pR4HiCmhXorD3QPw0bqpsqIGKtDvNLTtwA']),
    // Apex CNAME to Cloudflare Pages (proxied)
    ep.endpoint(zone, 'CNAME', ['tom-www.pages.dev'], providerSpecific=ep.cloudflareProxied),
    // WWW CNAME (proxied)
    ep.endpoint('www.' + zone, 'CNAME', [zone], providerSpecific=ep.cloudflareProxied),
  ]
)
