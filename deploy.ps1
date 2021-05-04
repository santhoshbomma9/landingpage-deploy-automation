$ErrorActionPreference = "Stop"

$ResourceGroupName = Read-Host "Please enter resource group to deploy the azure resources"
$AppAdmin = Read-Host "Please enter email of the user to be the app admin:"

##  STEP 1: CREATE LOGIN APP REGISTRATION
$req = New-Object -TypeName "Microsoft.Open.AzureAD.Model.RequiredResourceAccess"
$req.ResourceAccess = New-Object -TypeName "Microsoft.Open.AzureAD.Model.ResourceAccess" -ArgumentList "e1fe6dd8-ba31-4d61-89e7-88639da4683d","Scope"
$req.ResourceAppId = "00000003-0000-0000-c000-000000000000"
$landingPageApp = New-AzureADApplication -DisplayName "landingpageapp" -Oauth2RequirePostResponse $true -AvailableToOtherTenants $true -RequiredResourceAccess $req

##  STEP 2: CREATE FULFILLMENT APP REGISTRATION
$Guid = New-Guid
$startDate = Get-Date
$PasswordCredential = New-Object -TypeName Microsoft.Open.AzureAD.Model.PasswordCredential
$PasswordCredential.StartDate = $startDate
$PasswordCredential.EndDate = $startDate.AddYears(1)
$PasswordCredential.KeyId = $Guid
$PasswordCredential.Value = ([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($Guid))))+"="
$fulfillmentAppId = New-AzureADApplication -DisplayName "fulfillmentapp" -PasswordCredentials $PasswordCredential | %{  $_.AppId }

## CREATE RESOURCE GROUP IF NEEDED
Get-AzResourceGroup -Name $ResourceGroupName -ErrorVariable notPresent -ErrorAction SilentlyContinue

if($notPresent) {
    $ResourceGroup = New-AzResourceGroup -Name $ResourceGroupName -Location "east us"
}

## SET VARIABLES
$landingPageAppId = $landingPageApp.AppId
$tenantId = Get-AzureADTenantDetail | %{  $_.ObjectId }
$publisherDomain = Get-AzureADApplication -ObjectId $landingPageApp.ObjectId | %{  $_.publisherDomain }

<# DEBUG
"Domain : " + $publisherDomain
"ClientId : " +  $landingPageAppId
"TenantId : " + $tenantId
"ClientId : " + $fulfillmentAppId
"Secret : " + $fulfillmentAppSecret
 #>

## STEP 3: DEPLOY AZURE RESOURCES AND APPLICATION
$deployment = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName `
                  -TemplateFile .\mainTemplate.json `
                  -loginAppRegDomainName $publisherDomain `
                  -loginAppRegClientId $landingPageAppId `
                  -fulfillmentAppRegTenantId $tenantId `
                  -fulfillmentAppRegClientId $fulfillmentAppId `
                  -fulfillmentAppRegClientSecret (ConvertTo-SecureString $PasswordCredential.Value -AsPlainText -Force) `
                  -webAppAdmin $AppAdmin `
                  -managedAppInstall $false

## STEP 4: ADD REDIRECT URI TO THE LOGIN APP REGISTRATION
$rawurl =  $deployment.Outputs.applicationURL.Value
$applicationURL = "https://"+ $rawurl
$appoidcURL = "https://"+ $rawurl + "/signin-oidc"
$landingpageURL = "https://"+ $rawurl + "/landingpage"
$webhookURL = "https://"+ $rawurl + "/api/webhook"
$logoutURL = "https://"+ $rawurl + "/signout-callback-oidc"
Set-AzureADApplication -ObjectId $landingPageApp.ObjectId -ReplyUrls @($applicationURL, $appoidcurl) -LogoutUrl $logoutURL

## STEP 5: USE THE BELOW IN THE PC - OFFER - TECHNICAL CONFIGURATION PAGE
"Landingpage : " + $landingpageURL
"Webhook : " +  $webhookURL
"TenantId : " + $tenantId
"ClientId : " + $fulfillmentAppId

## UPDATE THE LOGIN APP REGISTRATION MANIFEST "accessTokenAcceptedVersion": 2, "signInAudience": "AzureADandPersonalMicrosoftAccount",
