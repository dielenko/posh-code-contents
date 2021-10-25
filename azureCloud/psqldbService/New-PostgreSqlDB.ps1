[CmdletBinding()]
param 
(
    [Parameter(Mandatory = $true)]
    [string]$AzureResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$AzureResourceLocation,

    [Parameter(Mandatory = $true)]
    [string]$PostgreSqlDBName,

    [Parameter(Mandatory = $false)]
    [ValidateSet('B_Gen5_2', 'GP_Gen5_32', 'MO_Gen5_2')]
    [String]$PostgreSqlSku = 'B_Gen5_2',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Enabled', 'Disabled')]
    [String]$PostgreSqlGeoRedundantBackup = 'Disabled'

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
    # Check the Microsoft.DBforPostgreSQL resource provider
    Write-Host "Checking the `"Microsoft.DBforPostgreSQL`" resource provider existence..." -ForegroundColor Magenta
    $checkPostgreSQLProviderStatus = Get-AzResourceProvider | Where-Object { $_.ProviderNamespace -eq "Microsoft.DBforPostgreSQL" }

    if ($checkPostgreSQLProviderStatus.RegistrationState -eq 'Registered') {
        Write-Host "The resource provider found with registration state attribute equal to registered. No further actions required" -ForegroundColor Green
    }
    else {
        Write-Host "`"Microsoft.DBforPostgreSQL`" resource provider will be registered" -ForegroundColor Yellow
        Register-AzResourceProvider -ProviderNamespace "Microsoft.DBforPostgreSQL"
        Write-Host "Resource provider called `"Microsoft.DBforPostgreSQL`" registered" -ForegroundColor Green
    }

    # Create a resource group
    Write-Host "Creating a resource group as a logical boundary for the psql db service called `"$($PostgreSqlDBName)`"..." -ForegroundColor Magenta
    New-AzResourceGroup –Name $AzureResourceGroupName –Location $AzureResourceLocation
    Write-Host "The resource group called `"$($AzureResourceGroupName)`" created" -ForegroundColor Green

    # Create an Azure Database for PostgreSQL server
    Write-Host "Creating an Azure Database for PostgreSQL server within the resource group called `"$($AzureResourceGroupName)`"..." -ForegroundColor Magenta
    $postgreSqlDBAdminUsernamePassword = Set-RandomPassword

    New-AzPostgreSqlServer -Name $PostgreSqlDBName `
        -ResourceGroupName $AzureResourceGroupName `
        -Sku $PostgreSqlSku `
        -GeoRedundantBackup $PostgreSqlGeoRedundantBackup `
        -Location $AzureResourceLocation `
        -AdministratorUsername 'adminpsql' `
        -AdministratorLoginPassword $postgreSqlDBAdminUsernamePassword
    Write-Host "The PostgreSQL Azure Database called `"$($PostgreSqlDBName)`" created" -ForegroundColor Green

    # Configure a firewall access rule for PostgreSQL Azure Database
    Write-Host "Getting yours public IP Address to be added to the PostgreSQL Azure Database firewall..." -ForegroundColor Magenta
    $sites = @('ipinfo.io/ip', 'ifconfig.me/ip', 'ident.me')
    for ($i = 0; $i -lt $sites.length; $i++) {
        try {
            $ipAddress = (Invoke-WebRequest -Uri "http://$($sites[$i])").Content
            if ($ipAddress -as [IPAddress] -as [Bool]) {
                Write-Host "Your IP address `"$($ipAddress)`" is valid" -ForegroundColor Green
                Break
            }
        }
        catch {
            $ipAddresserrorMessage = $_.Exception.Message
            $ipAddresserrorMessage
        }
    }

    # Create a firewall rule that allows connections from a specific IP address
    $ipAddressRuleName = $($ipAddress -replace '\.', '_')
    Write-Host "Creating a firewall rule named `"AllowIP_$($ipAddressRuleName)`" that allows connections from `"$($ipAddress)`" IP address..." -ForegroundColor Magenta
    New-AzPostgreSqlFirewallRule -Name "AllowIP_$($ipAddressRuleName)" `
        -ResourceGroupName $AzureResourceGroupName `
        -ServerName $PostgreSqlDBName `
        -StartIPAddress $ipAddress `
        -EndIPAddress $ipAddress
    Write-Host "The firewall rule called `"AllowIP_$($ipAddressRuleName)`" created" -ForegroundColor Green

    # Get the connection information regarding the created PostgreSQL Azure Database
    Write-Host "Getting the connection information regarding the created PostgreSQL Azure Database called `"$($PostgreSqlDBName)`"..." -ForegroundColor Magenta
    $getAzPostgreSqlDetails = Get-AzPostgreSqlServer -Name $PostgreSqlDBName -ResourceGroupName $AzureResourceGroupName |
    Select-Object -Property FullyQualifiedDomainName, AdministratorLogin
    $administratorLoginPassword = ConvertFrom-SecureString -SecureString $postgreSqlDBAdminUsernamePassword -AsPlainText
    $getAzPostgreSqlDetails | Add-Member -MemberType NoteProperty -Name 'administratorLoginPassword' -Value "$administratorLoginPassword"
    Write-Host "Below are the connection details for PostgreSQL Azure Database called `"$($PostgreSqlDBName)`"" -ForegroundColor Green
    $getAzPostgreSqlDetails | Format-List
}
catch {
    $errorMessage = $_.Exception.Message
    $errorMessage
}
