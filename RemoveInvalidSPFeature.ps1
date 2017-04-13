#http://get-spscripts.com/2011/06/removing-features-from-content-database.html

$ver = $host | select version
if ($ver.Version.Major -gt 1)  {$Host.Runspace.ThreadOptions = "ReuseThread"}
Add-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue
cls

Set-StrictMode -Version Latest
#$ErrorActionPreference="stop"

$LogFile = "E:\Log_RemoveInvalidSPFeature." + (Get-Date).ToString("yyyyMMdd-HHmmss") + ".txt"

function Write-Log{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias("LogContent")]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet("Error","Warn","Info","HighLight")]
        [string]$Level="Info"
    )

    Begin{
        $VerbosePreference = 'Continue'
    }
    Process{
        #if (!(Test-Path $LogFile)) {
        #    Write-Verbose "Creating $LogFile."
        #    $NewLogFile = New-Item $LogFile -Force -ItemType File
        #}

        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        switch ($Level) {
            'Error' {
                $LevelText = 'ERROR:'
				$MessageColor = [System.ConsoleColor]::Red
            }
            'Warn' {
                $LevelText = 'WARNING:'
				$MessageColor = [System.ConsoleColor]::Yellow
            }
            'Info' {
                $LevelText = 'INFO:'
				$MessageColor = [System.ConsoleColor]::DarkGreen
            }
            'HighLight' {
                $LevelText = 'HIGHLIGHT:'
				$MessageColor = [System.ConsoleColor]::Green
            }
        }
        Write-Host $Message -f $MessageColor

		$MessageContent = "$FormattedDate $LevelText $Message"
        $MessageContent | Out-File -FilePath $LogFile -Append
		#$opts = @{ForegroundColor=$MessageColor; BackgroundColor="black"; object=$MessageContent}
		#Write-Log $opts
    }
    End{
    }
}

