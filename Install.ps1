$ModuleName = 'ConvertFrom-ESXiSCSILog'
$FileList = Get-Content FILES.lst

# Select module installation folder between PowerShell module paths
$itemsListArray = $env:PSModulePath -split ';'

$itemsList = @{}
$i = 0
$itemsListArray | %{
    $key = $i++
    $itemsList[$key] =  $_
}

$itemsList.Keys | Sort-Object | %{ Write-Host $_":" $itemsList[$_] }

$itemIndex = $itemsListArray.Count
do {
    Write-Host -NoNewline -ForegroundColor green "Please select destination path: "
    [int]$itemIndex = Read-Host
} until ($itemsList.ContainsKey($itemIndex)) 

$Dest = Join-Path -Path $itemsList[[int]$itemIndex] -ChildPath $ModuleName

# Do not overwrite if it exist already
if (-not (Test-Path $Dest)) {
    Write-Host "Creating destination folder `"$Dest`".."
    New-Item -ItemType Directory -Path $Dest | Out-Null

    # Copy source files to destination folder
    Write-Host "Copying files.."
    $FileList | %{
        Copy-Item $_ $Dest
    }

    # Unblock script file (for your convenience)
    Write-Host "Running `"Unblock-File`" Cmdlet.."
    Unblock-File (Join-Path -Path $Dest -ChildPath '*') -Confirm:$true

    Write-Host "Module installed to `"$Dest`" successfully."

    # (Re)Load the module
    if (Get-Module $ModuleName) {
        Write-Host "Removing current module `"$ModuleName`".."
        Remove-Module $ModuleName
    }

    Write-Host "Importing module `"$ModuleName`".."
    Import-Module $ModuleName
}
else {
    Write-Host -ForegroundColor red "Destination folder `"$Dest`" exists. Please remove it and try again."
}
