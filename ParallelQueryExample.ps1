<#
  Powershell 7.4.2     https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.4
  Az 12.0.0            Install-Module Az -Scope CurrentUser
  SQLServer 22.2.0     Install-Module Az -Scope CurrentUser
  Az.Sql Documentation https://learn.microsoft.com/en-us/powershell/module/az.sql/?view=azps-12.0.0
#>

#Connect-AzAccount -Subscription '12c13603-727c-44ab-953f-ae8f7ec9e183'

# Environment Variables
$resourceGroupName = 'Konecki_Test_RG'
$location = "North Central US"
$throttleLimit = 10
$adminCredential = Get-Credential

## SQL Server Section ##
# Use splatting to enhance argument readability.
$serverArguments = @{
  ResourceGroupName           = $resourceGroupName
  Location                    = $location 
  ServerName                  = 'koneckiServer'
  ServerVersion               = "12.0" 
  SqlAdministratorCredentials = $adminCredential
}

# Create the SQL Server Instance. If you want, you can capture the AzSqlServerModel output here as well.
New-AzSqlServer @serverArguments

# Exit if the server was not created.
if (!$sqlServerObject) {
  Write-Error "Failed to create SQL Server."; exit
}

$firewallRuleArguments = @{
  ServerName       = $serverName
  FirewallRuleName = "AllowDevIP"
  StartIpAddress   = $devPublicIP
  EndIpAddress     = $devPublicIP
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
    ResourceGroupName = "Konecki_Test_RG"
    ServerName        = $using:serverName
    DatabaseName      = $dbName
  }
  Write-Host "Creating $dbName..."
  New-AzSqlDatabase @databaseArguments -Verbose
  Write-Host "Finished creating $dbName."
}

$result = $databases | ForEach-Object -ThrottleLimit $throttleLimit -Parallel {
  $dbName = $_ 
  $serverURI = $using:serverName + ".database.windows.net"
 
  $SQLArgs = @{
    Database       = $dbName
    ServerInstance = $serverURI
    Credential     = $adminCredential
    Query          = "SELECT DBName()"
  }
  Write-Host "Querying $dbName..."
  Invoke-Sqlcmd @SQLArgs
  Write-Host "Finished querying $dbName."
}

# Display the results
$result | Format-Table

# Delete the resources.
Remove-AzResourceGroup -Name $resourceGroupName
