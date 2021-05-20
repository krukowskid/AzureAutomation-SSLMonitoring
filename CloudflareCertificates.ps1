Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$token = (Get-AutomationPSCredential -Name 'CloudflareDNSReadAPIKey').GetNetworkCredential().Password
$teamsWebhook = (Get-AutomationPSCredential -Name 'TeamsWebhookSSLAlert').GetNetworkCredential().Password
$baseurl = "https://api.cloudflare.com/client/v4/zones/"

$headers = @{Authorization = "Bearer $token"}

$zoneIds = (Invoke-RestMethod   -Uri $baseurl `
                                -Method GET `
                                -Headers $headers).result.id

$sites = foreach ($zoneId in $zoneIds){
            (Invoke-RestMethod  -Uri "$baseurl$zoneId/dns_records" `
                                -Method GET `
                                -Headers $headers).result `
                                    | Where-Object { 
                                            (($_.type -eq "A") `
                                            -or ($_.type -eq "CNAME")) `
                                            -and ($_.name -notmatch "\*") `
                                        } | Select-Object   name, 
                                                            type
        }

[Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
$certificates = foreach ($site in $sites.name){
                    $url = "https://$site"
                    $req = [Net.HttpWebRequest]::Create($url)
                    $req.AllowAutoRedirect = $false
                    $req.Timeout = 10000
                    $req.GetResponse() | Out-Null  
                    [PSCustomObject]@{
                        URL = $url
                        'endDate' = $req.ServicePoint.Certificate.GetExpirationDateString()
                    }
                }
$today = get-date
$expiredCertificates = $certificates `
                            | Where-Object { (get-date($_.'endDate')) -le $today }
$aboutToExpire = $certificates `
                    | Where-Object { ((get-date($_.'endDate')) -le $today.AddDays(14)) -and ((get-date($_.'endDate')) -ge $today) }

$ArrayTable = New-Object 'System.Collections.Generic.List[System.Object]'

if(($expiredCertificates | Measure-Object | ForEach-Object count) -gt 0){
    $section = @{
        activityTitle = "Expired certificate(s)"
        activitySubtitle = "$($expiredCertificates | Measure-Object | ForEach-Object count) expired certificate(s)!"
        activityText = "-----------------------------------------------"
        activityImage = "https://www.iconsdb.com/icons/preview/soylent-red/ssl-badge-xxl.png"
        facts = @(
                    foreach ($expiredCertificate in $expiredCertificates){
                        @{
                            name  = "$(($expiredCertificate.URL).Replace('https://',''))"
                            value = "$($expiredCertificate.endDate)"
                        }
                    }
                )
    }
     $arrayTable.add($section)
}
if(($aboutToExpire | Measure-Object | ForEach-Object count) -gt 0){
    $section = @{
        activityTitle = "Certificate(s) about to expiry"
        activitySubtitle = "$($aboutToExpire | Measure-Object | ForEach-Object count) certificate(s) about to expiry!"
        activityText = "-----------------------------------------------"
        activityImage = "https://www.iconsdb.com/icons/preview/yellow/ssl-badge-xxl.png"
        facts = @(
            foreach ($aboutTo in $aboutToExpire){
                @{
                    name  = "$(($aboutTo.URL).Replace('https://',''))"
                    value = "$($aboutTo.endDate)"
                }
            }
        )
    }
     $arrayTable.add($section)
}

if($arrayTable.count -gt 0){
    $body = ConvertTo-Json -Depth 8 @{
        title    = "SSL Alert"
        text = "Automatic check for CloudFlare added domains." 
        sections = $ArrayTable
    }

    Invoke-RestMethod   -uri $teamsWebhook `
                        -Method POST `
                        -body $body `
                        -ContentType 'application/json'
}
