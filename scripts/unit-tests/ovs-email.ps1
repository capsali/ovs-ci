# Source the config and utils scripts.
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
. "$scriptPath\config.ps1"
. "$scriptPath\utils.ps1"


$messageUri = "$privatelogLink/commitmessage.txt.gz"
$messageOutFile = "$localLogs\message-$commitID.txt"
write-host "connecting to $messageUri"
ExecRetry {Invoke-WebRequest -Uri $messageUri -OutFile $messageOutFile}
$commitMessage = Get-Content $messageOutFile -Raw

if ($makeStatus) {
    write-host "Sending Unit Tests E-mail for $commitID with status $unitStatus"
    Send-Email $from $msito $unitStatus $commitLink $publiclogLink
}
if ($unitStatus) {
    write-host "Sending Unit Tests E-mail for $commitID with status $unitStatus"
    Send-Email $from $to $unitStatus $commitLink $publiclogLink
}

Remove-Item -Force -Path $messageOutFile