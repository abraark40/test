<#
.SYNOPSIS
    Gets effective route tables for all network interfaces across all subscriptions and resource groups.
.DESCRIPTION
    This script retrieves all network interfaces across all Azure subscriptions and resource groups,
    gets the effective route table for each, and exports the combined results to a CSV file.
.NOTES
    File Name      : Get-EffectiveRouteTables-AllSubscriptions.ps1
    Prerequisites  : Azure PowerShell module (Az)
    Version        : 1.0
#>

# Connect to Azure (if not already connected)
if (-not (Get-AzContext)) {
    Connect-AzAccount
}

# Initialize an array to store all route table results
$allRoutes = @()

# Get all subscriptions
$subscriptions = Get-AzSubscription

if (-not $subscriptions) {
    Write-Output "No Azure subscriptions found."
    exit
}

# Process each subscription
foreach ($subscription in $subscriptions) {
    Write-Output "Processing Subscription: $($subscription.Name) (ID: $($subscription.Id))"
    
    # Set the context to the current subscription
    Set-AzContext -Subscription $subscription.Id | Out-Null

    # Get all network interfaces in the current subscription
    $networkInterfaces = Get-AzNetworkInterface

    if (-not $networkInterfaces) {
        Write-Output "No network interfaces found in subscription: $($subscription.Name)"
        continue
    }

    # Process each network interface
    foreach ($nic in $networkInterfaces) {
        Write-Output "Processing NIC: $($nic.Name) in Resource Group: $($nic.ResourceGroupName)"
        
        try {
            # Get the effective route table
            $routeTable = Get-AzEffectiveRouteTable -NetworkInterfaceName $nic.Name -ResourceGroupName $nic.ResourceGroupName
            
            # Add properties to identify which NIC and subscription this belongs to
            foreach ($route in $routeTable) {
                $route | Add-Member -NotePropertyName "NetworkInterfaceName" -NotePropertyValue $nic.Name
                $route | Add-Member -NotePropertyName "ResourceGroupName" -NotePropertyValue $nic.ResourceGroupName
                $route | Add-Member -NotePropertyName "Location" -NotePropertyValue $nic.Location
                $route | Add-Member -NotePropertyName "SubscriptionName" -NotePropertyValue $subscription.Name
                $route | Add-Member -NotePropertyName "SubscriptionId" -NotePropertyValue $subscription.Id
            }
            
            # Add to the collection
            $allRoutes += $routeTable
        }
        catch {
            Write-Warning "Failed to get route table for NIC $($nic.Name) in RG $($nic.ResourceGroupName), Subscription $($subscription.Name): $_"
        }
    }
}

# Export to CSV
if ($allRoutes.Count -gt 0) {
    $outputFile = "EffectiveRouteTables_AllSubscriptions_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    
    # Flatten the object structure for proper CSV export
    $exportData = $allRoutes | Select-Object @(
        'NetworkInterfaceName',
        'ResourceGroupName',
        'Location',
        'SubscriptionName',
        'SubscriptionId',
        'State',
        'AddressPrefix',
        'NextHopType',
        'NextHopIpAddress',
        'Source',
        'Name'
    )
    
    $exportData | Export-Csv -Path $outputFile -NoTypeInformation -Force
    Write-Output "Exported $($allRoutes.Count) routes to $outputFile"
    
    # Verify the file was created properly
    if (Test-Path $outputFile) {
        $fileInfo = Get-Item $outputFile
        if ($fileInfo.Length -gt 0) {
            Write-Output "CSV file created successfully with data."
            Write-Output "File location: $((Get-Item $outputFile).FullName)"
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
