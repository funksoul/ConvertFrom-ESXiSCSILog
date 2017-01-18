ConvertFrom-ESXiSCSILog
=======================

A PowerShell Module converts SCSI Sense Code from ESXi vmkernel.log to human readable format.  
This module also contains ConvertFrom-SCSICode which converts SCSI Sense Code.  
For more information, please consult the help page of each Cmdlet.  

###Installation###

1.  Download repo as .zip file and extract it to your preferred PowerShell module path.
2.  Remove extra suffix from the folder name. (-master, -devel, ..etc)
3.  Check if the PowerShell recognizes the module properly.
4.  Load the module (yay)

`PS C:\> $env:PSModulePath -split ';'`  
_`C:\Users\Foo\Documents\WindowsPowerShell\Modules\ConvertFrom-ESXiSCSILog`_  
`PS C:\> Get-Module -ListAvailable ConvertFrom-ESXiSCSILog`  
`PS C:\> Import-Module ConvertFrom-ESXiSCSILog`  

###Usage###

* Using default parameters (Translate SCSI Codes only)

`PS C:\> Get-Content -Path vmkernel.log | ConvertFrom-ESXiSCSILog`  

`=== Sample Output ===`  
`Timestamp  : 2016-12-22 PM 1:01:01`  
`LogType    : nmp_ThrottleLogForDevice`  
`Cmd        : SERVICE ACTION IN(16)`  
`WorldFrom  :`  
`DeviceTo   : naa.50000f000b600d0b`  
`OnPath     : vmhba2:C0:T0:L0`  
`HostCode   : NO error`  
`DeviceCode : CHECK CONDITION`  
`PlugInCode : No error.`  
`SenseKey   : ILLEGAL REQUEST`  
`SenseData  : INVALID COMMAND OPERATION CODE`  
`Action     : NONE`  


* Translate SCSI Codes and ESXi Host Data

`PS C:\> Get-Content -Path vmkernel.log | ConvertFrom-ESXiSCSILog -Resolve -Server vmhost.example.com`  

`=== Sample Output ===`  
`Timestamp  : 2016-12-22 PM 1:01:01`  
`LogType    : nmp_ThrottleLogForDevice`  
`Cmd        : SERVICE ACTION IN(16)`  
`WorldFrom  :`  
`DeviceTo   : ATA - SAMSUNG HE160HJ (LOCAL-COMPUTE01-01)`  
`OnPath     : Dell SAS 5/iR Adapter / Ctlr 0 Tgt 0 LUN 0`  
`HostCode   : NO error`  
`DeviceCode : CHECK CONDITION`  
`PlugInCode : No error.`  
`SenseKey   : ILLEGAL REQUEST`  
`SenseData  : INVALID COMMAND OPERATION CODE`  
`Action     : NONE`  


* Output both of raw and translated data

`PS C:\> Get-Content -Path vmkernel.log | ConvertFrom-ESXiSCSILog -OutFormat Combined -Resolve -Server vmhost.example.com`  

`=== Sample Output ===`  
`Timestamp  : 2016-12-22 AM 3:10:17`  
`LogType    : ScsiDeviceIO`  
`Cmd        : 0x89 COMPARE AND WRITE`  
`WorldFrom  : 24822716 sdrsInjector`  
`DeviceTo   : naa.6001405a6c5bb67b44c4af59a3466fcd LIO-ORG - disk01`  
`OnPath     :`  
`HostCode   : 0x0 NO error`  
`DeviceCode : 0x2 CHECK CONDITION`  
`PlugInCode : 0x0 No error.`  
`SenseKey   : 0xe MISCOMPARE`  
`SenseData  : 0x1d/0x0 MISCOMPARE DURING VERIFY OPERATION`  
`Action     :`  


* Translate from 2017/01/01 (to now)

`PS C:\> Get-Content -Path vmkernel.log | ConvertFrom-ESXiSCSILog -Resolve -Server vmhost.example.com -Start 2017/01/01`  
