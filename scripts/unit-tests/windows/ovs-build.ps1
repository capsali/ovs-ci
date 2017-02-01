Param(
)
$ErrorActionPreference = "Stop"

function CheckRemoveDir($path) {
    if (Test-Path $path) {
        Remove-Item -Recurse -Force $path
    }
}

function CheckCopyDir($src, $dest) {
    CheckRemoveDir $dest
    Copy-Item $src $dest -Recurse
}

function CheckDir($path) {
    if (!(Test-Path -path $path))
    {
        mkdir $path
    }
}

function GitClonePull($path, $url, $branch="master") {
    Write-Host "Cloning / pulling: $url"

    $needspull = $true

    if (!(Test-Path -path $path))
    {
        git clone -b $branch $url
        if ($LastExitCode) { throw "git clone failed" }
        $needspull = $false
    }

    if ($needspull)
    {
        pushd .
        try
        {
            cd $path

            $branchFound = (git branch)  -match "(.*\s)?$branch"
            if ($LastExitCode) { throw "git branch failed" }

            if($branchFound)
            {
                git checkout $branch
                if ($LastExitCode) { throw "git checkout failed" }
            }
            else
            {
                git checkout -b $branch origin/$branch
                if ($LastExitCode) { throw "git checkout failed" }
            }

            git reset --hard
            if ($LastExitCode) { throw "git reset failed" }

            git clean -f -d
            if ($LastExitCode) { throw "git clean failed" }

            git pull
            if ($LastExitCode) { throw "git pull failed" }
        }
        finally
        {
            popd
        }
    }
}

function Start-GitClone {
    ExecRetry {
    # Make sure to have a private key that matches a github deployer key in $ENV:HOME\.ssh\id_rsa
    GitClonePull $gitcloneDir "https://github.com/openvswitch/ovs.git"
    }
}

function Change-GitCommidID ( $commitID ) {
    git checkout $commitID
    write-host "this is the CommitID that we are working on"
    git rev-parse HEAD
}

function Set-commitInfo {
	write-host "Reading and saving commit author and message."
	pushd "$commitDir/$gitcloneDir"
    git log -n 1 $commitID | Out-File "$localLogs\message-$commitID.txt"
	Copy-Item "$localLogs\message-$commitID.txt" -Destination "$commitlogDir\commitmessage.txt" -Force
	popd
}

function SetVCVars($version="12.0", $platform="amd64") {
    pushd "$ENV:ProgramFiles (x86)\Microsoft Visual Studio $version\VC\"
    try
    {
        cmd /c "vcvarsall.bat $platform & set" |
        foreach {
          if ($_ -match "=") {
            $v = $_.split("="); set-item -force -path "ENV:\$($v[0])"  -value "$($v[1])"
          }
        }
    }
    finally
    {
        popd
    }
}

function ExecRetry($command, $maxRetryCount = 10, $retryInterval=2) {
    $currErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    $retryCount = 0
    while ($true)
    {
        try
        {
            & $command
            break
        }
        catch [System.Exception]
        {
            $retryCount++
            if ($retryCount -ge $maxRetryCount)
            {
                $ErrorActionPreference = $currErrorActionPreference
                throw
            }
            else
            {
                Write-Error $_.Exception
                Start-Sleep $retryInterval
            }
        }
    }

    $ErrorActionPreference = $currErrorActionPreference
}

function Start-CheckPath {
    CheckDir $basePath
    CheckDir $localLogs
    CheckRemoveDir $commitlogDir
    mkdir -Force $commitlogDir
    CheckRemoveDir $commitDir
    mkdir -Force $commitDir
    CheckRemoveDir $commitmsiDir
    mkdir -Force $commitmsiDir
    CheckRemoveDir $outputSymbolsPath
    mkdir -Force $outputSymbolsPath
    mkdir -Force $outputPath
}

function Start-CopyTestLog {
    $testlogPath = "$commitDir\ovs\tests\testsuite.log"
    $testdirPath = "$commitDir\ovs\tests\testsuite.dir"
    if ((Test-Path -path $testlogPath)) {
        copy-item -Force "$testlogPath" "$commitlogDir\testsuite.log"
    }
    else { write-host "No testsuite.log found." }
    if ((Test-Path -path $testdirPath)) {
        copy-item -Force -recurse "$testdirPath" "$commitlogDir\testsuite.dir"
    }
    else { write-host "No testsuite.dir found." }
}

function Start-CopyMsi {
    $msiPath = "$commitDir\ovs\windows\ovs-windows-installer\bin\Release\OpenvSwitch.msi"
    if ((Test-Path -path $msiPath)) {
        copy -Force "$msiPath" "$commitmsiDir\OpenvSwitch.msi"
    }
    else { write-host "No msi found."}
}

