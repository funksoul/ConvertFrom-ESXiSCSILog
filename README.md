ConvertFrom-ESXiSCSILog
=======================

A PowerShell Module converts SCSI Sense Code from ESXi vmkernel.log to human
readable format

###Installation###

1.  Download repo as .zip file and extract it to your preferred PowerShell module path.
2.  Remove extra suffix from the folder name. (-master, -devel, ..etc)
3.  Check if the PowerShell recognizes the module properly.
4.  Load the module (yay)

`PS C:\> $env:PSModulePath -split ';'`  
`C:\Users\Foo\Documents\WindowsPowerShell\Modules\ConvertFrom-ESXiSCSILog`  
`PS C:\> Get-Module -ListAvailable ConvertFrom-ESXiSCSILog`  
`PS C:\> Import-Module ConvertFrom-ESXiSCSILog`  
