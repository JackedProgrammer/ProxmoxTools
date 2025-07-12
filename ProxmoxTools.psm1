
<#
.SYNOPSIS
Connects to a Proxmox server using an API Token.

.DESCRIPTION
Establishes a connection to the specified Proxmox server using an API token and returns a connection object containing headers and base URI for future API requests.

.PARAMETER ProxmoxServer
The hostname or IP address of the Proxmox server.

.PARAMETER TokenID
The API token ID including the user and token name (e.g. root@pam!mytoken).

.PARAMETER Secret
The secret key for the API token.

.EXAMPLE
$connection = Connect-ProxmoxAPIToken -ProxmoxServer "192.168.1.10" -TokenID "root@pam!mytoken" -Secret "s3cr3t"
#>
function Connect-ProxmoxAPIToken {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [String] $ProxmoxServer,
        [Parameter(Mandatory=$true)]
        [String] $TokenID,
        [Parameter(Mandatory=$true)]
        [String] $Secret
    )

    $headers = @{}
    $headers.Authorization = "PVEAPIToken $TokenID=$Secret"
    $baseUri = "https://$($ProxmoxServer):8006/api2/json"
    $uri = "$baseUri/version"

    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -ContentType "application/json" -Method Get -SkipCertificateCheck

        return @{
            baseUri = $baseUri
            headers = $headers
            proxmoxServer = $ProxmoxServer
        }
    } catch {
        throw "Error in trying to get information from Proxmox Server $($ProxmoxServer): error: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
Retrieves one or more nodes from a Proxmox server.

.DESCRIPTION
Gets information about available nodes in the Proxmox cluster. Optionally filters for a specific node by name.

.PARAMETER Connection
The connection object returned by Connect-ProxmoxAPIToken.

.PARAMETER NodeName
Optional. The name of a specific node to retrieve.

.EXAMPLE
Get-ProxmoxNode -Connection $connection
Get-ProxmoxNode -Connection $connection -NodeName "pve01"
#>
function Get-ProxmoxNode {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [Object] $Connection,
        [Parameter()]
        [String] $NodeName
    )

    $uri = "$($Connection.baseUri)/nodes"

    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $Connection.headers -ContentType "application/json" -Method Get -SkipCertificateCheck

        if ($NodeName) {
            $response = $response.data | Where-Object node -eq $NodeName | Select-Object id, status, node
            if ($response) {
                return $response
            } else {
                throw "No nodes $NodeName found in proxmox server $($Connection.proxmoxServer)"
            }
        } else {
            return $response.data | Select-Object id, status, node
        }
    } catch {
        throw "Error in trying to get information from Proxmox Server $($Connection.proxmoxServer): error: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
Retrieves storage information for a given Proxmox node.

.DESCRIPTION
Gets a list of storage units or details about a specific storage on a given node.

.PARAMETER Connection
The connection object returned by Connect-ProxmoxAPIToken.

.PARAMETER Node
The name of the node to query.

.PARAMETER StorageName
Optional. The name of a specific storage to retrieve.

.EXAMPLE
Get-ProxmoxStorage -Connection $connection -Node "pve01"
Get-ProxmoxStorage -Connection $connection -Node "pve01" -StorageName "local-lvm"
#>
function Get-ProxmoxStorage {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [Object] $Connection,
        [Parameter(Mandatory=$true)]
        [String] $Node,
        [Parameter()]
        [String] $StorageName
    )

    $uri = "$($Connection.baseUri)/nodes/$Node/storage"

    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $Connection.headers -ContentType "application/json" -Method Get -SkipCertificateCheck

        if ($StorageName) {
            $response = $response.data | Where-Object storage -eq $StorageName | Select-Object storage, content, used_fraction, avail

            if ($response) {
                return $response
            } else {
                throw "No storage $StorageName found in proxmox server $($Connection.proxmoxServer)"
            }
        } else {
            return $response.data | Select-Object storage, content, used_fraction, avail
        }
    } catch {
        throw "Error in trying to get information from Proxmox Server $($Connection.proxmoxServer): error: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
Adds ISO or template content to a Proxmox storage via URL.

.DESCRIPTION
Downloads ISO images or templates from a specified URL to a storage unit in a Proxmox node.

.PARAMETER Connection
The connection object returned by Connect-ProxmoxAPIToken.

.PARAMETER Node
The name of the Proxmox node.

.PARAMETER Storage
The name of the target storage.

.PARAMETER Content
The type of content being uploaded. Supported: iso, vztmpl, import.

.PARAMETER FileName
The filename to save as.

.PARAMETER URL
The URL from which the content is downloaded.

.EXAMPLE
Add-ContentProxmox -Connection $connection -Node "pve01" -Storage "local" -Content "iso" -FileName "ubuntu.iso" -URL "https://example.com/ubuntu.iso"
#>
function Add-ContentProxmox {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [Object] $Connection,
        [Parameter(Mandatory=$true)]
        [String] $Node,
        [Parameter(Mandatory=$true)]
        [String] $Storage,
        [Parameter(Mandatory=$true)]
        [ValidateSet("iso","vztmpl","import")]
        [String] $Content,
        [Parameter(Mandatory=$true)]
        [String] $FileName,
        [Parameter(Mandatory=$true)]
        [String] $URL
    )

    $uri = "$($Connection.baseUri)/nodes/$Node/storage/$Storage/download-url"

    try {
        $body = @{
            content = $Content
            filename = $FileName
            node = $Node
            storage = $Storage
            url = $URL
        }

        $response = Invoke-RestMethod -Uri $uri -Headers $Connection.headers -Method Post -ContentType "application/json" -Body ($body | ConvertTo-Json -Depth 100) -SkipCertificateCheck

        return $response.data
    } catch {
        throw "Error in trying to add content to Proxmox Server $($Connection.proxmoxServer): error: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
Retrieves a list of content items stored on a specific Proxmox storage.

.DESCRIPTION
Returns content metadata for the selected storage unit on the specified node.

.PARAMETER Connection
The connection object returned by Connect-ProxmoxAPIToken.

.PARAMETER Node
The name of the node hosting the storage.

.PARAMETER Storage
The name of the storage to inspect.

.EXAMPLE
Get-ContentProxmox -Connection $connection -Node "pve01" -Storage "local"
#>
function Get-ContentProxmox {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [Object] $Connection,
        [Parameter(Mandatory=$true)]
        [String] $Node,
        [Parameter(Mandatory=$true)]
        [String] $Storage
    )

    $uri = "$($Connection.baseUri)/nodes/$Node/storage/$Storage/content"

    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $Connection.headers -Method Get -ContentType "application/json" -SkipCertificateCheck

        return $response.data
    } catch {
        throw "Error in trying to get content from Proxmox Server $($Connection.proxmoxServer): error: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
Retrieves virtual machines from a specific Proxmox node.

.DESCRIPTION
Lists all virtual machines on a given Proxmox node or returns details of a specified VM.

.PARAMETER Connection
The connection object returned by Connect-ProxmoxAPIToken.

.PARAMETER Node
The name of the Proxmox node to query.

.PARAMETER VMName
Optional. The name of a specific VM to retrieve.

.EXAMPLE
Get-ProxmoxVM -Connection $connection -Node "pve01"
Get-ProxmoxVM -Connection $connection -Node "pve01" -VMName "myvm"
#>
function Get-ProxmoxVM{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [Object]
        $Connection,
        [Parameter(Mandatory=$true)]
        [String]
        $Node,
        [Parameter()]
        [String]
        $VMName
    )

    $uri="$($Connection.baseUri)/nodes/$Node/qemu"

    try{
        $response=Invoke-RestMethod -Uri $uri -Headers $Connection.headers -Method Get -ContentType "application/json" -SkipCertificateCheck

        if($VMName){
            $response=$response.data | where name -eq $VMName
            if($response){
                return $response
            }else{
                throw "No VM $VMName found in proxmox server $($Connection.proxmoxServer)"
            }
        }else{
            $response=$response.data
            return $response
        }
    }catch{
        throw "Error in trying to get content from Proxmox Server $($Connection.proxmoxServer): error: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
Creates a new virtual machine on a Proxmox node.

.DESCRIPTION
Creates a new VM with specified configuration such as memory, CPU, OS type, and attached ISO.

.PARAMETER Connection
The connection object returned by Connect-ProxmoxAPIToken.

.PARAMETER Node
The node on which to create the VM.

.PARAMETER VMName
The desired name for the virtual machine.

.PARAMETER MemoryInGB
The amount of memory to allocate to the VM, in gigabytes.

.PARAMETER CPU
The CPU type to use for the VM. Only "x86-64-v2-AES" is currently supported.

.PARAMETER Sockets
Number of CPU sockets for the VM.

.PARAMETER Cores
Number of CPU cores per socket.

.PARAMETER OSType
Operating system type. Currently only "l26" (Linux 2.6+) is supported.

.PARAMETER Storage
The name of the storage where the VM disk will be created.

.PARAMETER StorageSizeInGB
Size of the VM's disk in gigabytes.

.PARAMETER ISO
The ISO image to mount as a CD-ROM.

.EXAMPLE
New-ProxmoxVM -Connection $connection -Node "pve01" -VMName "newvm" -MemoryInGB 4 -CPU "x86-64-v2-AES" -Sockets 1 -Cores 2 -OSType "l26" -Storage "local-lvm" -StorageSizeInGB 20 -ISO "local:iso/ubuntu.iso"
#>
function New-ProxmoxVM{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [Object]
        $Connection,
        [Parameter(Mandatory=$true)]
        [String]
        $Node,
        [Parameter(Mandatory=$true)]
        [String]
        $VMName,
        [Parameter(Mandatory=$true)]
        [Int16]
        $MemoryInGB,
        [Parameter(Mandatory=$true)]
        [ValidateSet("x86-64-v2-AES")]
        [String]
        $CPU,
        [Parameter(Mandatory=$true)]
        [Int16]
        $Sockets,
        [Parameter(Mandatory=$true)]
        [Int16]
        $Cores,
        [Parameter(Mandatory=$true)]
        [ValidateSet("l26")]
        [String]
        $OSType,
        [Parameter(Mandatory=$true)]
        [String]
        $Storage,
        [Parameter(Mandatory=$true)]
        [Int16]
        $StorageSizeInGB,
        [Parameter(Mandatory=$true)]
        [String]
        $ISO
    )

    $uri="$($Connection.baseUri)/nodes/$Node/qemu"

    try{
        $vmID=(Get-ProxmoxVM -Connection $Connection -Node $Node | sort vmid -Descending | select -first 1).vmid+1

        $body=@{
            vmid=$vmID
            name=$VMName
            memory=$($MemoryInGB*1024)
            cpu=$CPU
            sockets=$Sockets
            cores=$Cores
            ostype=$OSType
            scsihw="virtio-scsi-pci"
            scsi0="$($Storage):$($StorageSizeInGB),discard=on"
            numa=0
            agent=1
            net0="virtio,bridge=vmbr0"
            ide2="$($ISO),media=cdrom"
        }

        $response=Invoke-RestMethod -Uri $uri -Headers $Connection.headers -Method Post -ContentType "application/json" -Body $($body | ConvertTo-Json -Depth 100) -SkipCertificateCheck

        $response=$response.data
        return $response
    }catch{
        throw "Error in trying to add vm to Proxmox Server $($Connection.proxmoxServer): error $($_.Exception.Message)"
    }


}

<#
.SYNOPSIS
Deletes a virtual machine from a Proxmox node.

.DESCRIPTION
Finds the virtual machine by name and deletes it using its VM ID.

.PARAMETER Connection
The connection object returned by Connect-ProxmoxAPIToken.

.PARAMETER Node
The name of the node where the VM resides.

.PARAMETER VMName
The name of the virtual machine to delete.

.EXAMPLE
Remove-ProxmoxVM -Connection $connection -Node "pve01" -VMName "oldvm"
#>
function Remove-ProxmoxVM{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [Object]
        $Connection,
        [Parameter(Mandatory=$true)]
        [String]
        $Node,
        [Parameter(Mandatory=$true)]
        [String]
        $VMName
    )

    $VM=Get-ProxmoxVM -Connection $Connection -Node $Node -VMName $VMName

    $uri="$($Connection.baseUri)/nodes/$Node/qemu/$($VM.vmid)"

    try{
        $response=Invoke-RestMethod -uri $uri -Headers $Connection.headers -Method Delete -ContentType "application/json" -SkipCertificateCheck
        $response=$response.data
        return $response
    }catch{
        throw "Error in trying to remove VM $VMName from Proxmox Server $($Connection.proxmoxServer): error: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
Starts a virtual machine on a Proxmox node.

.DESCRIPTION
Starts the specified virtual machine by its name using the QEMU interface.

.PARAMETER Connection
The connection object returned by Connect-ProxmoxAPIToken.

.PARAMETER Node
The node that hosts the VM.

.PARAMETER VMName
The name of the virtual machine to start.

.EXAMPLE
Start-ProxmoxVM -Connection $connection -Node "pve01" -VMName "myvm"
#>
function Start-ProxmoxVM{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [Object]
        $Connection,
        [Parameter(Mandatory=$true)]
        [String]
        $Node,
        [Parameter(Mandatory=$true)]
        [String]
        $VMName
    )

    $VM=Get-ProxmoxVM -Connection $Connection -Node $Node -VMName $VMName

    $uri="$($Connection.baseUri)/nodes/$Node/qemu/$($VM.vmid)/status/start"

    $body=@{
        vmid=$VM.vmid
        node=$Node
    }

    try{
        $response=Invoke-RestMethod -uri $uri -Headers $Connection.headers -Method Post -Body $($body | ConvertTo-Json -Depth 100) -ContentType "application/json" -SkipCertificateCheck
        $response=$response.data
        return $response
    }catch{
        throw "Error in trying to start VM $VMName from Proxmox Server $($Connection.proxmoxServer): error: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
Shuts down a virtual machine on a Proxmox node.

.DESCRIPTION
Performs a graceful shutdown of a specified VM using the QEMU shutdown API.

.PARAMETER Connection
The connection object returned by Connect-ProxmoxAPIToken.

.PARAMETER Node
The name of the node hosting the VM.

.PARAMETER VMName
The name of the virtual machine to shut down.

.EXAMPLE
Stop-ProxmoxVM -Connection $connection -Node "pve01" -VMName "myvm"
#>
function Stop-ProxmoxVM{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [Object]
        $Connection,
        [Parameter(Mandatory=$true)]
        [String]
        $Node,
        [Parameter(Mandatory=$true)]
        [String]
        $VMName
    )

    $VM=Get-ProxmoxVM -Connection $Connection -Node $Node -VMName $VMName

    $uri="$($Connection.baseUri)/nodes/$Node/qemu/$($VM.vmid)/status/shutdown"

    $body=@{
        vmid=$VM.vmid
        node=$Node
    }

    try{
        $response=Invoke-RestMethod -uri $uri -Headers $Connection.headers -Method Post -Body $($body | ConvertTo-Json -Depth 100) -ContentType "application/json" -SkipCertificateCheck
        $response=$response.data
        return $response
    }catch{
        throw "Error in trying to shutdown VM $VMName from Proxmox Server $($Connection.proxmoxServer): error: $($_.Exception.Message)"
    }
}