function Start-CompressLogs ( $logsPath ) {
    $logfiles = Get-ChildItem -File -Recurse -Path $logsPath | Where-Object { $_.Extension -ne ".gz" }
    foreach ($file in $logfiles) {
        $filename = $file.name
        $directory = $file.DirectoryName
        $extension = $file.extension
        if (!$extension) {
            $name = $file.name + ".txt"
        }
        else {
            $name = $file.name
        }
        &7z.exe a -tgzip "$directory\$name.gz" "$directory\$filename" -sdel
    }
}

function Set-RemoteVars {
    Set-Variable -Name server -Value "10.20.1.14" -Scope Script
    Set-Variable -Name user -Value "logs" -Scope Script
    Set-Variable -Name key -Value "C:\scripts\ssh\norman.ppk" -Scope Script
    Set-Variable -Name remotelogDir -Value "/srv/logs/ovs" -Scope Script
    Set-Variable -Name remotemsiDir -Value "/srv/dl/ovs" -Scope Script
}

function Start-SSHCMD ($server, $user, $key, $cmd) {
    write-host "Running ssh command $cmd on remote server $server"
#        &plink -batch $server -l $user -i $key $cmd
    echo Y | plink.exe $server -l $user -i $key $cmd
}

function Start-SCP ($server, $user, $key, $localPath, $remotePath) {
    write-host "Starting copying $localPath to remote location ${server}:${remotePath}"
#        &pscp -batch -scp -r -i $key $localPath $user@${server}:${remotePath}
    echo Y | pscp.exe -scp -r -i $key $localPath $user@${server}:${remotePath}
}

function Start-CreateRemoteDir {
    Set-RemoteVars
    $logCMD = "mkdir -p $remotelogDir/$commitID"
    $msiCMD = "mkdir -p $remotemsiDir/$commitID"
    Start-SSHCMD $server $user $key $logCMD
    Start-SSHCMD $server $user $key $msiCMD
}

function Start-RemoteLogCopy ($locallogPath) {
    Set-RemoteVars
    $remotelogPath = "$remotelogDir/$commitID"
    write-host "Started copying logs for commit ID $commitID unit tests to remote location ${server}:${remotelogPath}"
    Start-SCP $server $user $key $locallogPath $remotelogPath
}

function Start-RemoteMsiCopy ($localmsiPath) {
    Set-RemoteVars
    $remotemsiPath = "$remotemsiDir/$commitID"
    write-host "Started copying generated msi for commit ID $commitID to remote location ${server}:${remotemsiPath}"
    Start-SCP $server $user $key $localmsiPath $remotemsiPath
}

function Start-Cleanup {
    $ovsprocess = Get-Process ovs* -ErrorAction SilentlyContinue
    $ovnprocess = Get-Process ovn* -ErrorAction SilentlyContinue
    if ($ovsprocess) {
        Stop-Process -name ovs*
    }
    if ($ovnprocess) {
        Stop-Process -name ovn*
    }
    cd $buildDir
    CheckRemoveDir $commitDir
}

function Start-MailJob ($user, $pass, $status) {
    $uri = "http://10.20.1.3:8080/job/ovs-email-job/buildWithParameters?token=b204eee759ab38ebb986d223f6c5b4ce&commitid=$commitID&status=$status"
    $pair = "${user}:${pass}"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $base64 = [System.Convert]::ToBase64String($bytes)
    $basicAuthValue = "Basic $base64"
    $headers = @{ Authorization = $basicAuthValue }
    write-host "Starting the Mail Job for status $status"
    Invoke-WebRequest -uri $uri -Headers $headers -UseBasicParsing
}

function Set-MakeSh {
$makeScript = @"
#!/bin/bash
set -e
cd $msysCwd
echo `$INCLUDE
./boot.sh
./configure CC=./build-aux/cccl LD="C:/Program Files (x86)/Microsoft Visual Studio 12.0/VC/BIN/x86_amd64/link.exe" LIBS="-lws2_32 -liphlpapi -lwbemuuid -lole32 -loleaut32" --prefix="C:/ProgramData/openvswitch" \
--localstatedir="C:/ProgramData/openvswitch" --sysconfdir="C:/ProgramData/openvswitch" \
--with-pthread="$pthreadDir" --with-vstudiotarget="Debug"
make clean && make -j4
exit `$?
"@

$makeScriptPath = Join-Path $pwd "make.sh"
$makeScript.Replace("`r`n","`n") | Set-Content $makeScriptPath -Force
return $makeScriptPath
}

function Set-UnitSh {
$unitScript = @"
#!/bin/bash
set -e
cd $msysCwd
echo `$INCLUDE
make check RECHECK=yes || make check TESTSUITEFLAGS="--recheck" || make check TESTSUITEFLAGS="--recheck" || make check TESTSUITEFLAGS="--recheck" || make check TESTSUITEFLAGS="--recheck"
exit `$?
"@

$unitScriptPath = Join-Path $pwd "unit.sh"
$unitScript.Replace("`r`n","`n") | Set-Content $unitScriptPath -Force
return $unitScriptPath
}

