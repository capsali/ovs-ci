function CheckCopyDir($src, $dest) {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -Path $dest
    Copy-Item -Recurse $src $dest
}


function GitClonePull($path, $url, $branch="master") {
    Write-Host "Cloning / pulling: $url"

    if (Test-Path -path $path) {
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -Path $path
    }
    
    # Start git clone
    &git clone $url $path
    if ($LastExitCode) {
        throw "git clone failed"
    }
    
    # Change branch
    &git -C $path checkout $branch
    if ($LastExitCode) {
        throw "git checkout for branch $branch failed"
    }
}


function Set-GitCommidID ( $commitID ) {
    pushd "$gitcloneDir"
    &git checkout $commitID
    write-host "this is the CommitID that we are working on"
    &git rev-parse HEAD
    popd
}

function Set-commitInfo {
	write-host "Reading and saving commit author and message."
	pushd "$gitcloneDir"
    &git log -n 1 $commitID | Out-File "$localLogs\message-$commitID.txt"
	Copy-Item "$localLogs\message-$commitID.txt" -Destination "$commitlogDir\commitmessage.txt" -Force
	popd
}

function Set-VCVars($version="12.0", $platform="amd64") {
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

function ExecRetry ($command, $maxRetryCount = 10, $retryInterval=2) {
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

function ExecSSHCmd ($server, $user, $key, $cmd) {
    write-host "Running ssh command $cmd on remote server $server"
    echo Y | plink.exe $server -l $user -i $key $cmd
}

function ExecSCPCmd ($server, $user, $key, $localPath, $remotePath) {
    write-host "Starting copying $localPath to remote location ${server}:${remotePath}"
    echo Y | pscp.exe -scp -r -i $key $localPath $user@${server}:${remotePath}
}

function CheckLocalPaths {
    New-Item -ItemType Directory -ErrorAction SilentlyContinue -Path $basePath
    New-Item -ItemType Directory -ErrorAction SilentlyContinue -Path $localLogs
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -Path $commitlogDir
    New-Item -ItemType Directory -Force -ErrorAction SilentlyContinue -Path $commitlogDir
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -Path $commitDir
    New-Item -ItemType Directory -Force -ErrorAction SilentlyContinue -Path $commitDir
    New-Item -ItemType Directory -Force -ErrorAction SilentlyContinue -Path $outputSymbolsPath
    New-Item -ItemType Directory -Force -ErrorAction SilentlyContinue -Path $outputPath
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -Path $commitmsiDir
    New-Item -ItemType Directory -Force -ErrorAction SilentlyContinue -Path $commitmsiDir
}

function CreateRemotePaths ($remotedirPath) {
    $remoteCMD = "mkdir -p $remotedirPath"
    ExecSSHCmd $remoteServer $remoteUser $remoteKey $remoteCMD
}

function Copy-LocalLogs {
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

function Copy-LocalMsi {
    $msiPath = "$commitDir\ovs\windows\ovs-windows-installer\bin\Release\OpenvSwitch.msi"
    if ((Test-Path -path $msiPath)) {
        copy-item -Force "$msiPath" "$commitmsiDir\OpenvSwitch.msi"
    }
    else { write-host "No msi found."}
}

function Copy-RemoteLogs ($locallogPath, $remotelogPath) {
    write-host "Started copying logs for commit ID $commitID unit tests to remote location ${server}:${remotelogPath}"
    ExecSCPCmd $remoteServer $remoteUser $remoteKey $locallogPath $remotelogPath
}

function Copy-RemoteMSI ($localmsiPath) {
    write-host "Started copying generated msi for commit ID $commitID to remote location ${server}:${remotemsiPath}"
    ExecSCPCmd $remoteServer $remoteUser $remoteKey $localmsiPath $remotemsiPath
}

function CompressLogs ( $logsPath ) {
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

function Cleanup {
    $ovsprocess = Get-Process ovs* -ErrorAction SilentlyContinue
    $ovnprocess = Get-Process ovn* -ErrorAction SilentlyContinue
    if ($ovsprocess) {
        Stop-Process -name ovs*
    }
    if ($ovnprocess) {
        Stop-Process -name ovn*
    }
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -Path $commitDir
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

function Set-MakeScript {
$makeScript = @"
#!/bin/bash
set -e
set -o pipefail
cd $msysCwd
echo `$INCLUDE
./boot.sh
./configure CC=./build-aux/cccl LD="C:/Program Files (x86)/Microsoft Visual Studio 12.0/VC/BIN/x86_amd64/link.exe" LIBS="-lws2_32 -liphlpapi -lwbemuuid -lole32 -loleaut32" --prefix="C:/ProgramData/openvswitch" \
--localstatedir="C:/ProgramData/openvswitch" --sysconfdir="C:/ProgramData/openvswitch" \
--with-pthread="$pthreadDir" --with-vstudiotarget="Debug"
make clean 2>&1 | tee makeoutput.log
make -j4 2>&1 | tee -a makeoutput.log
exit `$?
"@

$makeScriptPath = Join-Path $pwd "make.sh"
$makeScript.Replace("`r`n","`n") | Set-Content $makeScriptPath -Force
return $makeScriptPath
}

function Set-UnitScript {
$unitScript = @"
#!/bin/bash
set -e
cd $msysCwd
echo `$INCLUDE
make check TESTSUITEFLAGS="-j3" RECHECK=yes || make check TESTSUITEFLAGS="--recheck" || make check TESTSUITEFLAGS="--recheck" || make check TESTSUITEFLAGS="--recheck" || make check TESTSUITEFLAGS="--recheck"
exit `$?
"@

$unitScriptPath = Join-Path $pwd "unit.sh"
$unitScript.Replace("`r`n","`n") | Set-Content $unitScriptPath -Force
return $unitScriptPath
}

function Set-MsiScript {
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


# Email job functions
function Send-Email ($from, $to, $status, $commitLink, $publiclogLink) {
    $subject = "[ovs-build] ${status}: openvswitch/ovs (master - $commitID)"
    $body = @"
<pre>
Status: $status
</pre>
<pre>
$commitMessage
</pre>
<pre>
View the changeset:
<a href="$commitLink">$commitLink</a>

View the full build log and details:
<a href="$publiclogLink">$publiclogLink</a></pre>
"@
    Send-MailMessage -from $from -to $to -subject $subject -body $body -BodyAsHtml -smtpServer $smtpServer
}
