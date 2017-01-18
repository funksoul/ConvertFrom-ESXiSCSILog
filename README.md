ConvertFrom-ESXiSCSILog
=======================

A PowerShell Module converts SCSI Sense Code from ESXi vmkernel.log to human
readable format

**Installation**

1.  Download repo as .zip file and extract it to your preferred PowerShell
    module path.

>   PS C:\\\> \$env:PSModulePath -split ';'

1.  Remove extra suffix from the folder name. (-master, -devel, ..etc)

>   C:\\Users\\Foo\\Documents\\WindowsPowerShell\\Modules\\ConvertFrom-ESXiSCSILog

1.  Check if the PowerShell recognizes the module properly.

>   PS C:\\\> Get-Module -ListAvailable ConvertFrom-ESXiSCSILog

1.  Load the module (yay)

PS C:\\\> Import-Module ConvertFrom-ESXiSCSILog
