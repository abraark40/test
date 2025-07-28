[CmdletBinding()]
param (
    [parameter(Mandatory = $true)]
    [string] $filepath,

    [parameter(Mandatory = $true)]
    [string] $subscriptionId,

    [parameter(Mandatory = $false)]
    [array] $exclvnets,

    [parameter(Mandatory = $false)]
    [array] $exclsubnets
)

function ParseAzNetworkInterfaceID {
    param ([string]$resourceID)
    if ($resourceID -notmatch "/subscriptions/.+/resourceGroups/.+/providers/Microsoft.Network/networkInterfaces/.+") {
        return $null
    }
    $array = $resourceID.Split('/')
    return @($array[2], $array[4], $array[-1])
}

function LoadModule ($m) {
    if (!(Get-Module -Name $m)) {
        if (!(Get-Module -ListAvailable -Name $m)) {
            Install-Module -Name $m -Force -Scope CurrentUser
        }
        Import-Module $m -Force
    }
}

# Load required modules
LoadModule "Az.Accounts"
LoadModule "Az.Network"
LoadModule "Az.Compute"

Connect-AzAccount
Set-AzContext -SubscriptionId $subscriptionId

# Validate output path
if (!(Test-Path $filepath)) {
    Write-Error "Invalid file path: $filepath"
    exit
}

$excludedsubnets = @("AzureBastionSubnet", "RouteServerSubnet")
if ($exclsubnets) {
    $excludedsubnets += $exclsubnets
    $excludedsubnets = $excludedsubnets | Select-Object -Unique
}

$outputs = [System.Collections.Generic.List[PSObject]]::new()
$vnets = Get-AzVirtualNetwork | Where-Object {$exclvnets -notcontains $_.Name}

foreach ($vnet in $vnets) {
    $snets = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet
    $snets = $snets | Where-Object {$excludedsubnets -notcontains $_.Name}

    foreach ($snet in $snets) {
        if (-not $snet.IpConfigurations.Id) { continue }

        $vmnicInfo = ParseAzNetworkInterfaceID -resourceID $snet.IpConfigurations.Id
        if (!$vmnicInfo -or $vmnicInfo.Count -lt 3) {
            Write-Warning "Could not parse NIC info for subnet $($snet.Name)"
            continue
        }

        $rtattached = if ($snet.RouteTable) { "Yes" } else { "No" }
        $rtname = if ($snet.RouteTable) { ($snet.RouteTable.ID.Split("/") | Select-Object -Last 1) } else { $null }

        $vmnic = Get-AzNetworkInterface -Name $vmnicInfo[2] -ResourceGroupName $vmnicInfo[1]
        if (!$vmnic.VirtualMachine) {
            $effroutes = "No"
        } else {
            $vm = Get-AzVM -Name (($vmnic.VirtualMachine.Id.Split("/") | Select-Object -Last 1)) -ResourceGroupName $vmnicInfo[1] -Status
            if ($vm.PowerState -ne "VM running") {
                $effroutes = "No"
            } else {
                $nicroutes = Get-AzEffectiveRouteTable -ResourceGroupName $vm.ResourceGroupName -NetworkInterfaceName $vmnic.Name
                $effroutes = "Yes"
                $bgppropagation = if ($nicroutes | Where-Object {$_.DisableBgpRoutePropagation -eq "True"}) { "Disabled" } else { "Enabled" }

                $internetRoutes = $nicroutes | Where-Object {$_.NextHopType -eq "Internet" -and $_.State -eq "Active"}
                $internetaccess = if ($internetRoutes) { "Enabled" } else { "Disabled" }
                $inetroutes = $internetRoutes.AddressPrefix -join ", "

                $gatewayRoutes = $nicroutes | Where-Object {$_.NextHopType -eq "VirtualNetworkGateway" -and $_.State -eq "Active"}
                $gatewayroutes = if ($gatewayRoutes) { "Enabled" } else { "Disabled" }
                $vngroutesaddprefix = $gatewayRoutes.AddressPrefix -join ", "
                $vngroutesnexthop = ($gatewayRoutes.NextHopIpAddress | Select-Object -Unique) -join ", "

                $applianceRoutes = $nicroutes | Where-Object {$_.Name -ne $null -and $_.NextHopIpAddress -ne $null}
                $applianceroutes = if ($applianceRoutes) { "Enabled" } else { "Disabled" }
                $nvaprefix = $applianceRoutes.AddressPrefix -join ", "
                $nvanexthop = ($applianceRoutes.NextHopIpAddress | Select-Object -Unique) -join ", "
            }
        }

        $output = [PSCustomObject]@{
            "Subscription ID"                        = $subscriptionId
            "vNet Name"                              = $vnet.Name
            "Subnet Name"                            = $snet.Name
            "EffectiveRoutes"                        = $effroutes
            "RouteTable Attached"                    = $rtattached
            "RouteTable Name"                        = $rtname
            "BGP Propagation"                        = $bgppropagation
            "Internet Routes"                        = $internetaccess
            "InternetAddress Prefix"                 = $inetroutes
            "VirtualNetworkGateway Routes"           = $gatewayroutes
            "VirtualNetworkGateway AddressPrefix"    = $vngroutesaddprefix
            "VirtualNetworkGateway NextHopIP"        = $vngroutesnexthop
            "NetworkVirtualAppliance Routes"         = $applianceroutes
            "NetworkVirtualAppliance AddressPrefix"  = $nvaprefix
            "NetworkVirtualAppliance NextHopIP"      = $nvanexthop
        }

        $outputs.Add($output)

        # Clear vars safely
        Clear-Variable -Name @(
            "bgppropagation", "rtname", "internetaccess", "inetroutes", "gatewayroutes",
            "vngroutesaddprefix", "vngroutesnexthop", "nvaprefix", "nvanexthop", "applianceroutes", "rtattached"
        ) -ErrorAction SilentlyContinue
    }
}

# Export to CSV
$outputFilePath = Join-Path $filepath "AzureEffectiveRoutes.csv"
$outputs | Export-Csv -Path $outputFilePath -NoTypeInformation -Force
Write-Host "Effective routes exported to: $outputFilePath"
