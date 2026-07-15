// Helper functions for creating externaldns.k8s.io/v1alpha1 DNSEndpoint resources.
local contains(values, value) =
  std.length([candidate for candidate in values if candidate == value]) > 0;

local endpointKey(endpoint) =
  endpoint.dnsName + '|' + endpoint.recordType;

local uniqueValues(values, seen=[]) =
  if std.length(values) == 0 then
    seen
  else
    uniqueValues(
      values[1:],
      if contains(seen, values[0]) then seen else seen + [values[0]]
    );

local uniqueEndpointKeys(endpoints, seen=[]) =
  if std.length(endpoints) == 0 then
    seen
  else
    local key = endpointKey(endpoints[0]);
    uniqueEndpointKeys(
      endpoints[1:],
      if contains(seen, key) then seen else seen + [key]
    );

local coalesceEndpoints(endpoints) = [
  (
    local matching = [endpoint for endpoint in endpoints if endpointKey(endpoint) == key];
    local representative = matching[0];
    assert std.length([
      endpoint
      for endpoint in matching
      if endpoint.recordTTL != representative.recordTTL
    ]) == 0 : 'Cannot coalesce endpoints for %s with different recordTTL values' % key;
    assert std.length([
      endpoint
      for endpoint in matching
      if std.objectHas(endpoint, 'providerSpecific') != std.objectHas(representative, 'providerSpecific') ||
         (std.objectHas(endpoint, 'providerSpecific') && endpoint.providerSpecific != representative.providerSpecific)
    ]) == 0 : 'Cannot coalesce endpoints for %s with different providerSpecific values' % key;
    representative {
      targets: uniqueValues(std.flattenArrays([endpoint.targets for endpoint in matching])),
    }
  )
  for key in uniqueEndpointKeys(endpoints)
];

{
  // Create a DNSEndpoint resource from a name, namespace, and list of endpoint objects.
  new(name, namespace, endpoints):: {
    apiVersion: 'externaldns.k8s.io/v1alpha1',
    kind: 'DNSEndpoint',
    metadata: {
      name: name,
      namespace: namespace,
    },
    spec: {
      endpoints: coalesceEndpoints(endpoints),
    },
  },

  // Merge duplicate endpoint objects into one record set per dnsName + recordType.
  coalesce(endpoints):: coalesceEndpoints(endpoints),

  // Build a single endpoint entry for use in spec.endpoints.
  // providerSpecific is an optional array of {name, value} objects.
  endpoint(dnsName, recordType, targets, ttl=300, providerSpecific=[])::
    {
      dnsName: dnsName,
      recordType: recordType,
      targets: targets,
      recordTTL: ttl,
    }
    + if std.length(providerSpecific) > 0 then { providerSpecific: providerSpecific } else {},

  // providerSpecific entry to enable Cloudflare orange-cloud proxying.
  cloudflareProxied:: [
    { name: 'external-dns.kubernetes.io/cloudflare-proxied', value: 'true' },
  ],
}
