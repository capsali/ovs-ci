Param(
)
$ErrorActionPreference = "Stop"

# Source the config and utils scripts.
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
. "$scriptPath\config.ps1"
. "$scriptPath\utils.ps1"

CheckLocalPaths
# Create the log paths on the remote log server
CreateRemotePaths $remotelogdirPath

pushd $commitDir
GitClonePull $gitcloneDir $OVS_URL
popd
pushd $gitcloneDir
Set-GitCommidID $commitID
Set-commitInfo

$msysCwd = "/" + $pwd.path.Replace("\", "/").Replace(":", "")

# Make Visual Studio Paths available to msys.
Set-VCVars $vsVersion $platform
# This must be the Visual Studio version of link.exe, not MinGW
$vsLink = $(Get-Command link.exe).path
$vsLinkPath = $vsLink.Replace("\", "/").Replace(":", "")

$makeScriptPath = Set-MakeScript
Get-Content $makeScriptPath
write-host "Running make on OVS commit $commitid"
&bash.exe $makeScriptPath
    if ($LastExitCode) {
		copy-item -Force "$gitcloneDir\makeoutput.log" "$commitlogDir\makeoutput.log"
        CompressLogs "$commitlogDir"
        Copy-RemoteLogs "$commitlogDir\*" $remotelogdirPath
		New-Item -Type file -Force -Path "$workspace\params.txt" -Value "makeStatus=ERROR"
        popd
        Cleanup
        throw "make.sh failed"
    }
    else {
        write-host "Finished compiling. Moving on..."
    }
    
$unitScriptPath = Set-UnitScript
Get-Content $unitScriptPath
write-host "Running unit tests!"
&bash.exe $unitScriptPath | Tee-Object -FilePath "$commitlogDir\unitsoutput.log"
    if ($LastExitCode) {
        Copy-LocalLogs
        CompressLogs "$commitlogDir"
        Copy-RemoteLogs "$commitlogDir\*" $remotelogdirPath
		New-Item -Type file -Force -Path "$workspace\params.txt" -Value "unitStatus=FAILED"
        popd
        Cleanup
        throw "Unit tests failed. The logs have been saved."
    }
    else {
        write-host "unit tests succeded. Moving on"
        Copy-LocalLogs
        CompressLogs "$commitlogDir"
        Copy-RemoteLogs "$commitlogDir\*" $remotelogdirPath
		New-Item -Type file -Force -Path "$workspace\params.txt" -Value "unitStatus=PASSED"
    }
    
$msiScriptPath = Set-MsiScript
Get-Content $msiScriptPath
write-host "Building OVS MSI."
&bash.exe $msiScriptPath | Tee-Object -FilePath "$commitlogDir\msioutput.log"
    if ($LastExitCode) { 
        cd $buildDir
        CompressLogs "$commitlogDir"
        Copy-RemoteLogs "$commitlogDir\msioutput.log.gz" $remotelogdirPath
        popd
        Cleanup
        throw "Failed to create OVS msi." 
    }
    else { 
        write-host "OVS msi created."
        # Create the msi remote log paths
        CreateRemotePaths $remotemsidirPath
        CompressLogs "$commitlogDir"
        Copy-LocalMsi
        Copy-RemoteLogs "$commitlogDir\msioutput.log.gz" $remotelogdirPath
        Copy-RemoteMSI "$gitcloneDir\windows\ovs-windows-installer\bin\Release\OpenvSwitch.msi" $remotemsidirPath
		Copy-RemoteMSI "$gitcloneDir\datapath-windows\x64\Win8.1Debug\package.cer" $remotemsidirPath
        popd
        Cleanup
    }
