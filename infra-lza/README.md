# Select the deployment infrastructure of your choice
The current app template is *self-suffiecient*, in the sense that with a simple `azd up` command it will deploy all the ncessary Azure resources and the web applications. However, the azure resources are architected with *simplicity* in mind, since the main purpose of this Repo is to showcase how to how to use Entity Framework Core in an ASP.NET Core Razor Pages web app. Thus, the app are deployed to Microsoft's Azure cloud platform without security or scability in mind. 

However, we also provide [Azure App Service Landing Zone Accelerator](https://github.com/Azure/appservice-landing-zone-accelerator) reference implementation artifacts and architectural guidance to accelerate deployment of Azure App Service at scale. One of the scenarios you can find there is the Secure Baseline. 

# Deploy App Template to App Service LZA
In this document we outline how you can deploy the present app-template in a new (or existing) secure appservice environment.
Before we delve into the detailed steps, let's highlight the most important benefits of deploying into the appservice LZA

## Deployment to App Service LZA highlights
- All the Azure resources (app service web apps, azure SQL, keyvault etc) are deployed internally with private endpoints
- The Web Apps are Virtual Network integrated so that they can resolve and reach internal (private) endoints / resources
- Web App egress traffic is controlled and monitored with Azure Firewall
- Web Apps utilize User Assigned Managed Identities. For UAMI to work correctly we need to set up the `AZURE_CLIENT_ID` enviroment variable (Web App Configuration). More information: https://learn.microsoft.com/en-us/aspnet/core/security/key-vault-configuration?view=aspnetcore-7.0#use-managed-identities-for-azure-resources
- Contoso University web app is exposed to public internet through Azure Front Door Premium with WAF Policies
- [Connection String to database is passwordless](https://learn.microsoft.com/en-us/samples/azure-samples/azure-sql-db-who-am-i/azure-sql-db-passwordless-connections/)
- Deployment of App Template must be executed through the VM Jumpbox (or from a secure VPN Connection)

## Deployment Steps

### 1. Deploy the App Service LZA
Head to [App Service LZA Secure Baseline](https://github.com/Azure/appservice-landing-zone-accelerator/tree/main/scenarios/secure-baseline-multitenant) scenario and deploy the LZA. Choose any of the deployment options (the easier one is the *Deploy To Azure* button), but make sure you select the following options
- **Deployment Settings**: 
  - Web App Base Os: Linux
- **Jump-Box Settings (VM)**: You can leave the default options, but your deployment experience will be improved if you make the below choices:
  - Deploy Jump-box: yes
  - Install Useful CLIs: yes
  - Install SQL Management Studio: yes
- **Azure SQL Settings**: You need to deploy an Azure SQL Server through the LZA, and you need to enable AAD Authentication. Follow the instructions in the LZA deployment Guide, or the deployment through the portal. For more information regarding Azure SQL AAD Auth [see here](https://learn.microsoft.com/en-us/azure/azure-sql/database/authentication-aad-configure?view=azuresql-mi&tabs=azure-powershell)
- **Deployment Feature Flags**: You can leave the default options, but your deployment experience will be improved if you make the below choices:
  - Enable Egress Lockdown: true
  - Deploy Redis: false
  - Deploy App Config: false
  - Autoapprove AFD private endpoint: true

A clean deployment of the App Service LZA with the above options anabled may require arounf 45 minutes to complete

### 2. Deploy the App Template
To deploy the App Template on the new App Service LZA you need a VPN Connection to the Virtual Network of the App SVC LZA spoke virtual network. Alternatively, you can utilize the newly deployed jump-box, and this approach will be described next. 

#### 1. Login to the Azure VM Jump-box
To connect to the VM you need to use the Bastion service (Deployed through the App SVC LZA), because the VM has no public IP. You can [connect to the Jump-Box with native client](https://github.com/Azure/appservice-landing-zone-accelerator/blob/main/scenarios/secure-baseline-multitenant/bicep/README.md#connect-to-the-jumpbox-vm-deployed-in-the-spoke-resource-group), or you can use the portal/web based rdp connection through the Bastion Service 
    - Click on the VM located in the App SVC Spoke resource group, 
    - click on "*connect*", 
    - click "*bastion*", 
    - click "*Use Bastion*" 
    - add Username/password and click "Connect"  

#### 2. Finalize VM Setup
If you selected the feature flags as described above, when deploying the LZA, you should already have some tools available, such as Git, Azure CLI, SSMS etc. We need to add some more tools as described below. 
1. Open *Microsoft Store* and install/update (or just verify that it is up to date) the *App Installer*. This will allow you to use `winget` package manager
2. Open File Explorer, go to Disk D:, find folder *azd* and run the executable found there (*azd-windows-amd64*) 
3. After the previous deployment finishes, open a new **Terminal** app (in Powershell - which is the default choice) and verify that **azd** is successfully installed by running `azd version`.  
4. *Install .net 6*: in the same terminal run the command `winget install Microsoft.DotNet.SDK.6 --accept-package-agreements --accept-source-agreements`
5. *Instal Visual Studio Code*: in the same terminal run the command `winget install --id Microsoft.VisualStudioCode --accept-package-agreements --accept-source-agreements`. Once the installation finishes, run `code` to open VSCode and fisnish setup (syn profiles etc)

#### 3. Configure the AZD file
- Clone the repo https://github.com/thotheod/app-templates-dotnet-azuresql-appservice.git and open it in VSCode
- Edit azure.yaml file, change Infra/Path value from *infra* to *infra-lza*
> TODO: change URL once PR merged. For now move to Branch feat/deployToLza

#### 4. Deploy with azd - both infra resources and apps
- run azd auth login
- edit main.parameters.json file and add the names of the LZA resources (i.e. afdName, AppServicePlanName etc)
- Once the parameters are filled in, deploy ith `azd up` and select as environment, location and subscription the values you have previously selected  for the LZA

#### 5. Create the SQL user and grant minimal permissions - for the web app User Assigned Managed Identity
Open SQL Server management Studio, connect to the Azure SQL Server with AAD User with MFA. Make sure you have added this user in the AAD SQL Admin Group.

Find the user assigned managed identity that is assigned in the web app well (an idenity in the spoke RG starting with id- and ending with -appSvc)

In the SSMS run the following SQL on the SchollContext Database
```sql

DROP USER [id-appsvc03-test-neu-appSvc];
GO
CREATE USER [id-appsvc03-test-neu-appSvc]FROM EXTERNAL PROVIDER;
GO
ALTER ROLE db_owner ADD MEMBER [id-appsvc03-test-neu-appSvc];
GO		
```

#### 6. restart the contoso api app
Once you run the above SQL commands, you need to restart the API Application (i.e. contoso-apiapp-7rz7c). This is required because on startup the app is initializing the Database. 

#### 7. Test the deployment
After a few minutes, you can check with SSMS to see if there are tables in the `SchollContext` databae. If yes, then the api-app has connected successfully to the SQL DB and inititialized the DB Tables of the application. From inside the jumbox you can check in edge browser the deployed services endpoints, i.e.
    - https://contoso-apiapp-7rz7c.azurewebsites.net/
    - https://contoso-webapp-7rz7c.azurewebsites.net/api/values

Those endpoints should not be reachable outside the jump-box (i.e. your local PC if no VPN Connection is established).

To test if the Contoso web application is published successfully, you need to go to the Azure Front Door resource, on the spoke RG, and find the endpoint which starts with the prefix `contosoWeb`, i.e. https://contosoWeb-7rz7c-btbyegdwc9cxgugj.z01.azurefd.net. Testing this URL in the web browser should show a fully functional web application.
