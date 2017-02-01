function Send-PassEmail ($from, $to, $smtpServer, $commitLink, $logLink) {
    $subject = "[ovs-build] Passed: openvswitch/ovs (master - $commitID)"
    $body = @"
<pre>
Status: Passed
</pre>
<pre>
$commitMessage
</pre>
<pre>
View the changeset:
<a href="$commitLink">$commitLink</a>

View the full build log and details:
<a href="$logLink">$logLink</a></pre>
"@
    Send-MailMessage -from $from -to $to -subject $subject -body $body -BodyAsHtml -smtpServer $smtpServer
}

function Send-FailEmail ($from, $to, $smtpServer, $commitLink, $logLink) {
    $subject = "[ovs-build] Failed: openvswitch/ovs (master - $commitID)"
    $body = @"
<pre>
Status: Failed
</pre>
<pre>
$commitMessage
</pre>
<pre>
View the changeset:
<a href="$commitLink">$commitLink</a>

View the full build log and details:
<a href="$logLink">$logLink</a></pre>
"@
    Send-MailMessage -from $from -to $to -subject $subject -body $body -BodyAsHtml -smtpServer $smtpServer
}

function Send-ErrorEmail ($from, $to, $smtpServer, $commitLink, $logLink) {
    $subject = "[ovs-make] Error: openvswitch/ovs (master - $commitID)"
    $body = @"
<pre>
Status: Error
</pre>
<pre>
$commitMessage
</pre>
<pre>
View the changeset:
<a href="$commitLink">$commitLink</a>

View the full build log and details:
<a href="$logLink">$logLink</a></pre>
"@
    Send-MailMessage -from $from -to $to -subject $subject -body $body -BodyAsHtml -smtpServer $smtpServer
}


$Status = $env:status
$commitID = $env:commitid
$basePath = "C:\OpenStack\OpenvSwitch"
$localLogs = "$basePath\logs"
$commitlogDir = "$localLogs\$commitID"
$commitMessage = Get-Content "$localLogs\message-$commitID.txt" -Raw
$smtpServer = "mail.cloudbasesolutions.com"
$from = "microsoft_ovs_ci@microsoft.com"
$to = "aserdean@cloudbasesolutions.com","ociuhandu@cloudbasesolutions.com","mgheorghe@cloudbasesolutions.com"
$commitLink = "https://github.com/openvswitch/ovs/commit/$commitID"
$logLink = "http://64.119.130.115/ovs/$commitID"
#$msiLink = "http://10.20.1.14:8080/ovs/$commitID"

if ( $Status -eq "UNITPASS" ) {
        write-host "Sending Unit Tests Pass E-mail for $commitID"
        Send-PassEmail $from $to $smtpServer $commitLink $logLink
}

if ( $Status -eq "UNITFAIL" ) {
        write-host "Sending Unit Tests Fail E-mail for $commitID"
        Send-FailEmail $from $to $smtpServer $commitLink $logLink
}

if ( $Status -eq "ERROR" ) {
        write-host "Sending make error E-mail for $commitID"
        Send-PassEmail $from "mgheorghe@cloudbasesolutions.com" $smtpServer $commitLink $logLink
}

Remove-Item -Path "$localLogs\message-$commitID.txt" -Force