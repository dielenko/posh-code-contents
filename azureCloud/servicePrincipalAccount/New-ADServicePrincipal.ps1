[CmdletBinding()]
param 
(

    [Parameter(Mandatory = $true)]
    [string]$AzureADServicePrincipalName

)
#******************************************************************************
# Function section
#******************************************************************************
# checks Azure PowerShell modules existence as prerequisites
function Test-AzPoshModule {
    try {
        $link = 'https://azure.microsoft.com/en-us/blog/azure-powershell-cross-platform-az-module-replacing-azurerm'
        if ($PSVersionTable.PSEdition -eq 'Desktop' -and (Get-Module -Name AzureRM -ListAvailable)) {
            Write-Host ('Az module not installed. Having both the AzureRM and ' +
                'Az PowerShell modules installed at the same time is not supported.') -ForegroundColor Red
            Write-Host "Uninstall firtsly AzureRM and run again the automation..." -ForegroundColor Yellow
            Write-Host "Open the following link to porceed further:`n$link" -ForegroundColor Green
            break
        }
        elseif (Get-Module -Name "Az.*" -ListAvailable) {
            Write-Host "Az PowerShell module exists." -ForegroundColor Green
        }
        else {
            Write-Host "Install Az PowerShell module for the current user only..." -ForegroundColor Yellow
            Install-Module -Name Az -AllowClobber -Scope CurrentUser
            Write-Host "Az PowerShell module installed." -ForegroundColor Yellow
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        $errorMessage
        exit 1 
    }
}

# checks the metadata used to authenticate Azure Resource Manager requests
function Test-AzLogin {
    $needLogin = $true
    Try {
        $content = Get-AzContext
        if ($content) {
            $needLogin = ([string]::IsNullOrEmpty($content.Account))
            $currentAzContext = Get-AzContext | Select-Object -ExpandProperty  Name
            Write-Host 'You are working with the following Azure context:' -ForegroundColor Yellow
            Write-Host $currentAzContext -ForegroundColor Green
        } 
    } 
    Catch {
        if ($_ -like "*Login-AzAccount to login*") {
            $needLogin = $true
        } 
        else {
            throw
        }
    }
    
    if ($needLogin) {
        # sign in
        Write-Host "Logging in..." -ForegroundColor Magenta
        Login-AzAccount
    }
}

function Set-RandomPassword {
    $length = 14
    $symbols = '!@#$%^&*'.ToCharArray()
    $characterList = 'a'..'z' + 'A'..'Z' + '0'..'9' + $symbols

    do {
        $password = -join (0..$length | ForEach-Object { $characterList | Get-Random })
        [int]$hasLowerChar = $password -cmatch '[a-z]'
        [int]$hasUpperChar = $password -cmatch '[A-Z]'
        [int]$hasDigit = $password -match '[0-9]'
        [int]$hasSymbol = $password.IndexOfAny($symbols) -ne -1

    }
    until (($hasLowerChar + $hasUpperChar + $hasDigit + $hasSymbol) -ge 1)
    $password | ConvertTo-SecureString -AsPlainText
}
#******************************************************************************
# Script body
# Execution begins here
#******************************************************************************
$ErrorActionPreference = "Stop"
Push-Location $PsScriptRoot

Write-Host "Checking and if needed configure the Az PowerShell module..." -ForegroundColor Magenta
Test-AzPoshModule

Write-Host "Checking current login state at Azure..."  -ForegroundColor Magenta
Test-AzLogin

try {
    # Check the Az.Resources module
    Write-Host "Checking the `"Az.Resources`" module existence..." -ForegroundColor Magenta
    $getAzResources = Get-Module Az.Resources

    if ($getAzResources) {
        Write-Host "The `"Az.Resources`" module exists. No further actions required" -ForegroundColor Green
    }
    else {
        Write-Host "`"Az.Resources`" module will be imported" -ForegroundColor Yellow
        Import-Module Az.Resources
        Write-Host "`"Az.Resources`" module imported" -ForegroundColor Green
    }

    # Create an Azure Service Principal account
    Write-Host "Checking the existence of the Azure Service Principal account called `"$($AzureADServicePrincipalName)`"..." -ForegroundColor Magenta
    $getAzADServicePrincipal = Get-AzADServicePrincipal -DisplayName "$AzureADServicePrincipalName"
    $getAzADApplication = Get-AzADApplication -DisplayName "$AzureADServicePrincipalName"

    #TODO: Separate the if output per each item
    if ($getAzADServicePrincipal -or $getAzADApplication) {
        Write-Host "The Azure Service Principal account exists. The script execution will be stopped" -ForegroundColor Red
        Break
    }
    else {
        Write-Host "The Azure Service Principal account does not exists" -ForegroundColor Green
        Write-Host "Creating an Azure Service Principal account with the following display name `"$($AzureADServicePrincipalName)`"..." -ForegroundColor Magenta
        $adServicePrincipalPassword = Set-RandomPassword
        $adServicePrincipalcredentials = New-Object Microsoft.Azure.Commands.ActiveDirectory.PSADPasswordCredential `
            -Property @{ StartDate = Get-Date; EndDate = Get-Date -Year 2024; Password = $adServicePrincipalPassword };
        
        $adServicePrincipalSplat = @{
            DisplayName        = "$AzureADServicePrincipalName"
            PasswordCredential = $adServicePrincipalcredentials
        }
        $adServicePrincipalAccount = New-AzAdServicePrincipal @adServicePrincipalSplat
        Write-Host "The Azure Service Principal account called `"$($AzureADServicePrincipalName)`" created" -ForegroundColor Green
    
        # Assign a Role to the Azure Service Principal account
        Write-Host "Assigning the RBAC role `"Contributor`" to the Service Principal called `"$($AzureADServicePrincipalName)`"..." -ForegroundColor Magenta
        $currentAzSubscriptionId = (Get-AzContext).Subscription.id
    
        $roleAssignmentSplat = @{
            ObjectId           = $adServicePrincipalAccount.id
            RoleDefinitionName = 'Contributor'
            Scope              = "/subscriptions/$currentAzSubscriptionId"
        }
    
        New-AzRoleAssignment @roleAssignmentSplat
    
        # Get the connection information regarding the created Azure Service Principal account
        Write-Host "Getting the connection information regarding the created Azure Service Principal account called `"$($AzureADServicePrincipalName)`"..." -ForegroundColor Magenta
        $servicePrincipalPassword = ConvertFrom-SecureString -SecureString $adServicePrincipalPassword -AsPlainText
        $azADServicePrincipalInfo = [ordered]@{
            ServicePrincipalDisplayName   = $adServicePrincipalAccount.DisplayName
            ServicePrincipalName          = $adServicePrincipalAccount.ServicePrincipalNames
            ServicePrincipalApplicationId = $adServicePrincipalAccount.ApplicationId
            ServicePrincipalId            = $adServicePrincipalAccount.Id
            ServicePrincipalPassword      = $servicePrincipalPassword
        }
        Write-Host "Below are the connection details for the created Azure Service Principal account called `"$($AzureADServicePrincipalName)`"" -ForegroundColor Green
        $azADServicePrincipalInfo | Format-Table
    }

}
catch {
    $errorMessage = $_.Exception.Message
    $errorMessage
}
