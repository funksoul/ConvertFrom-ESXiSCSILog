$ModuleName = 'ConvertFrom-ESXiSCSILog'
$FileList = Get-Content FILES.lst

# Select module installation folder between PowerShell module paths
$itemsListArray = $env:PSModulePath -split ';'

$itemsList = @{}
$i = 0
$itemsListArray | ForEach-Object {
    $key = $i++
    $itemsList[$key] =  $_
}

Write-Host "Current PowerShell Module path(s):"
$itemsList.Keys | Sort-Object | %{
    Write-Host -NoNewline -ForegroundColor Green "  $_"
    Write-Host ":" $itemsList[$_]
}

$itemIndex = $itemsListArray.Count
do {
    Write-Host -NoNewline -ForegroundColor green "Please select destination path: "
    [int]$itemIndex = Read-Host
} until ($itemsList.ContainsKey($itemIndex)) 

$Dest = Join-Path -Path $itemsList[[int]$itemIndex] -ChildPath $ModuleName

# Do not overwrite if it exist already
if (-not (Test-Path $Dest)) {
    Write-Host -NoNewline "Creating destination folder `"$Dest`".."
    Try {
        New-Item -ItemType Directory -Path $Dest -ErrorAction Stop | Out-Null
    }
    Catch {
        Write-Host -ForegroundColor Red "[FAIL]`n  Could not create destination folder, stop installation."
        exit 1
    }
    Write-Host -ForegroundColor Green "[OK]"

    # Copy source files to destination folder
    Write-Host -NoNewline "Copying files.."
    $FileList | %{
        Try {
            Copy-Item $_ $Dest -ErrorAction Stop
        }
        Catch {
            Write-Host -ForegroundColor Red "[FAIL]`n  Could not copy files, stop installation."
            exit 1
        }
    }
    Write-Host -ForegroundColor Green "[OK]"

    # Unblock script file (for your convenience)
    Write-Host -NoNewline "Running `"Unblock-File`" Cmdlet.."
    Try {
        Unblock-File (Join-Path -Path $Dest -ChildPath '*') -ErrorAction Stop
    }
    Catch {
        Write-Host -ForegroundColor Red "[FAIL]`n  Could not unblock file, stop installation."
        exit 1
    }
    Write-Host -ForegroundColor Green "[OK]"

    # (Re)Load the module
    if (Get-Module $ModuleName) {
        Write-Host -NoNewline "Removing current module `"$ModuleName`".."
        Try {
            Remove-Module $ModuleName -ErrorAction Stop
        }
        Catch {
            Write-Host -ForegroundColor Red "[FAIL]`n  Could not remove current module, stop proceeding.`n  If you don't remove current module first, new module would not be loaded."
            exit 1
        }
        Write-Host -ForegroundColor Green "[OK]"
    }

    Write-Host -NoNewline "Importing new module `"$ModuleName`".."
    if (Get-Module -ListAvailable $ModuleName) {
        Try {
            Import-Module $ModuleName -ErrorAction Stop
        }
        Catch {
            Write-Host -ForegroundColor Red "[FAIL]`n  Could not load module, stop proceeding."
            exit 1
        }
        Write-Host -ForegroundColor Green "[OK]"
    }
    else {
        Write-Host -ForegroundColor Red "[FAIL]`n  Module was installed but not available, cannot import."
        exit 1
    }

    Write-Host -ForegroundColor Green "`nModule installation was successful."
}
else {
    Write-Host -ForegroundColor yellow "Destination folder `"$Dest`" exists, please remove it and try again."
}