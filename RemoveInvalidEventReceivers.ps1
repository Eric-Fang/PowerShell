#http://get-spscripts.com/2011/06/removing-features-from-content-database.html

$ver = $host | select version
if ($ver.Version.Major -gt 1)  {$Host.Runspace.ThreadOptions = "ReuseThread"}
Add-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue
cls

Set-StrictMode -Version Latest
#$ErrorActionPreference="stop"

$LogFile = "E:\Log_RemoveInvalidEventReceivers." + (Get-Date).ToString("yyyyMMdd-HHmmss") + ".txt"

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

function RemoveInvalidEventReceivers([string]$startSPSiteUrl, [string]$AssemblyName, [switch]$ReportOnly)
{
Write-Log "$(get-date -UFormat '%Y%m%d %H:%M:%S') - RemoveInvalidEventReceivers() begin... $startSPSiteUrl, ReportOnly=$ReportOnly"
    $sites = @(Get-SPWebApplication -IncludeCentralAdministration | Get-SPSite -Limit ALL | ?{$_.Url.Startswith($startSPSiteUrl, "CurrentCultureIgnoreCase") `
        -and $_.Url -notmatch "mysite"})
    $SiteCount = $sites.count
    $progressBarTitle = "RemoveInvalidEventReceivers(), SiteCount=$SiteCount, startSPSiteUrl=$startSPSiteUrl"
    $i = 0
    foreach($site in $sites){
		$count = 0
        $i++
		Write-Progress -Activity "$progressBarTitle" -PercentComplete (($i/$SiteCount)*100) -Status "Working"

		try{
            Write-Log "$i, $($site.Url)"

			$evenReceiverIds = @($site.EventReceivers | ?{ $_.Assembly -eq $AssemblyName })
			if ($evenReceiverIds.Count -gt 0){
				$count += $evenReceiverIds.Count
			}
			$evenReceiverIds | %{
				$er = $site.EventReceivers[$_.ID]
				if ($ReportOnly){
					Write-Log "site level: '$($er.Assembly)', $($er.Class), $($er.Type), $($site.Url)" -Level HighLight
				}
				else{
					Write-Log "Deleting site level: '$($er.Assembly)', $($er.Class), $($er.Type), $($site.Url)" -Level HighLight
					$er.Delete()
					Write-Log "Deleted"
				}
				Write-Host ""
			}
			
			foreach($web in $site.AllWebs){
				foreach($ct in $web.ContentTypes){
					$evenReceiverIds = @($ct.EventReceivers | ?{ $_.Assembly -eq $AssemblyName })
					if ($evenReceiverIds.Count -gt 0){
						$count += $evenReceiverIds.Count
					}
					$evenReceiverIds | %{
						$er = $ct.EventReceivers[$_.ID]
						if ($ReportOnly){
							Write-Log "site Content Type level: '$($er.Assembly)', $($er.Class), $($er.Type), $($web.Url), $($ct.Name)" -Level HighLight
						}
						else{
							Write-Log "Deleting site Content Type level: '$($er.Assembly)', $($er.Class), $($er.Type), $($web.Url), $($ct.Name)" -Level HighLight
							$er.Delete()
							Write-Log "Deleted"
						}
						Write-Host ""
					}
				}
				
				$web.Dispose()
			}
			
			foreach($web in $site.AllWebs){
				foreach($list in $web.Lists){
					$evenReceiverIds = @($list.EventReceivers | ?{ $_.Assembly -eq $AssemblyName })
					if ($evenReceiverIds.Count -gt 0){
						$count += $evenReceiverIds.Count
					}
					$evenReceiverIds | %{
						$er = $list.EventReceivers[$_.ID]
						if ($ReportOnly){
							Write-Log "list level: '$($er.Assembly)', $($er.Class), $($er.Type), $($web.Url), $($list.Title)" -Level HighLight
						}
						else{
							Write-Log "Deleting list level: '$($er.Assembly)', $($er.Class), $($er.Type), $($web.Url), $($list.Title)" -Level HighLight
							$er.Delete()
							Write-Log "Deleted"
						}
						Write-Host ""
					}
				}
				
				$web.Dispose()
			}
			
			if ($count -gt 0){
				Write-Log "site.Url=$($site.Url), count=$count" -Level Warn
			}
		}
		Catch [system.exception]{
			$strTmp = [string]::Format("RemoveInvalidEventReceivers(), SiteUrl={0}, ex.Message={1}", $site.Url, $Error[0].Exception.Message)
	Write-Log $strTmp -Level Error
	Write-Log $_.Exception -Level Error
		}
		
		$site.Dispose()
    }
}

# $_AssemblyName = "Microsoft.AnalysisServices.SPAddin"
# $_AssemblyName = "Microsoft.AnalysisServices.SharePoint.Integration, Version=10.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91"

# $_AssemblyName = "Microsoft.AnalysisServices.SPAddin.ConnectionUsageDefinition, Microsoft.AnalysisServices.SPAddin, Version=12.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91"
$_AssemblyName = "Microsoft.AnalysisServices.SPAddin.LoadUsageDefinition, Microsoft.AnalysisServices.SPAddin, Version=12.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91"
# $_AssemblyName = "Microsoft.AnalysisServices.SPAddin.UnloadUsageDefinition, Microsoft.AnalysisServices.SPAddin, Version=12.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91"
# $_AssemblyName = "Microsoft.AnalysisServices.SPAddin.RequestUsageDefinition, Microsoft.AnalysisServices.SPAddin, Version=12.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91"

RemoveInvalidEventReceivers "" $_AssemblyName -ReportOnly
# RemoveInvalidEventReceivers "http://apps.unitingcare.local/sites/HRRecords" $_AssemblyName
# RemoveInvalidEventReceivers "http://sptest.unitingcare.local/sites/HRRecords" $_AssemblyName

# RemoveInvalidEventReceivers "http://apps.unitingcare.local/sites/HRRecords" $_AssemblyName -ReportOnly
# RemoveInvalidEventReceivers "http://sptest.unitingcare.local/sites/HRRecords" $_AssemblyName -ReportOnly


Write-Log "Finished! Press enter key to exit."
# Read-Host