function Set-MsiSh {
$msiScript = @"
#!/bin/bash
set -e
cd $msysCwd
echo `$INCLUDE
make windows_installer
exit `$?
"@

$msiScriptPath = Join-Path $pwd "msi.sh"
$msiScript.Replace("`r`n","`n") | Set-Content $msiScriptPath -Force
return $msiScriptPath
}

# Make sure ActivePerl comes before MSYS Perl, otherwise
# the OpenSSL build will fail
$ENV:PATH = "C:\Perl64\bin;$ENV:PATH"
$ENV:PATH += ";${ENV:ProgramFiles}\7-Zip"
$ENV:PATH += ";${ENV:ProgramFiles}\Git\bin"
$ENV:PATH += ";${ENV:ProgramFiles(x86)}\CMake\bin"
$ENV:PATH += ";C:\Python27"
$ENV:PATH += ";C:\Python3"
$ENV:PATH += ";${ENV:ProgramFiles(x86)}\PuTTY"


$msysBinDir = "C:\mingw\msys\1.0\bin"
$basePath = "C:\OpenStack\OpenvSwitch"
$buildDir = "$basePath\Build"
$commitID = $env:commitid
$commitDir = "$buildDir\$commitID"
$outputPath = "$commitDir\bin"
$installerDir = "$basePath\installer"
$commitmsiDir = "$installerDir\$commitID"
$localLogs = "$basePath\logs"
$commitlogDir = "$localLogs\$commitID"
$outputSymbolsPath = "$commitDir\symbols"
#automake already appends \lib\<platform> to the pthread library
$winPthreadLibDir = "$basePath\pthread"
#Git clone Dir
$gitcloneDir = "ovs"

Start-CheckPath
Start-CreateRemoteDir
cd $commitDir
Start-GitClone
cd $gitcloneDir
Change-GitCommidID $commitID
Set-commitInfo

$vsVersion = "12.0"
$platform = "x86_amd64"
SetVCVars $vsVersion $platform

$msysCwd = "/" + $pwd.path.Replace("\", "/").Replace(":", "")
$pthreadDir = $winPthreadLibDir.Replace("\", "/")
# This must be the Visual Studio version of link.exe, not MinGW
$vsLink = $(Get-Command link.exe).path
$vsLinkPath = $vsLink.Replace("\", "/").Replace(":", "")

$ENV:PATH = "$msysBinDir;$ENV:PATH"

$makeScriptPath = Set-MakeSh
Get-Content $makeScriptPath
write-host "Running make on OVS commit $commitid"
&bash.exe $makeScriptPath | Tee-Object -FilePath "$commitlogDir\makeoutput.log"
    if ($LastExitCode) {
        Start-CompressLogs "$commitlogDir"
        Start-RemoteLogCopy "$commitlogDir\*"
        Start-MailJob "$jenk_user" "$jenk_api" "ERROR"
        Start-Cleanup
        throw "make.sh failed"
    }
    else {
#        Start-RemoteLogCopy "$commitlogDir\makeoutput.log"
        write-host "Finished compiling. Moving on..."
    }
    
$unitScriptPath = Set-UnitSh
Get-Content $unitScriptPath
write-host "Running unit tests!"
&bash.exe $unitScriptPath | Tee-Object -FilePath "$commitlogDir\unitsoutput.log"
    if ($LastExitCode) {
        Start-CopyTestLog
        Start-CompressLogs "$commitlogDir"
        Start-RemoteLogCopy "$commitlogDir\*"
        Start-MailJob "$jenk_user" "$jenk_api" "UNITFAIL"
        Start-Cleanup
        throw "Unit tests failed. The logs have been saved."
    }
    else {
        write-host "unit tests succeded. Moving on"
        Start-CopyTestLog
        Start-CompressLogs "$commitlogDir"
        Start-RemoteLogCopy "$commitlogDir\*"
        Start-MailJob "$jenk_user" "$jenk_api" "UNITPASS"
    }
    
$msiScriptPath = Set-MsiSh
Get-Content $msiScriptPath
write-host "Building OVS MSI."
&bash.exe $msiScriptPath | Tee-Object -FilePath "$commitlogDir\msioutput.log"
    if ($LastExitCode) { 
        cd $buildDir
        Start-CompressLogs "$commitlogDir"
        Start-RemoteLogCopy "$commitlogDir\msioutput.log.gz"
        Start-Cleanup
        throw "Failed to create OVS msi." 
    }
    else { 
        write-host "OVS msi created."
        Start-CompressLogs "$commitlogDir"
        Start-CopyMsi
        Start-RemoteLogCopy "$commitlogDir\msioutput.log.gz"
        Start-RemoteMsiCopy "$commitDir\ovs\windows\ovs-windows-installer\bin\Release\OpenvSwitch.msi"
        Start-Cleanup
    }