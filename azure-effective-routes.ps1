<#
.SYNOPSIS
    Gets effective route tables for all network interfaces in a subscription and exports to CSV.
.DESCRIPTION
    This script retrieves all network interfaces in the current Azure subscription,
    gets the effective route table for each, and exports the combined results to a CSV file.
.NOTES
    File Name      : Get-EffectiveRouteTables.ps1
    Prerequisites  : Azure PowerShell module (Az)
    Version        : 1.0
#>

# Connect to Azure (if not already connected)
if (-not (Get-AzContext)) {
    Connect-AzAccount
}

# Select the subscription (if you have multiple)
$subscription = Get-AzSubscription | Out-GridView -Title "Select a subscription" -PassThru
if ($subscription) {
    Set-AzContext -Subscription $subscription.Id
}
else {
    Write-Error "No subscription selected. Exiting."
    exit
}

# Initialize an array to store all route table results
$allRoutes = @()

# Get all network interfaces in the subscription
$networkInterfaces = Get-AzNetworkInterface

if (-not $networkInterfaces) {
    Write-Output "No network interfaces found in the subscription."
    exit
}

# Process each network interface
foreach ($nic in $networkInterfaces) {
    Write-Output "Processing NIC: $($nic.Name) in Resource Group: $($nic.ResourceGroupName)"
    
    try {
        # Get the effective route table
        $routeTable = Get-AzEffectiveRouteTable -NetworkInterfaceName $nic.Name -ResourceGroupName $nic.ResourceGroupName
        
        # Add properties to identify which NIC this belongs to
        foreach ($route in $routeTable) {
            $route | Add-Member -NotePropertyName "NetworkInterfaceName" -NotePropertyValue $nic.Name
            $route | Add-Member -NotePropertyName "ResourceGroupName" -NotePropertyValue $nic.ResourceGroupName
            $route | Add-Member -NotePropertyName "Location" -NotePropertyValue $nic.Location
        }
        
        # Add to the collection
        $allRoutes += $routeTable
    }
    catch {
        Write-Warning "Failed to get route table for NIC $($nic.Name): $_"
    }
}

# Export to CSV
if ($allRoutes.Count -gt 0) {
    $outputFile = "EffectiveRouteTables_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $allRoutes | Export-Csv -Path $outputFile -NoTypeInformation -Force
    Write-Output "Exported $($allRoutes.Count) routes to $outputFile"
    
    # Verify the file was created properly
    if (Test-Path $outputFile) {
        $fileInfo = Get-Item $outputFile
        if ($fileInfo.Length -gt 0) {
            Write-Output "CSV file created successfully with data."
        }
        else {
            Write-Warning "CSV file was created but is empty. Check if there were any routes returned."
        }
    }
    else {
        Write-Error "Failed to create CSV file."
    }
}
else {
    Write-Output "No route tables were retrieved to export."
}
