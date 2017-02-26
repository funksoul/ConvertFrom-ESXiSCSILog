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
            . Cmd (Op-Code) / Host Code / Device Code / PlugIn Code / Sense Key / Sense Data
        - ESXi Host Data
            . Retrieved using PowerCLI Cmdlets
            . World (Process) Id / Target Device Name / Datastore Name / HBA Name
.PARAMETER InputObject
    An array of strings which are read from vmkernel.log file.
.PARAMETER OutFormat
    Specifies output format. The valid choices are Raw, Decoded and Combined.
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
    Timestamp  : 2016-12-22 PM 1:01:01
    LogType    : nmp_ThrottleLogForDevice
    Cmd        : SERVICE ACTION IN(16)
    WorldFrom  :
    DeviceTo   : naa.50000f000b600d0b
    OnPath     : vmhba2:C0:T0:L0
    HostCode   : NO error
    DeviceCode : CHECK CONDITION
    PlugInCode : No error.
    SenseKey   : ILLEGAL REQUEST
    SenseData  : INVALID COMMAND OPERATION CODE
    Action     : NONE

.EXAMPLE
    Get-Content -Path vmkernel.log | ConvertFrom-ESXiSCSILog -Resolve -Server vmhost.example.com
    Translate SCSI Codes and ESXi Host Data

    === Sample Output ===
    Timestamp  : 2016-12-22 PM 1:01:01
    LogType    : nmp_ThrottleLogForDevice
    Cmd        : SERVICE ACTION IN(16)
    WorldFrom  :
    DeviceTo   : ATA - SAMSUNG HE160HJ (LOCAL-COMPUTE01-01)
    OnPath     : Dell SAS 5/iR Adapter / Ctlr 0 Tgt 0 LUN 0
    HostCode   : NO error
    DeviceCode : CHECK CONDITION
    PlugInCode : No error.
    SenseKey   : ILLEGAL REQUEST
    SenseData  : INVALID COMMAND OPERATION CODE
    Action     : NONE

.EXAMPLE
    Get-Content -Path vmkernel.log | ConvertFrom-ESXiSCSILog -OutFormat Combined -Resolve -Server vmhost.example.com
    Output both of raw and translated data

    === Sample Output ===
    Timestamp  : 2016-12-22 AM 3:10:17
    LogType    : ScsiDeviceIO
    Cmd        : 0x89 COMPARE AND WRITE
    WorldFrom  : 24822716 sdrsInjector
    DeviceTo   : naa.6001405a6c5bb67b44c4af59a3466fcd LIO-ORG - disk01
    OnPath     :
    HostCode   : 0x0 NO error
    DeviceCode : 0x2 CHECK CONDITION
    PlugInCode : 0x0 No error.
    SenseKey   : 0xe MISCOMPARE
    SenseData  : 0x1d/0x0 MISCOMPARE DURING VERIFY OPERATION
    Action     :

.EXAMPLE
    Get-Content -Path vmkernel.log | ConvertFrom-ESXiSCSILog -Resolve -Server vmhost.example.com -Start 2017/01/01
    Translate from 2017/01/01 (to now)

.NOTES
    Author                      : Han Ho-Sung
    Author email                : funksoul@insdata.co.kr
    Version                     : 1.0
    Dependencies                : 
    ===Tested Against Environment====
    ESXi Version                : 6.0.0
    PowerCLI Version            : VMware PowerCLI 6.5 Release 1 build 4624819
    PowerShell Version          : 5.1.14393.693
