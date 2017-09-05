# Interpreting SCSI sense codes in VMware ESXi and ESX (289902) https://kb.vmware.com/kb/289902
# Understanding SCSI device/target NMP errors/conditions in ESX/ESXi 4.x and ESXi 5.x/6.0 (1030381) https://kb.vmware.com/kb/1030381
# Understanding SCSI plug-in NMP errors/conditions in ESX/ESXi 4.x/5.x/6.0 (2004086) https://kb.vmware.com/kb/2004086

Function ConvertFrom-ESXiSCSILog {
<#
.SYNOPSIS
    Converts SCSI Sense Code from ESXi vmkernel.log to human readable format

.DESCRIPTION
    ESXi records details on failed SCSI I/Os to vmkernel.log in Raw form.
    This Cmdlet translates these details to human readable form as much as possible:
        - SCSI Codes
            . Based on T10 standard documents (http://www.t10.org)
            . Cmd (Operation Code) / Host Code / Device Code / PlugIn Code / Sense Key / Additional Sense Data
        - ESXi Host Data
            . Retrieved using PowerCLI Cmdlets
            . World (Process) Id / Target Device Name / Datastore Name / Storage Adapter Name

.PARAMETER InputObject
    An array of strings which are read from vmkernel.log file.
.PARAMETER Resolve
    Determines whether translate ESXi Host Data or not.
    Used in conjunction with 'Server' parameter.
.PARAMETER UseCache
    Use cached(offline) version of ESXi Host Data when 'Resolve' parameter is $true.
    Caches are saved as .csv files to $env:TMP or /tmp directory depend on the PowerShell Edition.
.PARAMETER Server
    Specifies ESXi Host to contact to retrieve data.
.PARAMETER Start
    Specifies the start date of the log you want to retrieve. The valid formats depend on the local machine regional settings.
.PARAMETER Finish
    Specifies the end date of the log you want to retrieve. The valid formats depend on the local machine regional settings.

.EXAMPLE
    Get-Content -Path vmkernel.log | ConvertFrom-ESXiSCSILog
    Using default parameters (Translate SCSI Codes only)

    === Sample Output ===
    Id                   : 664
    Timestamp            : 2017-02-08 AM 12:35:05
    LogType              : nmp_ThrottleLogForDevice
    Cmd                  : 0xf1
    OperationCode        : ATOMIC TEST AND SET (EMC VMAX/VNX, IBM Storwize)
    from_world           :
    WorldName            :
    to_dev               : naa.6006016006902c008d9626e54f85e111
    DeviceName           : 
    DatastoreName        : 
    on_path              : vmhba3:C0:T1:L1
    StorageAdapterName   : 
    HostDevicePlugInCode : H:0x0 D:0x2 P:0x0
    HostStatus           : NO error
    DeviceStatus         : CHECK CONDITION
    PlugInStatus         : No error.
    SenseDataValidity    : Valid
    SenseData            : 0xe 0x1d 0x0
    SenseKey             : MISCOMPARE
    AdditionalSenseData  : MISCOMPARE DURING VERIFY OPERATION
    Action               : NONE

    Id                   : 665
    Timestamp            : 2017-02-08 AM 12:35:06
    ...

.EXAMPLE
    Get-Content -Path vmkernel.log | ConvertFrom-ESXiSCSILog -Resolve -Server vmhost.example.com
    Translate SCSI Codes and ESXi Host Data (You need to be connected to a vCenter Server)

    === Sample Output ===
    Id                   : 664
    Timestamp            : 2017-02-08 AM 12:35:05
    LogType              : nmp_ThrottleLogForDevice
    Cmd                  : 0xf1
    OperationCode        : ATOMIC TEST AND SET (EMC VMAX/VNX, IBM Storwize)
    from_world           :
    WorldName            :
    to_dev               : naa.6006016006902c008d9626e54f85e111
    DeviceName           : DGC VRAID
    DatastoreName        : VNX5100-01
    on_path              : vmhba3:C0:T1:L1
    StorageAdapterName   : QLogic Corp ISP2432-based 4Gb Fibre Channel to PCI Express HBA
    HostDevicePlugInCode : H:0x0 D:0x2 P:0x0
    HostStatus           : NO error
    DeviceStatus         : CHECK CONDITION
    PlugInStatus         : No error.
    SenseDataValidity    : Valid
    SenseData            : 0xe 0x1d 0x0
    SenseKey             : MISCOMPARE
    AdditionalSenseData  : MISCOMPARE DURING VERIFY OPERATION
    Action               : NONE

    Id                   : 665
    Timestamp            : 2017-02-08 AM 12:35:06
    ...

.EXAMPLE
    Get-Content -Path vmkernel.log | ConvertFrom-ESXiSCSILog -Resolve -Server vmhost.example.com -Start 2017/01/01
    Translate from 2017/01/01 (to now)

.NOTES
    Author                      : Han Ho-Sung
    Author email                : funksoul@insdata.co.kr
    Version                     : 1.1
    Dependencies                : 
    ===Tested Against Environment====
    ESXi Version                : 6.0
    PowerCLI Version            : VMware PowerCLI 6.5.2
    PowerShell Version          : 5.1.15063.502
#>
    Param (
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)][AllowEmptyString()][String[]]$InputObject,
        [Parameter(Mandatory=$false)][switch]$Resolve = $false,
        [Parameter(Mandatory=$false)][switch]$UseCache = $false,
        [Parameter(Mandatory=$false)][PSObject]$Server,
        [Parameter(Mandatory=$false)][DateTime]$Start = (Get-Date 0),
        [Parameter(Mandatory=$false)][DateTime]$Finish = (Get-Date)
    )

    Begin {
        $result = @()
        $ModuleBase = Split-Path $script:MyInvocation.MyCommand.Path

        # Skip HTTPS certificates validation on PowerShell Core (https://github.com/PowerShell/PowerShell/pull/2006)
        if ($PSVersionTable.PSEdition -eq 'Core') {
            $PSDefaultParameterValues.Add("Invoke-WebRequest:SkipCertificateCheck", $true)
        }

        # Convert array to hash table
        filter ArrayToHash {
            begin { $hash = @{} }
            process { $hash[$_.Code] = $_.Description }
            end { return $hash }
        }

        # Contact VMHost in order to fetch details of Worlds, Storage Adapters, SCSI Devices and VMFS Datastore Extents
        if ($Resolve) {
            if ($PSVersionTable.PSEdition -eq 'Desktop') { $tmppath = $Env:TMP }
            else { $tmppath = "/tmp" }

            if (! $UseCache) {
                Try {
                    # Object-by-Name (OBN) selection of VMHost
                    Switch ($Server.GetType().FullName) {
                        "System.String" {
                            Write-Verbose "Contacting VMHost `"$Server`".."
                            $VMHost = Get-VMHost -Name $Server -ErrorAction SilentlyContinue
                            break
                        }
                        "VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl" {
                            $VMHost = $Server
                            break
                        }
                    }

                    Write-Verbose "Fetching list of Worlds.."
                    $worldids = (Get-EsxCli -V2 -VMHost $VMHost).system.process.list.Invoke() | Select-Object @{Name="Code";Expression={$_.Id}}, @{Name="Description";Expression={$_.Name}}
                    $worldids | Export-Csv -NoTypeInformation -Path (Join-Path -Path $tmppath -ChildPath ("cache_" + $VMHost.Name + "_worldids.csv"))
                    $worldids = $worldids | ArrayToHash

                    Write-Verbose "Fetching list of Storage Adapters.."
                    $vmhbas = Get-VMHostHba -VMHost $VMHost | Select-Object @{Name="Code";Expression={$_.Device}}, @{Name="Description";Expression={$_.Model}}
                    $vmhbas | Export-Csv -NoTypeInformation -Path (Join-Path -Path $tmppath -ChildPath ("cache_" + $VMHost.Name + "_vmhbas.csv"))
                    $vmhbas = $vmhbas | ArrayToHash

                    Write-Verbose "Fetching list of SCSI Devices.."
                    $scsiluns_tmp = Get-ScsiLun -VmHost $VMHost
                    $scsiluns = $scsiluns_tmp | Select-Object @{Name="Code";Expression={$_.CanonicalName}}, @{Name="Description";Expression={$_.Vendor + " - " + $_.Model}}
                    $scsiluns | Export-Csv -NoTypeInformation -Path (Join-Path -Path $tmppath -ChildPath ("cache_" + $VMHost.Name + "_scsiluns.csv"))
                    $scsiluns = $scsiluns | ArrayToHash

                    Write-Verbose "Fetching list of VMFS Datastore Extents.."
                    $vmfsextents = @()
                    Get-Datastore -RelatedObject $VMHost | %{ $_.ExtensionData.Info.Vmfs | Select-Object Extent, Name } | %{
                        $VmfsName = $_.Name
                        $_.Extent | %{
                            $row = "" | Select-Object "Code", "Description"
                            $row.Code = $_.DiskName
                            $row.Description = $VmfsName
                            $vmfsextents += $row
                        }
                    }
                    $vmfsextents | Export-Csv -NoTypeInformation -Path (Join-Path -Path $tmppath -ChildPath ("cache_" + $VMHost.Name + "_vmfsextents.csv"))
                    $vmfsextents = $vmfsextents | ArrayToHash

                    $resolved = $true
                }
                Catch {
                    Write-Host "Could not contact VMHost `"$Server`". Resolving WorldName/DeviceName/DatastoreName/StorageAdapterName would fail."
                    Write-Error $_
                    $VMHost = $Server

                    $resolved = $false
                }
            }
            # Use cache to resolve
            else {
                Try {
                    Switch ($Server.GetType().FullName) {
                        "System.String" {
                            $VMHost = $Server
                            break
                        }
                        "VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl" {
                            $VMHost = $Server.Name
                            break
                        }
                    }

                    Write-Verbose "Reading list of Worlds, Storage Adapters, SCSI Devices and VMFS Datastore Extents from cache.."
                    $worldids = Import-Csv -Path (Join-Path -Path $tmppath -ChildPath ("cache_" + $VMHost + "_worldids.csv")) | ArrayToHash
                    $vmhbas = Import-Csv -Path (Join-Path -Path $tmppath -ChildPath ("cache_" + $VMHost + "_vmhbas.csv")) | ArrayToHash
                    $scsiluns = Import-Csv -Path (Join-Path -Path $tmppath -ChildPath ("cache_" + $VMHost + "_scsiluns.csv")) | ArrayToHash
                    $vmfsextents = Import-Csv -Path (Join-Path -Path $tmppath -ChildPath ("cache_" + $VMHost + "_vmfsextents.csv")) | ArrayToHash

                    $resolved = $true
                }
                Catch {
                    Write-Host "Reading from cache failed. Resolving WorldName/DeviceName/StorageAdapterName would fail."
                    Write-Host "Please check ${tmppath}cache_${Server}_*.csv files."
                    Write-Verbose $_
                    $VMHost = $Server

                    $resolved = $false
                }
            }
        }

        $opnums = Import-Csv -Path (Join-Path -Path $ModuleBase -ChildPath 'op-num.csv') | ArrayToHash
        $hoststatuscodes = Import-Csv -Path (Join-Path -Path $ModuleBase -ChildPath 'host-status-codes.csv') | ArrayToHash
        $devstatuscodes = Import-Csv -Path (Join-Path -Path $ModuleBase -ChildPath 'dev-status-codes.csv') | ArrayToHash
        $pluginstatuscodes = Import-Csv -Path (Join-Path -Path $ModuleBase -ChildPath 'plugin-status-codes-esxi5x-60.csv') | ArrayToHash
        $sensekeys = Import-Csv -Path (Join-Path -Path $ModuleBase -ChildPath 'sense-keys.csv') | ArrayToHash
        $additionalsensedata = Import-Csv -Path (Join-Path -Path $ModuleBase -ChildPath 'asc-num.csv') | ArrayToHash

        $id = 0
    }

    Process {
        # Put string[] object to pipeline at once
        $InputObject -split "`n" | ForEach-Object {
            # Pickup log entry which has SCSI status and sense information
            Switch -Regex ($_) {
                # NMP throttled log for device
                "cpu\d+:\d+.*\)NMP:\ nmp_ThrottleLogForDevice:\d+:\ Cmd" {
                    # Process only if the log entry is in valid time range
                    $timestamp = [DateTime]($_ -split " ")[0]
                    if ( ($timestamp -ge $Start) -and ($timestamp -le $Finish) ) {
                        $parsed_data = @{
                            "Cmd" = (($_ -split "Cmd ")[1] -split " ")[0]
                            "to_dev" = (($_ -split "to dev ")[1] -split " ")[0] -replace "`"",""
                            "on_path" = (($_ -split "on path ")[1] -split " ")[0] -replace "`"",""
                            "HostDevicePlugInCode" = ([regex]"H:\d+x\d+ D:\d+x\d+ P:\d+x\d+").Match($_).Value
                            "SenseDataValidity" = (($_ -split " sense data:")[0] -split " ")[-1]
                            "SenseData" = ([regex]"sense data: 0x[0-9a-f]+ 0x[0-9a-f]+ 0x[0-9a-f]+").Match($_).Value -replace "sense data: ",""
                            "Action" = ($_ -split "Act:")[1]
                        }

                        $row = "" | Select-Object "Id", "Timestamp", "LogType", "Cmd", "OperationCode", "from_world", "WorldName", "to_dev", "DeviceName", "DatastoreName", "on_path", "StorageAdapterName", "HostDevicePlugInCode", "HostStatus", "DeviceStatus", "PlugInStatus", "SenseDataValidity", "SenseData", "SenseKey", "AdditionalSenseData", "Action"
                        $row.Id = $id++
                        $row.Timestamp = $timestamp
                        $row.LogType = "nmp_ThrottleLogForDevice"

                        $row.Cmd = $parsed_data.Cmd
                        $row.OperationCode = $opnums.("{0:X2}" -f [Int]$parsed_data.Cmd)

                        $row.to_dev = $parsed_data.to_dev
                        if ($resolved) {
                            $row.DeviceName = $scsiluns.($parsed_data.to_dev)
                            $row.DatastoreName = $vmfsextents.($parsed_data.to_dev)
                        }

                        $row.on_path = $parsed_data.on_path
                        if ($resolved) { $row.StorageAdapterName = $vmhbas.(($parsed_data.on_path -split ":")[0]) }

                        $row.HostDevicePlugInCode = $parsed_data.HostDevicePlugInCode
                        $row.HostStatus = $hoststatuscodes.("0x{0:x2}" -f [Int](($parsed_data.HostDevicePlugInCode -split " H:")[1] -split " ")[0])
                        $row.DeviceStatus = $devstatuscodes.("{0:x2}h" -f [Int](($parsed_data.HostDevicePlugInCode -split " D:")[1] -split " ")[0])
                        $row.PlugInStatus = $pluginstatuscodes.((($parsed_data.HostDevicePlugInCode -split " P:")[1] -split " ")[0])

                        $row.SenseDataValidity = $parsed_data.SenseDataValidity
                        $row.SenseData = $parsed_data.SenseData
                        if ( ($parsed_data.SenseDataValidity -in "Valid","Possible") ) {
                            $row."SenseKey" = $sensekeys.("{0:X}h" -f [Int]($parsed_data.SenseData -split " ")[0])
                            $row."AdditionalSenseData" = $additionalsensedata.("{0:X2}h" -f [Int]($parsed_data.SenseData -split " ")[1] + "/" + "{0:X2}h" -f [Int]($parsed_data.SenseData -split " ")[2])
                        }
                        $row."Action" = $parsed_data.Action

                        $result += $row
                    }
                    break
                }

                # SCSI Device I/O
                "cpu\d+:\d+.*\)ScsiDeviceIO:\ \d+:\ Cmd" {
                    # Process only if the log entry is in valid time range
                    $timestamp = [DateTime]($_ -split " ")[0]
                    if ( ($timestamp -ge $Start) -and ($timestamp -le $Finish) ) {
                        $parsed_data = @{
                            "Cmd" = (($_ -split "Cmd\(.*\) ")[1] -split ",")[0]
                            "from_world" = (($_ -split "from world ")[1] -split " ")[0]
                            "to_dev" = (($_ -split "to dev ")[1] -split " ")[0] -replace "`"",""
                            "HostDevicePlugInCode" = ([regex]"H:\d+x\d+ D:\d+x\d+ P:\d+x\d+").Match($_).Value
                            "SenseDataValidity" = (($_ -split " sense data:")[0] -split " ")[-1]
                            "SenseData" = ([regex]"sense data: 0x[0-9a-f]+ 0x[0-9a-f]+ 0x[0-9a-f]+").Match($_).Value -replace "sense data: ",""
                        }

                        $row = "" | Select-Object "Id", "Timestamp", "LogType", "Cmd", "OperationCode", "from_world", "WorldName", "to_dev", "DeviceName", "DatastoreName", "on_path", "StorageAdapterName", "HostDevicePlugInCode", "HostStatus", "DeviceStatus", "PlugInStatus", "SenseDataValidity", "SenseData", "SenseKey", "AdditionalSenseData", "Action"
                        $row.Id = $id++
                        $row.Timestamp = $timestamp
                        $row.LogType = "ScsiDeviceIO"

                        $row.Cmd = $parsed_data.Cmd
                        $row.OperationCode = $opnums.("{0:X2}" -f [Int]$parsed_data.Cmd)

                        $row.from_world =  $parsed_data.from_world
                        if ($resolved) { $row.WorldName = $worldids.($parsed_data.from_world) }

                        $row.to_dev = $parsed_data.to_dev
                        if ($resolved) {
                            $row.DeviceName = $scsiluns.($parsed_data.to_dev)
                            $row.DatastoreName = $vmfsextents.($parsed_data.to_dev)
                        }

                        $row.HostDevicePlugInCode = $parsed_data.HostDevicePlugInCode
                        $row.HostStatus = $hoststatuscodes.("0x{0:x2}" -f [Int](($parsed_data.HostDevicePlugInCode -split " H:")[1] -split " ")[0])
                        $row.DeviceStatus = $devstatuscodes.("{0:x2}h" -f [Int](($parsed_data.HostDevicePlugInCode -split " D:")[1] -split " ")[0])
                        $row.PlugInStatus = $pluginstatuscodes.((($parsed_data.HostDevicePlugInCode -split " P:")[1] -split " ")[0])

                        $row.SenseDataValidity = $parsed_data.SenseDataValidity
                        $row.SenseData = $parsed_data.SenseData
                        if ( ($parsed_data.SenseDataValidity -in "Valid","Possible") ) {
                            $row."SenseKey" = $sensekeys.("{0:X}h" -f [Int]($parsed_data.SenseData -split " ")[0])
                            $row."AdditionalSenseData" = $additionalsensedata.("{0:X2}h" -f [Int]($parsed_data.SenseData -split " ")[1] + "/" + "{0:X2}h" -f [Int]($parsed_data.SenseData -split " ")[2])
                        }
                        $result += $row
                    }
                    break
                }

                Default {

                }
            }
        }
    }

    End {
        return $result
    }
}

Function ConvertFrom-SCSICode {
<#
.SYNOPSIS
    Converts SCSI Sense Code to human readable format

.DESCRIPTION
    This Cmdlet translates SCSI Codes to human readable form.
        - Based on T10 standard documents (http://www.t10.org)
        - Cmd (Operation Code) / Host Code / Device Code / PlugIn Code / Sense Key / Additional Sense Data

.PARAMETER CodeType
    Specifies SCSI code type. The valid choices are Cmd, HostCode, DeviceCode, PlugInCode, SenseKey and AdditionalSenseData.
.PARAMETER Value
    Specifies SCSI code value to translate.

.EXAMPLE
    ConvertFrom-SCSICode -CodeType Cmd -Value 0x1a
.EXAMPLE
    ConvertFrom-SCSICode -CodeType HostCode -Value 0x5
.EXAMPLE
    ConvertFrom-SCSICode DeviceCode 0x28
.EXAMPLE
    ConvertFrom-SCSICode PlugInCode 0x2
.EXAMPLE
    ConvertFrom-SCSICode SenseKey 0x3
.EXAMPLE
    ConvertFrom-SCSICode AdditionalSenseData "0x1d 0x0"

.NOTES
    Author                      : Han Ho-Sung
    Author email                : funksoul@insdata.co.kr
    Version                     : 1.1
    Dependencies                : 
    ===Tested Against Environment====
    ESXi Version                : 6.0
    PowerCLI Version            : VMware PowerCLI 6.5.2
    PowerShell Version          : 5.1.15063.502
#>
    Param (
        [Parameter(Mandatory=$true, Position=0)][ValidateSet("Cmd", "HostCode", "DeviceCode", "PlugInCode", "SenseKey", "AdditionalSenseData")]$CodeType,
        [Parameter(Mandatory=$true, Position=1)][String]$Value
    )

    Process {
        # Convert array to hash table
        filter ArrayToHash {
            begin { $hash = @{} }
            process { $hash[$_.Code] = $_.Description }
            end { return $hash }
        }

        $CsvFileList = @{}
        $CsvFileList["Cmd"] = "op-num.csv"
        $CsvFileList["HostCode"] = "host-status-codes.csv"
        $CsvFileList["DeviceCode"] = "dev-status-codes.csv"
        $CsvFileList["PlugInCode"] = "plugin-status-codes-esxi5x-60.csv"
        $CsvFileList["SenseKey"] = "sense-keys.csv"
        $CsvFileList["AdditionalSenseData"] = "asc-num.csv"

        $ModuleBase = Split-Path $script:MyInvocation.MyCommand.Path
        $CsvFilePath = Join-Path -Path $ModuleBase -ChildPath $CsvFileList.$CodeType
        $CodeTable = Import-Csv -Path $CsvFilePath | ArrayToHash

        Switch ($CodeType) {
            "Cmd" {
                $result = $CodeTable.("{0:X2}" -f [Int]$Value)
                break
            }
            "HostCode" {
                $result = $CodeTable.("0x{0:x2}" -f [Int]$Value)
                break
            }
            "DeviceCode" {
                $result = $CodeTable.("{0:x2}h" -f [Int]$Value)
                break
            }
            "PlugInCode" {
                $result = $CodeTable.($Value)
                break
            }
            "SenseKey" {
                $result = $CodeTable.("{0:X}h" -f [Int]$Value)
                break
            }
            "AdditionalSenseData" {
                $result = $CodeTable.("{0:X2}h" -f [Int]($Value -split " ")[0] + "/" + "{0:X2}h" -f [Int]($Value -split " ")[1])
                break
            }
        }
        if ($result -ne $null) { return $result }
        else { Write-Verbose "Decode Failed" }
    }
}