function RemoveSPFeatureFromContentDB($ContentDbNameStart, [switch]$ReportOnly){
Write-Log "$(get-date -UFormat '%Y%m%d %H:%M:%S') - RemoveSPFeatureFromContentDB() begin... ContentDbNameStart=$ContentDbNameStart, ReportOnly=$ReportOnly"
    $dbcollection = @(Get-SPContentDatabase | where { $_.Name.Startswith($ContentDbNameStart, "CurrentCultureIgnoreCase")})
    foreach($db in $dbcollection)
	{
		$ContentDbName = $db.Name
        Write-Log "ContentDbName=$ContentDbName"
		$url = ""
		$sites = @($db.Sites | ?{$_.ServerRelativeUrl -notmatch "Office_Viewing_Service_Cache" `
			-and $_.Url -notmatch "SearchCenter"})
		# $sites = Get-SPWebApplication -IncludeCentralAdministration | Get-SPSite -Limit ALL | ?{$_.ServerRelativeUrl -notmatch "Office_Viewing_Service_Cache"}
		$SiteCount = $sites.count
		$progressBarTitle = "RemoveSPFeatureFromContentDB(), SiteCount=$SiteCount, ContentDbName=$ContentDbName"
		$i = 0
		foreach($site in $sites)
		{
			$i++
			Write-Progress -Activity "$progressBarTitle" -PercentComplete (($i/$SiteCount)*100) -Status "Working"
			$url = $site.Url
			RemoveInvalidSPSiteFeatures $url $ReportOnly
			RemoveInvalidSPWebFeatures $url $ReportOnly
			$site.Dispose()
		}
	}
}

function RemoveInvalidSPSiteFeatures([string]$startSPSiteUrl, [switch]$ReportOnly){
Write-Log "$(get-date -UFormat '%Y%m%d %H:%M:%S') - RemoveInvalidSPSiteFeatures() begin... $startSPSiteUrl, ReportOnly=$ReportOnly"
    $dictValidFeatures = @{}
    $dictInvalidFeatures = @{}

    $sites = Get-SPWebApplication -IncludeCentralAdministration | Get-SPSite -Limit ALL
    $SiteCount = $sites.count
    $progressBarTitle = "RemoveInvalidSPSiteFeatures(), SiteCount=$SiteCount, startSPSiteUrl=$startSPSiteUrl"
    $i = 0
    foreach($site in $sites)    {
        $i++
		Write-Progress -Activity "$progressBarTitle" -PercentComplete (($i/$SiteCount)*100) -Status "Working"

        $dictValidFeatures.Clear()
        $dictInvalidFeatures.Clear()

        $AllFeaturesCount = $site.Features.Count
    
        Get-SPFeature -Site $site.Url -Limit All | %{
            $dictValidFeatures.Add($_.Id.ToString(), $_)
        }
        $ValidFeaturesCount = $dictValidFeatures.Count
    
        if ($AllFeaturesCount -ne $ValidFeaturesCount){
            $site.Features | %{
                $FeatureId = $_.DefinitionId.ToString()
                if ($dictValidFeatures.ContainsKey($FeatureId) -eq $false){
                    $_ | fl *
                    $_.Properties | ft *
                    $dictInvalidFeatures.Add($FeatureId, $site.Url)
                }
            }
        }
    
        foreach($featureItem in $dictInvalidFeatures.GetEnumerator()){
            if ($ReportOnly){
                Write-Log "Invalid Feature $($featureItem.Name) found in site collection: $($featureItem.Value)" -Level Warn
            }
            else{
                Write-Log "Invalid Feature $($featureItem.Name) in site collection: $($featureItem.Value) is removed." -Level HighLight
				[Microsoft.SharePoint.SPSecurity]::RunWithElevatedPrivileges({ 
					$mysite = get-spsite $site.Url
					$mysite.Features.Remove($featureItem.Name, $true)
					$mysite.Dispose()
				}); 
            }
        }
		$site.Dispose()
    }

    $dictValidFeatures.Clear()
    $dictInvalidFeatures.Clear()
}

function RemoveInvalidSPWebFeatures([string]$startSPSiteUrl, [switch]$ReportOnly){
Write-Log "$(get-date -UFormat '%Y%m%d %H:%M:%S') - RemoveInvalidSPWebFeatures() begin... $startSPSiteUrl, ReportOnly=$ReportOnly"
    $dictValidFeatures = @{}
    $dictInvalidFeatures = @{}

    $sites = Get-SPWebApplication -IncludeCentralAdministration | Get-SPSite -Limit ALL | ?{$_.ServerRelativeUrl -notmatch "Office_Viewing_Service_Cache"}
    $SiteCount = $sites.count
    $progressBarTitle = "RemoveInvalidSPWebFeatures(), SiteCount=$SiteCount, startSPSiteUrl=$startSPSiteUrl"
    $i = 0
    foreach($site in $sites){
        $i++
		if ($SiteCount -gt 2){
			Write-Progress -Activity "$progressBarTitle" -PercentComplete (($i/$SiteCount)*100) -Status "Working"
		}
        
        foreach($web in $site.AllWebs){
            $dictValidFeatures.Clear()
            $dictInvalidFeatures.Clear()

            $AllFeaturesCount = $web.Features.Count
            
            Get-SPFeature -Web $web.Url -Limit All | %{
                $dictValidFeatures.Add($_.Id.ToString(), $_)
            }
            $ValidFeaturesCount = $dictValidFeatures.Count
            
            if ($AllFeaturesCount -ne $ValidFeaturesCount){
                $web.Features | %{
                    $FeatureId = $_.DefinitionId.ToString()
                    if ($dictValidFeatures.ContainsKey($FeatureId) -eq $false){
                        $_ | fl *
                        $dictInvalidFeatures.Add($FeatureId, $web.Url)
                    }
                }
            }
            
            foreach($featureItem in $dictInvalidFeatures.GetEnumerator()){
                if ($ReportOnly){
                    Write-Log "Invalid Feature $($featureItem.Name) found in SPWeb: $($featureItem.Value)" -Level Warn
                }
                else{
                    Write-Log "Invalid Feature $($featureItem.Name) in SPWeb: $($featureItem.Value) is removed." -Level HighLight
					[Microsoft.SharePoint.SPSecurity]::RunWithElevatedPrivileges({ 
						$myweb = get-spsite $web.Url
						$myweb.Features.Remove($featureItem.Name, $true)
						$myweb.Dispose()
					}); 
                }
            }
			$web.Dispose()
        }
		$site.Dispose()
    }

    $dictValidFeatures.Clear()
    $dictInvalidFeatures.Clear()
}

Start-SPAssignment -Global

RemoveSPFeatureFromContentDB ""

Stop-SPAssignment -Global

Write-Log "Finished! Press enter key to exit."
# Read-Host