#>
    Param (
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)][AllowEmptyString()][String[]]$InputObject,
        [ValidateSet("Raw", "Decoded", "Combined")]$OutFormat = "Decoded",
        [Parameter(Mandatory=$false)][switch]$Resolve = $false,
        [Parameter(Mandatory=$false)][switch]$UseCache = $false,
        [Parameter(Mandatory=$false)][PSObject]$Server,
        [Parameter(Mandatory=$false)][DateTime]$Start = (Get-Date 0),
        [Parameter(Mandatory=$false)][DateTime]$Finish = (Get-Date)
    )

    Begin {
        $vmkernellog = @()
        $result = @()
        $ModuleBase = Split-Path $script:MyInvocation.MyCommand.Path

        # Skip HTTPS certificates validation on PowerShell Core (https://github.com/PowerShell/PowerShell/pull/2006)
        if ($PSVersionTable.PSEdition -eq 'Core') {
            $PSDefaultParameterValues.Add("Invoke-WebRequest:SkipCertificateCheck", $true)
        }

        # Setup hash table value (will be used in ArrayToHash filter as an expression) according to the output format
        Switch ($OutFormat) {
            "Raw" {
                $hashvalue = '$_.Code'
                break
            }
            "Decoded" {
                $hashvalue = '$_.Description'
                break
            }
            "Combined" {
                $hashvalue = '$_.Code + " " + $_.Description'
                break
            }
        }

        # Convert array to hash table
        filter ArrayToHash {
            begin { $hash = @{} }
            process { $hash[$_.Code] = Invoke-Expression $hashvalue }
            end { return $hash }
        }

        # Contact VMHost in order to fetch details of World Ids, vmhbas, LUNs, LUN Paths and VMFS Datastore Extents
        if ($Resolve -eq $true) {
            if ($PSVersionTable.PSEdition -eq 'Desktop') {
                $tmppath = $env:TMP
            }
            else {
                $tmppath = "/tmp"
            }

            if ($UseCache -eq $false) {
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

                    Write-Verbose "Fetching list of World IDs.."
                    $worldids = (Get-EsxCli -V2 -VMHost $VMHost).system.process.list.Invoke() | Select-Object @{Name="Code";Expression={$_.Id}}, @{Name="Description";Expression={$_.Name}}
                    $filename = Join-Path -Path $tmppath -ChildPath ("cache_" + $VMHost.Name + "_worldids.csv")
                    $worldids | Export-Csv -NoTypeInformation -Path $filename
                    $worldids = $worldids | ArrayToHash

                    Write-Verbose "Fetching list of vmhbas.."
                    $vmhbas = Get-VMHostHba -VMHost $VMHost | Select-Object @{Name="Code";Expression={$_.Device}}, @{Name="Description";Expression={$_.Model}}
                    $filename = Join-Path -Path $tmppath -ChildPath ("cache_" + $VMHost.Name + "_vmhbas.csv")
                    $vmhbas | Export-Csv -NoTypeInformation -Path $filename
                    $vmhbas = $vmhbas | ArrayToHash

                    $scsiluns_tmp = Get-ScsiLun -VmHost $VMHost

                    Write-Verbose "Fetching list of LUNs.."
                    $scsiluns = $scsiluns_tmp | Select-Object @{Name="Code";Expression={$_.CanonicalName}}, @{Name="Description";Expression={$_.Vendor + " - " + $_.Model}}
                    $filename = Join-Path -Path $tmppath -ChildPath ("cache_" + $VMHost.Name + "_scsiluns.csv")
                    $scsiluns | Export-Csv -NoTypeInformation -Path $filename
                    $scsiluns = $scsiluns | ArrayToHash

                    Write-Verbose "Fetching list of LUN Paths.."
                    $scsilunpaths = Get-ScsiLunPath -ScsiLun $scsiluns_tmp | Select-Object @{Name="Code";Expression={$_.Name}}, @{Name="Description";Expression={ `
                        ($vmhbas.(($_.Name -split ":")[0]) -replace "^vmhba\d{1,2} ","") + " /" + `
                        " Ctlr " + $_.Name[-7] + `
                        " Tgt " + $_.Name[-4] + `
                        " LUN " + $_.Name[-1] `
                        }
                    }
                    $filename = Join-Path -Path $tmppath -ChildPath ("cache_" + $VMHost.Name + "_scsilunpaths.csv")
                    $scsilunpaths | Export-Csv -NoTypeInformation -Path $filename
                    $scsilunpaths = $scsilunpaths | ArrayToHash

                    Write-Verbose "Fetching VMFS Datastore Extents.."
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
                    $filename = Join-Path -Path $tmppath -ChildPath ("cache_" + $VMHost.Name + "_vmfsextents.csv")
                    $vmfsextents | Export-Csv -NoTypeInformation -Path $filename
                    $vmfsextents = $vmfsextents | ArrayToHash

                    $resolved = $true
                }
                Catch {
                    Write-Host "Could not contact VMHost `"$Server`". Resolving DeviceTo/Path/WorldFrom would fail."
                    Write-Verbose $_
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

                    Write-Verbose "Reading World Ids, vmhbas, LUNs and LUN Paths from cache.."
                    $filename = Join-Path -Path $tmppath -ChildPath ("cache_" + $VMHost + "_worldids.csv")
                    $worldids = Import-Csv $filename | ArrayToHash
                    $filename = Join-Path -Path $tmppath -ChildPath ("cache_" + $VMHost + "_vmhbas.csv")
                    $vmhbas = Import-Csv $filename | ArrayToHash
                    $filename = Join-Path -Path $tmppath -ChildPath ("cache_" + $VMHost + "_scsiluns.csv")
                    $scsiluns = Import-Csv $filename | ArrayToHash
                    $filename = Join-Path -Path $tmppath -ChildPath ("cache_" + $VMHost + "_scsilunpaths.csv")
                    $scsilunpaths = Import-Csv $filename | ArrayToHash
                    $filename = Join-Path -Path $tmppath -ChildPath ("cache_" + $VMHost + "_vmfsextents.csv")
                    $vmfsextents = Import-Csv $filename | ArrayToHash

                    $resolved = $true
                }
                Catch {
                    Write-Host "Reading World Ids, vmhbas, LUNs and LUN Paths from cache failed. Resolving DeviceTo/Path/WorldFrom would fail."
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
        $sensedata = Import-Csv -Path (Join-Path -Path $ModuleBase -ChildPath 'asc-num.csv') | ArrayToHash
    }

    Process {
        # Put string[] object to pipeline at once
        $vmkernellog += $InputObject
    }

    End {
        $result = @()
        $vmkernellog | ForEach-Object {

            # Pickup log entry which has SCSI status and sense information
            Switch -Regex ($_) {

                # NMP throttle log for device
                "cpu\d+:\d+\)NMP:\ nmp_ThrottleLogForDevice:\d+:\ Cmd" {
                    $str_tmp = $_ -split " "
                    $timestamp = [datetime]$str_tmp[0]

                    # Process only if the log entry is in valid time range
                    if ( ($timestamp -ge $Start) -and ($timestamp -le $Finish) ) {
                        $row = "" | Select-Object "Timestamp", "LogType", "Cmd", "WorldFrom", "DeviceTo", "OnPath", "HostCode", "DeviceCode", "PlugInCode", "SenseKey", "SenseData", "Action"
                        $row."Timestamp" = [datetime]$str_tmp[0]
                        $row."LogType" = "nmp_ThrottleLogForDevice"
                        $row."Cmd" = $opnums.($str_tmp[4])
                        $scsilun = $str_tmp[9] -replace "`"",""
                        if (($Resolve -eq $true) -and ($resolved -eq $true) -and ($scsiluns.$scsilun -ne $null)) {
                            $row."DeviceTo" = $scsiluns.$scsilun
                            if ($vmfsextents.$scsilun -ne $null) {
                                $row."DeviceTo" += " (" + ($vmfsextents.$scsilun -split " ")[-1] + ")"
                            }
                        } else {
                            $row."DeviceTo" = $scsilun
                        }
                        $scsilunpath = $str_tmp[12] -replace "`"",""
                        if (($Resolve -eq $true) -and ($resolved -eq $true) -and ($scsilunpaths.$scsilunpath -ne $null)) {
                            $row."OnPath" = $scsilunpaths.$scsilunpath
                        } else {
                            $row."OnPath" = $scsilunpath
                        }
                        $row."HostCode" = $hoststatuscodes.($str_tmp[14] -replace "^H:","")
                        $row."DeviceCode" = $devstatuscodes.($str_tmp[15] -replace "^D:","")
                        $row."PlugInCode" = $pluginstatuscodes.($str_tmp[16] -replace "^P:","")
                        if ( ($str_tmp.Count -gt 17) -and ($str_tmp[17] -in "Valid","Possible") ) {
                            $row."SenseKey" = $sensekeys.($str_tmp[20])
                            $row."SenseData" = $sensedata.($str_tmp[21] + "/" + ($str_tmp[22] -replace "\.$",""))
                        }
                        $row."Action" = $str_tmp[23] -replace "^Act:",""
                        $result += $row
                    }
                    break;
                }

                # SCSI device I/O
                "cpu\d+:\d+\)ScsiDeviceIO:\ \d+:\ Cmd" {
                    $str_tmp = $_ -split " "
                    $timestamp = [datetime]$str_tmp[0]

                    if ( ($timestamp -ge $Start) -and ($timestamp -le $Finish) ) {
                        $row = "" | Select-Object "Timestamp", "LogType", "Cmd", "WorldFrom", "DeviceTo", "OnPath", "HostCode", "DeviceCode", "PlugInCode", "SenseKey", "SenseData", "Action"
                        $row."Timestamp" = [datetime]$str_tmp[0]
                        $row."LogType" = "ScsiDeviceIO"
                        $row."Cmd" = $opnums.($str_tmp[4] -replace ",$","")
                        $worldid = $str_tmp[9]
                        if (($Resolve -eq $true) -and ($resolved -eq $true) -and ($worldids.$worldid -ne $null)) {
                            $row."WorldFrom" = $worldids.$worldid
                        } else {
                            $row."WorldFrom" = $worldid
                        }
                        $scsilun = $str_tmp[12] -replace "`"",""
                        if (($Resolve -eq $true) -and ($resolved -eq $true) -and ($scsiluns.$scsilun -ne $null)) {
                            $row."DeviceTo" = $scsiluns.$scsilun
                            if ($vmfsextents.$scsilun -ne $null) {
                                $row."DeviceTo" += " (" + ($vmfsextents.$scsilun -split " ")[-1] + ")"
                            }
                        } else {
                            $row."DeviceTo" = $scsilun
                        }
                        $row."HostCode" = $hoststatuscodes.($str_tmp[14] -replace "^H:","")
                        $row."DeviceCode" = $devstatuscodes.($str_tmp[15] -replace "^D:","")
                        $row."PlugInCode" = $pluginstatuscodes.($str_tmp[16] -replace "^P:","")

                        if ( ($str_tmp.Count -gt 17) -and ($str_tmp[17] -in "Valid","Possible") ) {
                            $row."SenseKey" = $sensekeys.($str_tmp[20])
                            $row."SenseData" = $sensedata.($str_tmp[21] + "/" + ($str_tmp[22] -replace "\.$",""))
                        }
                        $result += $row
                    }
                    break;
                }
            }
        }
        $result
    }
}

Function ConvertFrom-SCSICode {
<#
.SYNOPSIS
    Converts SCSI Sense Code to human readable format
.DESCRIPTION
    This Cmdlet translates SCSI Codes to human readable form.
        - Based on T10 standard documents (http://www.t10.org)
        - Cmd (Op-Code) / Host Code / Device Code / PlugIn Code / Sense Key / Sense Data
.PARAMETER CodeType
    Specifies SCSI code type. The valid choices are Cmd, HostCode, DeviceCode, PlugInCode, SenseKey and SenseData.
.PARAMETER Value
    Specifies SCSI code value to translate.
.EXAMPLE
    ConvertFrom-SCSICode -CodeType Cmd -Value '0x9e'
.EXAMPLE
    ConvertFrom-SCSICode -CodeType SenseData -Value '0x1d 0x0'

.NOTES
    Author                      : Han Ho-Sung
    Author email                : funksoul@insdata.co.kr
    Version                     : 1.0
    Dependencies                : 
    ===Tested Against Environment====
    ESXi Version                : 6.0.0
    PowerCLI Version            : VMware PowerCLI 6.5 Release 1 build 4624819
    PowerShell Version          : 5.1.14393.693
#>
    Param (
        [Parameter(Mandatory=$true, Position=0)][ValidateSet("Cmd", "HostCode", "DeviceCode", "PlugInCode", "SenseKey", "SenseData")]$CodeType,
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
        $CsvFileList["SenseData"] = "asc-num.csv"

        $ModuleBase = Split-Path $script:MyInvocation.MyCommand.Path
        $CsvFilePath = Join-Path -Path $ModuleBase -ChildPath $CsvFileList.$CodeType
        $CodeTable = Import-Csv -Path $CsvFilePath | ArrayToHash
        # Additional Sense Data can be in the form of 'ASC/ASCQ' or 'ASC ASCQ'
        $result = $CodeTable.($Value -replace ' ','/')

        if ($result -ne $null) {
            return $result
        } else {
            Write-Verbose "Decode Failed"
        }
    }
}
