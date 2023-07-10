
@description('Required. Name of the api app.')
@maxLength(60)
param name string 

@description('TODO')
param serviceName string = 'api'

@description('Optional. Location for all resources.')
param location string

@description('Resource tags that we might need to add to all resources (i.e. Environment, Cost center, application name etc)')
param tags object

@description('Required. The resource ID of the app service plan to use for the site.')
param serverFarmResourceId string

@description('Resource ID of the app insight to leverage for this resource.')
param appInsightId string = ''

@description('Default is empty. If empty no Private Endpoint will be created for the resoure. Otherwise, the subnet where the private endpoint will be attached to')
param subnetPrivateEndpointId string = ''

@description('Optional. Array of custom objects describing vNet links of the DNS zone. Each object should contain vnetName, vnetId, registrationEnabled')
param virtualNetworkLinks array = []

@description('if empty, private dns zone will be deployed in the current RG scope')
param vnetHubResourceId string

@description('Kind of server OS of the App Service Plan')
@allowed([ 'Windows', 'Linux'])
param webAppBaseOs string = 'Linux'

@description('An existing Log Analytics WS Id for creating app Insights, diagnostics etc.')
param logAnalyticsWsId string

@description('The subnet ID that is dedicated to Web Server, for Vnet Injection of the web app')
param subnetIdForVnetInjection string

@description('The name of an existing keyvault, that it will be used to store secrets (connection string)' )
param keyvaultName string

@description('TODO')
param enableOryxBuild bool = contains(webAppBaseOs, 'Linux')

@description('TODO')
param appSettings object = {}

@description('TODO')
param scmDoBuildDuringDeployment bool = false

@description('TODO: Add description')
param appSvcUserAssignedManagedIdenityName string

var vnetHubSplitTokens = !empty(vnetHubResourceId) ? split(vnetHubResourceId, '/') : array('')

var apiAppDnsZoneName = 'privatelink.azurewebsites.net'

var appSettingsExtra = union(appSettings,
      {
        SCM_DO_BUILD_DURING_DEPLOYMENT: string(scmDoBuildDuringDeployment)
        ENABLE_ORYX_BUILD: string(enableOryxBuild)
        AZURE_CLIENT_ID: muai.properties.clientId
      },
      !empty(keyvaultName) ? { AZURE_KEY_VAULT_ENDPOINT: keyvault.properties.vaultUri } : {})


//!empty(redisConnectionStringSecretName) ? {redisConnectionStringSecret: '@Microsoft.KeyVault(VaultName=${keyvaultName};SecretName=${redisConnectionStringSecretName})'} : {}

resource keyvault 'Microsoft.KeyVault/vaults@2022-11-01' existing = {
  name: keyvaultName
}

resource muai 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: appSvcUserAssignedManagedIdenityName
}


module apiApp '../core/app-services/app-svc.bicep' = {
  name: take('${name}-apiApp-Deployment', 64)
  params: {
    kind: (webAppBaseOs =~ 'linux') ? 'app,linux' : 'app'
    name:  name
    location: location
    tags: union(tags, { 'azd-service-name': serviceName })
    serverFarmResourceId: serverFarmResourceId
    diagnosticWorkspaceId: logAnalyticsWsId   
    virtualNetworkSubnetId: subnetIdForVnetInjection
    appInsightId: appInsightId
    siteConfigSelection:  (webAppBaseOs =~ 'linux') ? 'linuxNet6' : 'windowsNet6'
    hasPrivateLink: (!empty (subnetPrivateEndpointId))
    systemAssignedIdentity: false
    userAssignedIdentities:  {
      '${muai.id}': {}
    }
    appSettingsKeyValuePairs: appSettingsExtra // union(redisConnStr, sqlConnStr)
  }
}

module apiAppPrivateDnsZone '../core/networking/private-dns-zone.bicep' = if ( !empty(subnetPrivateEndpointId) ) {
  // conditional scope is not working: https://github.com/Azure/bicep/issues/7367
  //scope: empty(vnetHubResourceId) ? resourceGroup() : resourceGroup(vnetHubSplitTokens[2], vnetHubSplitTokens[4]) 
  scope: resourceGroup(vnetHubSplitTokens[2], vnetHubSplitTokens[4])
  name: take('${replace(apiAppDnsZoneName, '.', '-')}-PrivateDnsZoneDeployment', 64)
  params: {
    name: apiAppDnsZoneName
    virtualNetworkLinks: virtualNetworkLinks
    tags: tags
  }
}

module peapiApp '../core/networking/private-endpoint.bicep' = if ( !empty(subnetPrivateEndpointId) ) {
  name:  take('pe-${name}-Deployment', 64)
  params: {
    name: take('pe-${apiApp.outputs.name}', 64)
    location: location
    tags: tags
    privateDnsZonesId: apiAppPrivateDnsZone.outputs.privateDnsZonesId
    privateLinkServiceId: apiApp.outputs.resourceId
    snetId: subnetPrivateEndpointId
    subresource: 'sites'
  }
}


module apiAppIdentityOnKeyvaultSecretsUser '../core/role-assignments/role-assignment.bicep' = {
  name: 'apiAppSystemIdentityOnKeyvaultSecretsUser-Deployment'
  params: {
    name: 'ra-apiAppSystemIdentityOnKeyvaultSecretsUser'
    principalId: muai.properties.principalId
    resourceId: keyvault.id
    roleDefinitionId: '4633458b-17de-408a-b874-0445c86b69e6'  //Key Vault Secrets User  
  }
}


output apiAppName string = apiApp.outputs.name
output apiAppHostName string = apiApp.outputs.defaultHostname
output apiAppResourceId string = apiApp.outputs.resourceId
output apiAppLocation string = apiApp.outputs.location
output apiAppSystemAssignedPrincipalId string = apiApp.outputs.systemAssignedPrincipalId
output apiAppUri string = 'https://${apiApp.outputs.defaultHostname}'
