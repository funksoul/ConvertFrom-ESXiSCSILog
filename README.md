
ConvertFrom-ESXiSCSILog
=======================

A PowerShell Module converts SCSI Sense Code from ESXi vmkernel.log to human readable format.
This module also contains ConvertFrom-SCSICode which converts SCSI Sense Code.
For more information, please consult the help page of each Cmdlet.



###Installation###

1. Download repo as .zip file and extract it.
2. Change location to the extracted folder and run the installer (.\Install.ps1)
3. Check if the module loaded correctly

```powershell
PS C:\> Get-Module -ListAvailable ConvertFrom-ESXiSCSILog

ModuleType Version    Name                                ExportedCommands
---------- -------    ----                                ----------------
Script     0.0        ConvertFrom-ESXiSCSILog             {ConvertFrom-ESXiSCSILog, ConvertFrom-SCSICode}
```



###Usage###

* Using default parameters (Translate SCSI Codes only)

  ```powershell
  PS C:\> Get-Content -Path vmkernel.log | ConvertFrom-ESXiSCSILog
  ```

  ```
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
  ```



* Translate SCSI Codes and ESXi Host Data (You need to be connected to a vCenter Server)

  ```powershell
  PS C:\> Get-Content -Path vmkernel.log | ConvertFrom-ESXiSCSILog -Resolve -Server vmhost.example.com
  ```

  ```
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
  ```



* Translate from 2017/01/01 (to now)

  ```powershell
  PS C:\> Get-Content -Path vmkernel.log | ConvertFrom-ESXiSCSILog -Resolve -Server vmhost.example.com -Start 2017/01/01
  ```



* Translate a SCSI Sense Data

  ```powershell
  PS C:\> ConvertFrom-SCSICode AdditionalSenseData "0x1d 0x0"
  ```



###Etc###

* An UTC timestamp field of vmkernel.log entry is converted to DateTime object and displayed in localtime.
