$ErrorActionPreference = "Stop"

$deploymentUsername = $Env:DEPLOYMENT_USER_NAME
$deploymentPassword = $Env:DEPLOYMENT_PASSWORD
$tenantId = $Env:TENANT_ID

$securePassword = ($deploymentPassword | ConvertTo-SecureString -AsPlainText -Force)
$credential = New-Object System.Management.Automation.PSCredential ($deploymentUsername, $securePassword)
Connect-AzureAD -Credential $credential -TenantId $tenantId

$appName = 'Test_From_Powershell_1'
$homePage = 'http://localhost:8080'
$replyUrl = 'http://localhost:8080/login/authorized'

$app = Get-AzureADApplication -Filter "DisplayName eq '$($appName)'" -ErrorAction SilentlyContinue
#Create Application Registration
if (!$app)
{
    # Create key value
    $guid = New-Guid
    $credValue = ([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($Guid))))+"="
    $passwordCredential = New-Object -TypeName Microsoft.Open.AzureAD.Model.PasswordCredential
    $passwordCredential.StartDate = Get-Date
    $passwordCredential.EndDate = ([Datetime]"12/31/2070")
    $passwordCredential.KeyId = $guid
    $passwordCredential.Value = $credValue
       
    # Add read/write permission to Azure AD
    $servicePrincipal = Get-AzureADServicePrincipal -All $true | ? { $_.DisplayName -match "Windows Azure Active Directory" }
    $readWriteRole = $servicePrincipal.AppRoles | Where-Object {$_.Value -eq 'Directory.ReadWrite.All'}
    $reqAAD = New-Object -TypeName "Microsoft.Open.AzureAD.Model.RequiredResourceAccess"
	$reqAAD.ResourceAppId = $servicePrincipal.AppId
    $readWritePermission = New-Object -TypeName "Microsoft.Open.AzureAD.Model.ResourceAccess" -ArgumentList $readWriteRole.Id,"Role"
    $reqAAD.ResourceAccess = $readWritePermission

    $app = New-AzureADApplication -DisplayName $appName -Homepage $homePage -IdentifierUris $homePage -ReplyUrls $replyUrl -PasswordCredentials $passwordCredential -RequiredResourceAccess $reqAAD

    $AppDetailsOutput = "Application Details for the $AADApplicationName application:
=========================================================
Application Name: 	$appName
Application Id:   	$($app.AppId)
Secret Key:       	$($passwordCredential.Value)
"
	Write-Host
	Write-Host $AppDetailsOutput
}

Disconnect-AzureAD

# Execute the admin permission grant (not sure how well this works???)

$credential1 = New-Object System.Management.Automation.PSCredential ($deploymentUsername, $securePassword)
Login-AzureRmAccount -Credential $credential1 -TenantId $tenantId
$context = Set-AzureRmContext -TenantId $tenantId -Name B2C -Force

$token = $context.TokenCache.ReadItems() | Where-Object { $_.Resource -ilike "*/management.core.windows.net/*" -and $_.RefreshToken -ne $null -and $tenantId -ieq $_.Authority.Split('/')[3] } | sort -Property ExpiresOn -Descending | select -First 1
$refreshToken = $token.RefreshToken
$body = "grant_type=refresh_token&refresh_token=$($refreshToken)&resource=74658136-14ec-4630-ad9b-26e160ff0fc6"
$apiToken = Invoke-RestMethod "https://login.windows.net/$tenantId/oauth2/token" -Method POST -Body $body -ContentType 'application/x-www-form-urlencoded'

$header = @{
'accept' = '*/*'
'accept-encoding' = 'gzip, deflate, br'
'accept-language' = 'en'
'authorization' = 'Bearer ' + $accessToken
'x-requested-with'= 'XMLHttpRequest'
'x-ms-client-request-id'= [guid]::NewGuid()
'x-ms-correlation-id' = [guid]::NewGuid()}

$appId = $app.AppId
$url = "https://main.iam.ad.ext.azure.com/api/RegisteredApplications/$appId/Consent?onBehalfOfAll=true"
Invoke-RestMethod –Uri $url –Headers $header –Method POST -ErrorAction Stop -Verbose
