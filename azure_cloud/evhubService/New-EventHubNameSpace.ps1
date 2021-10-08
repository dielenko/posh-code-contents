[CmdletBinding()]
param 
(
    [Parameter(Mandatory = $true)]
    [string]$AzureResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$AzureResourceLocation,

    [Parameter(Mandatory = $true)]
    [string]$EventHubName,

    [Parameter(Mandatory = $true)]
    [int]$MessageRetentionInDaysValue

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
    # Create a resource group
    Write-Host "Creating a resource group as a logical boundary for the event hub service called `"$($EventHubName)`"" -ForegroundColor Magenta
    New-AzResourceGroup –Name $AzureResourceGroupName –Location $AzureResourceLocation -Verbose
    Write-Host "The resource group called `"$($AzureResourceGroupName)`" created" -ForegroundColor Green

    # Generate a random number to assign as a suffix in the Event Hub namespace name
    $evHubNameSpaceName = $EventHubName + '-ns-' + $(Get-Random -Maximum 1000000)

    # Create an Event Hubs namespace
    Write-Host "Creating an Event Hubs namespace within the resource group called `"$($AzureResourceGroupName)`"" -ForegroundColor Magenta
    New-AzEventHubNamespace -ResourceGroupName $AzureResourceGroupName `
        -NamespaceName $evHubNameSpaceName `
        -Location $AzureResourceLocation `
        -Verbose
    Write-Host "The Event Hubs namespace called `"$($evHubNameSpaceName)`" created" -ForegroundColor Green

    # Create an event hub
    Write-Host "Creating an Event Hub within the namespace called `"$($evHubNameSpaceName)`"" -ForegroundColor Magenta
    New-AzEventHub -ResourceGroupName $AzureResourceGroupName `
        -NamespaceName $evHubNameSpaceName `
        -EventHubName $EventHubName `
        -MessageRetentionInDays $MessageRetentionInDaysValue `
        -Verbose
    Write-Host "The Event Hub called `"$($EventHubName)`" created" -ForegroundColor Green
}
catch {
    $errorMessage = $_.Exception.Message
    $errorMessage
}
