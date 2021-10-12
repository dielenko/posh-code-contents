[CmdletBinding()]
param 
(

    [Parameter(Mandatory = $true)]
    [string]$AzureADServicePrincipalDisplayName

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

    # Delete the Azure AD Application and the Azure Service Principal account
    Write-Host "Deleting the Azure AD Application and related Azure Service Principal account called `"$($AzureADServicePrincipalDisplayName)`"..." -ForegroundColor Magenta
    Get-AzADApplication -DisplayName "$AzureADServicePrincipalDisplayName" `
    | ForEach-Object { Remove-AzADApplication -ObjectId $_.ObjectId -Force }
    Write-Host "Azure AD Application and related Azure Service Principal account called `"$($AzureADServicePrincipalDisplayName)`" are deleted" -ForegroundColor Green

}
catch {
    $errorMessage = $_.Exception.Message
    $errorMessage
}
