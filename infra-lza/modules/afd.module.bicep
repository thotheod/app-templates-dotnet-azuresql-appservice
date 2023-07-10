@description('Required. Name of the AFD profile.')
param afdName string

@description('Name of the endpoint under the profile which is unique globally.')
param endpointName string 

@allowed([
  'Enabled'
  'Disabled'
])
@description('AFD Endpoint State')
param endpointEnabled string = 'Enabled'

@description('The name of the Origin Group')
param originGroupName string 

@description('Origin List')
param origins array 

@description('Optional, default value false. Set true if you need to cache content at the AFD level')
param enableCaching bool = false

@description('Name of the WAF policy to create.')
@maxLength(128)
param wafPolicyName string


// Create an Array of all Endpoint which includes customDomain Id and afdEndpoint Id
// This array is needed to be attached to Microsoft.Cdn/profiles/securitypolicies
// var customDomainIds = [for (domain, index) in customDomains: {id: custom_domains[index].id}]
// var afdEndpointIds = [{id: endpoint.id}]
// var endPointIdsForWaf = union(customDomainIds, afdEndpointIds)
var endPointIdsForWaf = [{id: endpoint.id}]

@description('Default Content to compress')
var contentTypeCompressionList = [
  'application/eot'
  'application/font'
  'application/font-sfnt'
  'application/javascript'
  'application/json'
  'application/opentype'
  'application/otf'
  'application/pkcs7-mime'
  'application/truetype'
  'application/ttf'
  'application/vnd.ms-fontobject'
  'application/xhtml+xml'
  'application/xml'
  'application/xml+rss'
  'application/x-font-opentype'
  'application/x-font-truetype'
  'application/x-font-ttf'
  'application/x-httpd-cgi'
  'application/x-javascript'
  'application/x-mpegurl'
  'application/x-opentype'
  'application/x-otf'
  'application/x-perl'
  'application/x-ttf'
  'font/eot'
  'font/ttf'
  'font/otf'
  'font/opentype'
  'image/svg+xml'
  'text/css'
  'text/csv'
  'text/html'
  'text/javascript'
  'text/js'
  'text/plain'
  'text/richtext'
  'text/tab-separated-values'
  'text/xml'
  'text/x-script'
  'text/x-component'
  'text/x-java-source'
]



resource profile 'Microsoft.Cdn/profiles@2022-11-01-preview' existing = {
  name: afdName  
}


resource waf 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2022-05-01' existing =  {
  name: wafPolicyName 
}

resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2022-11-01-preview' = {
  parent: profile
  name: endpointName
  location: 'Global'
  properties: {
    enabledState: endpointEnabled
  }
}
resource originGroup 'Microsoft.Cdn/profiles/originGroups@2022-11-01-preview' =  {
  parent: profile
  name: originGroupName
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/'
      probeRequestType: 'GET'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 100
    }
    sessionAffinityState: 'Disabled'
    trafficRestorationTimeToHealedOrNewEndpointsInMinutes: 10
  }
}

@description('For a description of the sharedPrivateLinkResource type look the above comment')
resource afdOrigins 'Microsoft.Cdn/profiles/originGroups/origins@2022-11-01-preview' = [for (origin, index) in origins: {
  parent: originGroup
  name: replace(origin.hostname, '.', '-')
  properties: {
    hostName: origin.hostname
    httpPort: 80
    httpsPort: 443
    originHostHeader: origin.hostname
    priority: 1
    weight: 1000
    enabledState: origin.enabledState ? 'Enabled' : 'Disabled'
    enforceCertificateNameCheck: true
    sharedPrivateLinkResource: empty(origin.privateLinkOrigin) ? null : {
      privateLink: {
        id: origin.privateLinkOrigin.privateEndpointResourceId
      }
      groupId: (origin.privateLinkOrigin.privateLinkResourceType != '') ? origin.privateLinkOrigin.privateLinkResourceType : null
      privateLinkLocation: origin.privateLinkOrigin.privateEndpointLocation
      requestMessage: 'Please approve this connection.'
    }
  }
}]

resource originRoute 'Microsoft.Cdn/profiles/afdendpoints/routes@2021-06-01' =  {
  parent: endpoint
  name: '${originGroup.name}-route'
  properties: {
    cacheConfiguration: !enableCaching ? null :  {
      compressionSettings: {
        isCompressionEnabled: true
        contentTypesToCompress: contentTypeCompressionList
      }
      queryStringCachingBehavior: 'UseQueryString'
    }
    // customDomains: [ for (domain, cid) in customDomains: {
    //   id: custom_domains[cid].id
    // }]
    customDomains: []
    originGroup: {
      id: originGroup.id
    }
    // ruleSets: routeRuleSets
    supportedProtocols: [
      'Https'
      'Http'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
  }
  dependsOn: [
    afdOrigins
  ]
}

resource afdWafSecurityPolicy 'Microsoft.Cdn/profiles/securitypolicies@2022-11-01-preview' =  {
  parent: profile
  name: 'afdWafSecurityPolicy'
  properties: {
    parameters: {
      wafPolicy: {
        id:  waf.id
      }
      associations: [
        {
          domains: endPointIdsForWaf
          patternsToMatch: [
            '/*'
          ]
        }
      ]
      type: 'WebApplicationFirewall'
    }
  }
}


@description('The name of the CDN profile.')
output afdProfileName string = profile.name

@description('The resource ID of the CDN profile.')
output afdProfileId string = profile.id

@description('Name of the endpoint.')
output endpointName string = endpoint.name

@description('HostName of the endpoint.')
output afdEndpointHostName string = endpoint.properties.hostName

@description('The resource group where the CDN profile is deployed.')
output resourceGroupName string = resourceGroup().name

@description('The type of the CDN profile.')
output profileType string = profile.type
