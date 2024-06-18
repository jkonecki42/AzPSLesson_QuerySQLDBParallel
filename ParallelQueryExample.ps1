<#
  Powershell 7.4.2     https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.4
  Az 12.0.0            Install-Module Az -Scope CurrentUser
  SQLServer 22.2.0     Install-Module SqlServer -Scope CurrentUser
#>

# Environment Variables
$resourceGroupName = 'QuerySQLDBParallelTutorial'
$location = "East US"
$throttleLimit = 10
$subscriptionName = "Konecki Pay As You Go"

Connect-AzAccount -Subscription $subscriptionName

# Create the Resource Group
New-AzResourceGroup -Name $resourceGroupName -Location $location

## SQL Server Section ##
$adminCredential = Get-Credential # any three: upper, lower, digit, non-alpha

# Use splatting to enhance argument readability.
$serverArguments = @{
  ResourceGroupName           = $resourceGroupName
  Location                    = $location 
  ServerName                  = 'konecki-server-01' # lowercase, digits, hyphens
  ServerVersion               = "12.0" 
  SqlAdministratorCredentials = $adminCredential 
}

# Create the SQL Server Instance. If you want, you can capture the AzSqlServerModel output here as well.
$sqlServerObject = New-AzSqlServer @serverArguments -Verbose

# Exit if the server was not created.
if (!$sqlServerObject) {
  Write-Error "Failed to create SQL Server."; exit
}

# Whitelist our IP in the SQL Server firewall.
$devPublicIP = (Invoke-WebRequest -uri "http://ifconfig.me/ip").Content

$firewallRuleArguments = @{
  ResourceGroupName = $resourceGroupName
  ServerName        = $sqlServerObject.ServerName
  FirewallRuleName  = "AllowDevIP"
  StartIpAddress    = $devPublicIP
  EndIpAddress      = $devPublicIP
}
New-AzSqlServerFirewallRule @firewallRuleArguments

## SQL Database Section ##
$serverName = $sqlServerObject.ServerName
$dbNames = @(
  "KoneckiDB1",
  "KoneckiDB2"
)

# Create a pair of SQL Databases attached to the server we just created.
# Also, capture the AzSqlDatabaseModel array output.
$databases = $dbNames | ForEach-Object -ThrottleLimit $throttleLimit -Parallel {
  $dbName = $_
  $databaseArguments = @{
    ResourceGroupName = $using:resourceGroupName
    ServerName        = $using:serverName
    DatabaseName      = $dbName
  }
  Write-Host "Creating $dbName..."
  New-AzSqlDatabase @databaseArguments -Verbose
  Write-Host "Finished creating $dbName."
}

$result = $databases | ForEach-Object -ThrottleLimit $throttleLimit -Parallel {
  $dbName = $_.DatabaseName
  $SQLArgs = @{
    Database       = $_.Databasename
    ServerInstance = $using:serverName + ".database.windows.net"
    Credential     = $using:adminCredential
    Query          = "SELECT DBName() AS 'DBName'"
  }
  Write-Host "Querying $dbName..."
  Invoke-Sqlcmd @SQLArgs
  Write-Host "Finished querying $dbName."
}

# Display the results
$result | Format-Table

# Delete the resources.
Remove-AzResourceGroup -Name $resourceGroupName -Force -Verbose
