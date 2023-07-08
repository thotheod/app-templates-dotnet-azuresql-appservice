
@description('Required. Name of the SQL Server.')
@maxLength(60)
param sqlServerName string 

@description('Required. The name of the existing keyvault.')
param keyVaultName string

@description('Required. The name of the keyvault secret that will hold the connection string.')
param connectionStringKey string

@description('Optional. Location for all resources.')
param location string

@description('Resource tags that we might need to add to all resources (i.e. Environment, Cost center, application name etc)')
param tags object

// database related params
@description('Required. The name of the Sql database.')
param databaseName string

@description('Optional, default SQL_Latin1_General_CP1_CI_AS. The collation of the database.')
param databaseCollation string = 'SQL_Latin1_General_CP1_CI_AS'

@description('Optional, default is S0. The SKU of the database ')
@allowed([
  'S0'
  'S1'
  'S2'
  'S3'
  'S4'
  'S6'
  'S7'
  'S9'
  'S12'
])
param databaseSkuName string = 'S0'



resource sqlServer 'Microsoft.Sql/servers@2022-11-01-preview' existing = {
  name: sqlServerName  
}

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
}

// NOTE: For this connection string to work we need to run the following command in the database after deployment
// drop user [webAppManagedIdentity]
// CREATE USER [webAppManagedIdentity] FROM EXTERNAL PROVIDER;
// ALTER ROLE db_datareader ADD MEMBER [webAppManagedIdentity];
// ALTER ROLE db_datawriter ADD MEMBER [webAppManagedIdentity];
// ALTER ROLE db_ddladmin ADD MEMBER [webAppManagedIdentity];
// GO
// OR .....give it DB OWNER role
// ALTER ROLE db_owner ADD MEMBER [webAppManagedIdentity];
// SEE MORE https://learn.microsoft.com/en-us/samples/azure-samples/azure-sql-db-who-am-i/azure-sql-db-passwordless-connections/
resource sqlAzureConnectionStringSercret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVault
  name: connectionStringKey
  properties: {
    value: 'Server=${sqlServerName}${environment().suffixes.sqlServerHostname};Authentication=Active Directory Default;Database=${databaseName};'
    // Server=tcp:sql-5w5yk3pw3wgfm.database.windows.net,1433;Initial Catalog=SchoolContext;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;Authentication="Active Directory Default";
    // Server=sql-5w5yk3pw3wgfm.database.windows.net; Database=SchoolContext; User=appUser; Password=dDPDfo3T3Vf9x80
  }
}



resource database 'Microsoft.Sql/servers/databases@2021-02-01-preview' = {
  parent: sqlServer
  name: databaseName
  location: location
  tags: tags
  sku: {
    name: databaseSkuName
  }
  properties: {
    collation: databaseCollation
  }
}
