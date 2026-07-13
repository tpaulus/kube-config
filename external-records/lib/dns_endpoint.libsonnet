// Helper functions for creating externaldns.k8s.io/v1alpha1 DNSEndpoint resources.
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
      endpoints: endpoints,
    },
  },

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
    { name: 'external-dns.alpha.kubernetes.io/cloudflare-proxied', value: 'true' },
  ],
}
