[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$teamsWebhook = (Get-AutomationPSCredential -Name 'TeamsWebhookSSLAlert').GetNetworkCredential().Password

$connectionName = "AzureRunAsConnection"
try 
{
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName         

    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
} 
catch 
{
    if (!$servicePrincipalConnection) {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } 
    else {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}
$subscriptions = Get-AzureRmSubscription `
                    | Where-Object {$_.'State' -eq "Enabled"}

foreach ($subscription in $subscriptions){
    Set-AzureRmContext -Subscriptionid $subscription.Id   
    $currentSubscription = (Get-AzureRmContext).Subscription
    $resourceGroups = Get-AzureRmResourceGroup

    if ($resourceGroups) 
    {
        foreach ($ResourceGroup in $resourceGroups)
        {
            $ResourceGroupName = "$($ResourceGroup.ResourceGroupName)"
            $allCertificates = Get-AzureRmWebAppCertificate -ResourceGroupName $ResourceGroupName
            $today = get-date
            $expiredCertificates = $allCertificates `
                                        | Where-Object { (get-date($_.'ExpirationDate')) -le $today }
            $aboutToExpire = $allCertificates `
                                | Where-Object { ((get-date($_.'ExpirationDate')) -le $today.AddDays(14)) -and ((get-date($_.'ExpirationDate')) -ge $today) }

            $arrayTable = New-Object 'System.Collections.Generic.List[System.Object]'

            if(($expiredCertificates | Measure-Object | ForEach-Object count) -gt 0){
                $section = @{
                    activityTitle = "Expired certificate(s)"
                    activitySubtitle = "$($expiredCertificates | Measure-Object | ForEach-Object count) expired certificate(s)!"
                    activityText = "-----------------------------------------------"
                    activityImage = "https://www.iconsdb.com/icons/preview/soylent-red/ssl-badge-xxl.png"
                    facts  = @(
                        foreach ($expiredCertificate in $expiredCertificates){
                            @{
                                name  = "$($expiredCertificate.FriendlyName)"
                                value = ""
                            }  
                            @{
                                name  = "Subject:"
                                value = "$($expiredCertificate.subjectName)"
                            }
                            @{
                                name  = "Expiration Date:"
                                value = "$($expiredCertificate.ExpirationDate)"
                            }
                            @{
                                name  = "Resource group:"
                                value = "$(($expiredCertificate.Id).split("/")[4])"
                            }
                            @{
                                name  = "Subscription:"
                                value = "$($currentSubscription.Name)"
                            }
                            @{
                                name  = " "
                                value = " "
                            }                            
                        }
                    )
                }
                $arrayTable.add($section)
            }
            if(($aboutToExpire | Measure-Object | ForEach-Object count) -gt 0){
                $section = @{
                    activityTitle = "Certificate(s) about to expire"
                    activitySubtitle = "$($aboutToExpire | Measure-Object | ForEach-Object count) certificate(s) about to expire!"
                    activityText = "-----------------------------------------------"
                    activityImage = "https://www.iconsdb.com/icons/preview/yellow/ssl-badge-xxl.png"
                    facts  = @(
                        foreach ($aboutTo in $aboutToExpire){
                            @{
                                name  = "$($aboutTo.FriendlyName)"
                                value = ""
                            }  
                            @{
                                name  = "Subject:"
                                value = "$($aboutTo.subjectName)"
                            }
                            @{
                                name  = "Expiration Date:"
                                value = "$($aboutTo.ExpirationDate)"
                            }
                            @{
                                name  = "Resource group:"
                                value = "$(($aboutTo.Id).split("/")[4])"
                            }
                            @{
                                name  = "Subscription:"
                                value = "$($currentSubscription.Name)"
                            }  
                            @{
                                name  = " "
                                value = " "
                            }      
                        }
                    )
                }
                $arrayTable.add($section)
            }

            if($arrayTable.count -gt 0){
                $body = ConvertTo-Json -Depth 8 @{
                    title    = "SSL Alert"
                    text = "Subscription: $($currentSubscription.Name)" 
                    sections = $arrayTable
                }

                Invoke-RestMethod   -uri $teamsWebhook `
                                    -Method Post `
                                    -body $body `
                                    -ContentType 'application/json'
            }    
        }
    }
    else
    {
        Write-Output "There are no resource groups within this subscription"
    }
}
