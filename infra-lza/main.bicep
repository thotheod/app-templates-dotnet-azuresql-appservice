targetScope = 'subscription'

// ================ //
// Parameters       //
// ================ //
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
@minLength(1)
@maxLength(64)
param environmentName string

@description('Primary location for all resources')
@minLength(1)
param location string

@description('TODO: Add description')
param applicationInsightsName string

@description('TODO: Add description')
param logAnalyticsWsName string

@description('TODO: Add description')
param appServicePlanName string 

@description('TODO: Add description')
param keyVaultName string

@description('TODO: Add description')
param afdName string 

@description('TODO: Add description')
param wafPolicyName string 

@description('TODO: Add description')
param resourceGroupName string

@description('TODO: Add description')
param appSvcUserAssignedManagedIdenityName string

@description('The subnet ID that is dedicated to Web Server, for Vnet Injection of the web app')
param subnetIdForVnetInjection string

@description('Default is empty. If empty no Private Endpoint will be created for the resoure. Otherwise, the subnet where the private endpoint will be attached to')
param subnetPrivateEndpointId string = ''

@description('Resource ID of the vnet in Hub RG')
param vnetHubResourceId string

@description('the name of the SQL Server deployed by the LZA template')
param sqlServerName string = ''

@description('Default name for the SQL Database')
param sqlDatabaseName string = 'SchoolContext'

@description('the name of the identity with Contributor Role that will run the Auto Approval of the AFD PE')
param idAfdPeAutoApproverName string

// @description('SQL Server administrator password')
// @secure()
// param sqlAdminPassword string

// @description('Application user password')
// @secure()
// param appUserPassword string


// ================ //
// Variables        //
// ================ //

var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }
var uniqueIdShort = take(resourceToken, 5)
var contosoWebAppName = 'contoso-webapp-${uniqueIdShort}'
var contosoApiAppName = 'contoso-apiapp-${uniqueIdShort}'
var sqlDbConnectionStringKey = 'AZURE-SQL-CONNECTION-STRING'

// 'Telemetry is by default enabled. The software may collect information about you and your use of the software and send it to Microsoft. Microsoft may use this information to provide services and improve our products and services.
var enableTelemetry = true 

var afdContosoWebEndPointName = 'contosoWeb-${ uniqueIdShort}' 



// ================ //
// Resources        //
// ================ //

// need referece to exisitng RG to deploy the rest of the resources
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' existing = {
  scope: rg
  name: appServicePlanName
}

// resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01'  existing = {
//   scope: rg
//   name: keyVaultName
// }

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  scope: rg
  name: applicationInsightsName
}

resource laws 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  scope: rg
  name: logAnalyticsWsName
}

// resource muai 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
//   scope: rg
//   name: appSvcUserAssignedManagedIdenityName
// }

module webApp 'modules/web-app.module.bicep' = {
  scope: rg
  name: 'contoso-webapp-deployment'
  params: {
    appSvcUserAssignedManagedIdenityName: appSvcUserAssignedManagedIdenityName
    keyvaultName: keyVaultName
    location: location
    logAnalyticsWsId: laws.id
    name: contosoWebAppName
    serverFarmResourceId: appServicePlan.id
    subnetIdForVnetInjection: subnetIdForVnetInjection
    tags: tags
    vnetHubResourceId: vnetHubResourceId
    appSettings: {
      URLAPI: apiApp.outputs.apiAppUri  
    }
    appInsightId: appInsights.id
    subnetPrivateEndpointId: subnetPrivateEndpointId
  }
}

module afd 'modules/afd.module.bicep' = {
  scope: rg
  name: take ('AzureFrontDoor-NewOrigin-deployment', 64)
  params: {
    afdName: afdName
    endpointName: afdContosoWebEndPointName
    originGroupName: afdContosoWebEndPointName
    origins: [
      {
          name: webApp.outputs.webAppName  //1-50 Alphanumerics and hyphens
          hostname: webApp.outputs.webAppHostName
          enabledState: true
          privateLinkOrigin: {
            privateEndpointResourceId: webApp.outputs.webAppResourceId
            privateLinkResourceType: 'sites'
            privateEndpointLocation: webApp.outputs.webAppLocation
          }
      }
    ]
    wafPolicyName: wafPolicyName
  }
}

module autoApproveAfdPe 'modules/approve-afd-pe.module.bicep' = {
  scope: rg
  name: take ('autoApproveAfdPe-deployment', 64)
  params: { 
    location: location 
    idAfdPeAutoApproverName: idAfdPeAutoApproverName   
  }
  dependsOn: [
    afd
  ]
}

module apiApp 'modules/api-app.module.bicep' = {
  scope: rg
  name: 'contoso-apiapp-deployment'
  params: {
    appSvcUserAssignedManagedIdenityName: appSvcUserAssignedManagedIdenityName
    keyvaultName: keyVaultName
    location: location
    logAnalyticsWsId: laws.id
    name: contosoApiAppName
    serverFarmResourceId: appServicePlan.id
    subnetIdForVnetInjection: subnetIdForVnetInjection
    tags: tags
    vnetHubResourceId: vnetHubResourceId
    appSettings: {
      AZURE_SQL_CONNECTION_STRING_KEY: sqlDbConnectionStringKey
    }
    appInsightId: appInsights.id
    subnetPrivateEndpointId: subnetPrivateEndpointId
  }
}

module sqlDb 'modules/sql-db.module.bicep' = {
  scope: rg
  name: 'contoso-sqlDb-deployment'
  params: {
    databaseName: sqlDatabaseName
    location: location    
    tags: tags  
    sqlServerName: sqlServerName  
    connectionStringKey: sqlDbConnectionStringKey 
    keyVaultName: keyVaultName
  }
}

//  Telemetry Deployment
@description('Enable usage and telemetry feedback to Microsoft.')
var telemetryId = '69ef933a-eff0-450b-8a46-331cf62e160f-NETWEB-${location}'

resource telemetrydeployment 'Microsoft.Resources/deployments@2021-04-01' = if (enableTelemetry) {
  name: telemetryId
  location: location
  properties: {
    mode: 'Incremental'
    template: {
      '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
      contentVersion: '1.0.0.0'
      resources: {}
    }
  }
}
