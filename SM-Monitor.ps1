<#  ------------------------------------------------------------------------------------------------
SM-Monitor: https://github.com/xeliuqa/SM-Monitor
    Based on: https://discord.com/channels/623195163510046732/691261331382337586/1142174063293370498
    and also: https://github.com/PlainLazy/crypto/blob/main/sm_watcher.ps1

With Thanks To: == S A K K I == Stizerg == PlainLazy == Shanyaa
for the various contributions in making this script awesome

Get grpcurl here: https://github.com/fullstorydev/grpcurl/releases
--------------------------------------------------------------------------------------------- #>

$host.ui.RawUI.WindowTitle = $MyInvocation.MyCommand.Name


############## General Settings  ##############
$coinbaseAddressVisibility = "partial" # "partial", "full", "hidden"
$smhCoinsVisibility = $false # $true or $false.
$fakeCoins = 0 # For screenshot purposes.  Set to 0 to pull real coins.  FAKE 'EM OUT!  (Example: 2352.24)
$tableRefreshTimeSeconds = 300 # Time in seconds that the refresh happens.  Lower value = more grpc entries in logs.
$DefaultBackgroundColor = "Black" # Set to the colour of your console if 'Black' doesn't look good 
$emailEnable = "False" #True to enable email notification, False to disable
$myEmail = "my@email.com" #Set your Email for notifications
$grpcurl = "bin\grpcurl.exe" #Set GRPCurl path if not in same folder
$fileFormat = 3
$queryHighestAtx = $false
# FileFormat variable sets the type of the file you want to export
# 0 - doesn't export
# 1 - an old format used for Spacemesh Reward Tracker App (by BVale)
# 2 - a new format used for Spacemesh Reward Tracker App (by BVale)
# 3 - use it for layers tracking website (by PlainLazy: http://fcmx.net/sm-eligibilities/)

$nodeList = @(
    @{ name = "Node_01"; host = "192.168.1.xx"; port = 11001; port2 = 11002 },
    @{ name = "Node_02"; host = "192.168.1.xx"; port = 12001; port2 = 12002 },
    @{ name = "Node_03"; host = "192.168.1.xx"; port = 13001; port2 = 13002 },
    @{ name = "Node_04"; host = "192.168.1.xx"; port = 14001; port2 = 14002 },
    @{ name = "SMAPP_Server"; host = "192.168.1.xx"; port = 9092; port2 = 9093 },
    @{ name = "SMAPP_Home"; host = "localhost"; port = 9092; port2 = 9093 }
)
################ Settings Finish ###############

function main {
	[System.Console]::CursorVisible = $false
	$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
	printSMMonitorLogo
	Write-Host "Querying nodes..." -NoNewline -ForegroundColor Cyan       

	$gitVersion = Get-gitNewVersion

	if (Test-Path ".\RewardsTrackApp.tmp") {
		Clear-Content ".\RewardsTrackApp.tmp"
	}

	while ($true) {
        
		$object = @()
		$resultsNodeHighestATX = $null
		$epoch = $null
		$totalLayers = $null
		$rewardsTrackApp = @()
        
		# $nodeList | ForEach-Object   {
		$nodeList | ForEach-Object -ThrottleLimit 16 -Parallel {
			$node = $_
			$grpcurl = $using:grpcurl
            
			if ($null -eq $node.name) {
				$node.name = $node.info	
			}
			Write-Host  " $($node.name)" -NoNewline -ForegroundColor Cyan
        
			$status = $null
			$status = ((Invoke-Expression ("$($grpcurl) --plaintext -max-time 3 $($node.host):$($node.port) spacemesh.v1.NodeService.Status")) | ConvertFrom-Json).status  2>$null
        
			if ($status) {
				Write-Host -NoNewline "." -ForegroundColor Cyan
				$node.online = "True"
				$node.connectedPeers = $status.connectedPeers
				$node.syncedLayer = $status.syncedLayer.number
				$node.topLayer = $status.topLayer.number
				$node.verifiedLayer = $status.verifiedLayer.number
				if ($status.isSynced) {
					$node.synced = "True"
					$node.emailsent = ""
				}
				else { $node.synced = "False" }
			}
			else {
				$node.online = ""
				$node.smeshing = "Offline"
				$node.synced = "Offline"
				$node.connectedPeers = $null
				$node.syncedLayer = $null
				$node.topLayer = $null
				$node.verifiedLayer = $null
				$node.version = $null
			}
        
			if ($node.online) {

				if ($using:queryHighestAtx) {
					$node.highestAtx = ((Invoke-Expression ("$($grpcurl) --plaintext -max-time 100 $($node.host):$($node.port) spacemesh.v1.ActivationService.Highest")) | ConvertFrom-Json).atx 2>$null
				}
				$node.epoch = ((Invoke-Expression ("$($grpcurl) --plaintext -max-time 3 $($node.host):$($node.port) spacemesh.v1.MeshService.CurrentEpoch")) | ConvertFrom-Json).epochnum 2>$null
                
				$version = $null
				$version = ((Invoke-Expression ("$($grpcurl) --plaintext -max-time 3 $($node.host):$($node.port) spacemesh.v1.NodeService.Version")) | ConvertFrom-Json).versionString.value  2>$null
				Write-Host -NoNewline "." -ForegroundColor Cyan
				if ($null -ne $version) {
					$node.version = $version
				}

				$eventstream = (Invoke-Expression ("$($grpcurl) --plaintext -max-time 3 $($node.host):$($node.port2) spacemesh.v1.AdminService.EventsStream")) 2>$null
				$eventstream = $eventstream -split "`n" | Where-Object { $_ }
				$eligibilities = @()
				$atxPublished = @()
				$jsonObject = @()
				$poetWaitProof = @()
				foreach ($line in $eventstream) {
					if ($line -eq "{") {
						$jsonObject = @()
					}
					$jsonObject += $line
					if ($line -eq "}") {
						Try {
							$json = $jsonObject -join "`n" | ConvertFrom-Json
							if ($json.eligibilities) {
								$eligibilities += $json.eligibilities
							}
							if ($json.atxPublished) {
								$atxPublished += $json.atxPublished
							}
							if ($json.poetWaitProof) {
								$poetWaitProof += $json.poetWaitProof
							}
						}
						Catch {
							# Ignore the error and continue
							continue
						}
					}
				}
				$layers = $null
				foreach ($eligibility in $eligibilities) {
					if ($eligibility.epoch -eq $node.epoch.number) {
						$rewardsCount = ($eligibility.eligibilities | Measure-Object).count
						$layers = $eligibility.eligibilities
					}
				}
				if (($rewardsCount) -and ($layers)) {
					$node.rewards = $rewardsCount
					$node.layers = $layers
				}
				$atxTarget = $atxPublished.target
				$poetWait = $poetWaitProof.target
				if ($atxTarget) {
					$node.atx = $atxTarget
				} 
				elseif ($poetWait -and ($null -eq $layers)) {
					$node.atx = $poetWait
				} 
				else {
					$node.atx = "-"
				}
                
				#Uncomment next line if your Smapp using standard configuration -- 1 of 2
				#if (($node.host -eq "localhost") -Or ($node.host -ne "localhost" -And $node.port2 -ne 9093)){ 
				$smeshing = ((Invoke-Expression ("$($grpcurl) --plaintext -max-time 3 $($node.host):$($node.port2) spacemesh.v1.SmesherService.IsSmeshing")) | ConvertFrom-Json)	2>$null
        
				if ($null -ne $smeshing.isSmeshing)
				{ $node.smeshing = "True" } else { $node.smeshing = "False" }
        
				$state = ((Invoke-Expression ("$($grpcurl) --plaintext -max-time 3 $($node.host):$($node.port2) spacemesh.v1.SmesherService.PostSetupStatus")) | ConvertFrom-Json).status 2>$null
				Write-Host -NoNewline "." -ForegroundColor Cyan
                
				if ($state) {
					$node.numUnits = $state.opts.numUnits
                            
					if ($state.state -eq "STATE_IN_PROGRESS") {
						$percent = [math]::round(($state.numLabelsWritten / 1024 / 1024 / 1024 * 16) / ($state.opts.numUnits * 64) * 100, 2)
						$node.smeshing = "$($percent)%"
					}
				}
                
				$publicKey = ((Invoke-Expression ("$($grpcurl) --plaintext -max-time 3 $($node.host):$($node.port2) spacemesh.v1.SmesherService.SmesherID")) | ConvertFrom-Json).publicKey 2>$null
                
				if ($publicKey) {
					$node.key = $publicKey
				}

				#Uncomment next line if your Smapp using standard configuration -- 2 of 2
				#}  
			}            
		}

		$object = $nodeList | ForEach-Object {

			if ($null -eq $resultsNodeHighestATX || $resultsNodeHighestATX.layer.number -lt $_.highestAtx.layer.number) {
				$resultsNodeHighestATX = $_.highestAtx
			}
            
			if ($epoch -lt $_.epoch.number) {
				$epoch = $_.epoch.number
			}
            
			$fullkey = (B64_to_Hex -id2convert $_.key)
			# Extract last 5 digits from SmesherID
			$_.key = $fullkey.substring($fullkey.length - 5, 5)

			$totalLayers = $totalLayers + $_.rewards
			if ($_.layers) {
				if ($fileFormat -eq 1) {
					$rewardsTrackApp = @(@{$fullkey = $_.layers })
					Write-Output $rewardsTrackApp | ConvertTo-Json -depth 100 | Out-File -FilePath RewardsTrackApp.tmp -Append
				}
				elseif ($fileFormat -eq 2) {
					$nodeData = [ordered]@{
						"nodeName"      = $_.name; 
						"nodeID"        = $fullkey; 
						"eligibilities" = $_.layers
					}
					$rewardsTrackApp += $nodeData
				}
				elseif ($fileFormat -eq 3) {
					$layers = $_.layers | ForEach-Object { $_.layer }
					$layers = $layers | Sort-Object
					$layersString = $layers -join ','
					$nodeData = [ordered]@{
						"nodeName"      = $_.name;
						"eligibilities" = $layersString
					}
					$rewardsTrackApp += $nodeData
				}
			}

                 
			[PSCustomObject]@{
				Name        = $_.name
				SmesherID   = $_.key
				Host        = $_.host
				Port        = $_.port
				PortPrivate = $_.port2
				Peers       = $_.connectedPeers
				SU          = $_.numUnits
				SizeTiB     = $_.numUnits * 64 / 1024
				Synced      = $_.synced
				Layer       = $_.syncedLayer
				Top         = $_.topLayer
				Verified    = $_.verifiedLayer
				Version     = $_.version
				Smeshing    = $_.smeshing
				RWD         = $_.rewards
				ELG         = $_.atx
			} 
		}

		if ($rewardsTrackApp -and ($fileFormat -ne 0)) {
			$files = Get-ChildItem -Path .\ -Filter "RewardsTrackApp_*.json"
			foreach ($file in $files) {
				Remove-Item $file.FullName
			}
			$timestamp = Get-Date -Format "HHmm"
			if ($fileFormat -eq 1) {
				$data = (Get-Content RewardsTrackApp.tmp -Raw) -replace '(?m)}\s+{', ',' | ConvertFrom-Json
				$data | ConvertTo-Json -Depth 99 | Set-Content "RewardsTrackApp_$timestamp.json"
				Remove-Item ".\RewardsTrackApp.tmp"
			}
			elseif ($fileFormat -eq 2) {
				$rewardsTrackApp | ConvertTo-Json -Depth 99 | Set-Content "RewardsTrackApp_$timestamp.json"
			}
			elseif (($fileFormat -eq 3)) {
				$rewardsTrackApp | ConvertTo-Json -Depth 99 | Set-Content "SM-Layers.json"
			}
		}
            
		# Find all private nodes, then select the first in the list.  Once we have this, we know that we have a good Online Local Private Node
		$filterObjects = $object | Where-Object { $_.Synced -match "True" -and $_.Smeshing -match "True" } # -and $_.Host -match "localhost" 
		if ($PSVersionTable.PSVersion.Major -eq 5) {
			$filterObjects = $filterObjects | Where-Object { $_.Host -match "localhost" -or $_.Host -match "127.0.0.1" }
		}
		if ($filterObjects) {
			$privateOnlineNodes = $filterObjects[0] #custom setting for me
		}
		else {
			$privateOnlineNodes = $null
		}
        
		# If private nodes are found, determine the PS version and execute corresponding grpcurl if statement. Else skip.
		if ($privateOnlineNodes.name.count -gt 0) {
			if ($PSVersionTable.PSVersion.Major -ge 7) {
				$coinbase = (Invoke-Expression "$grpcurl --plaintext -max-time 10 $($privateOnlineNodes.Host):$($privateOnlineNodes.PortPrivate) spacemesh.v1.SmesherService.Coinbase" | ConvertFrom-Json).accountId.address
				$jsonPayload = "{ `"filter`": { `"account_id`": { `"address`": `"$coinbase`" }, `"account_data_flags`": 4 } }"
				$balance = (Invoke-Expression "$grpcurl -plaintext -d '$jsonPayload' $($privateOnlineNodes.Host):$($privateOnlineNodes.Port) spacemesh.v1.GlobalStateService.AccountDataQuery" | ConvertFrom-Json).accountItem.accountWrapper.stateCurrent.balance.value
				$balanceSMH = [string]([math]::Round($balance / 1000000000, 3)) + " SMH"
				$coinbase = "($coinbase)" 
				if ($fakeCoins -ne 0) { [string]$balanceSMH = "$($fakeCoins) SMH" }
			}
			elseif ($PSVersionTable.PSVersion.Major -eq 5) {
				$coinbase = (Invoke-Expression "$grpcurl --plaintext -max-time 10 $($privateOnlineNodes.Host):$($privateOnlineNodes.PortPrivate) spacemesh.v1.SmesherService.Coinbase" | ConvertFrom-Json).accountId.address
				$command = { & $grpcurl -d '{\"filter\":{\"account_id\":{\"address\":\"$coinbase\"},\"account_data_flags\":4}}' -plaintext localhost:$($privateOnlineNodes.Port) spacemesh.v1.GlobalStateService.AccountDataQuery }
				$command = $command -replace '\$coinbase', $coinbase
				$balance = (Invoke-Expression $command | ConvertFrom-Json).accountItem.accountWrapper.stateCurrent.balance.value
				$balanceSMH = [string]([math]::Round($balance / 1000000000, 3)) + " SMH"
				$coinbase = "($coinbase)" 
				if ($fakeCoins -ne 0) { [string]$balanceSMH = "$($fakeCoins) SMH" }
			}
			if ($coinbaseAddressVisibility -eq "partial") {
				$coinbase = '(' + $($coinbase).Substring($($coinbase).IndexOf(")") - 4, 4) + ')'
			}
			elseif ($coinbaseAddressVisibility -eq "hidden") {
				$coinbase = "(----)"
			}
		}
		else {
			$coinbase = ""
			$balanceSMH = "You must have at least one synced 'localhost' node defined...or Install PowerShell 7"
		}
        
		if ($smhCoinsVisibility -eq $false) {
			$balanceSMH = "----.--- SMH"
		}
        
		$columnRules = applyColumnRules
    
		Clear-Host
		$object | Select-Object Name, SmesherID, Host, Port, Peers, SU, SizeTiB, Synced, Layer, Top, Verified, Version, Smeshing, RWD, ELG | ColorizeMyObject -ColumnRules $columnRules
		Write-Host `n
		Write-Host "-------------------------------------- Info: -----------------------------------" -ForegroundColor Yellow
		Write-Host "Current Epoch: " -ForegroundColor Cyan -nonewline; Write-Host $epoch -ForegroundColor Green
		Write-Host " Total Layers: " -ForegroundColor Cyan -nonewline; Write-Host ($totalLayers) -ForegroundColor Yellow -nonewline; Write-Host " Layers"
		Write-Host "      Balance: " -ForegroundColor Cyan -NoNewline; Write-Host "$balanceSMH" -ForegroundColor White -NoNewline; Write-Host " $($coinbase)" -ForegroundColor Cyan
		if ($queryHighestAtx) {
			if ($null -ne $resultsNodeHighestATX) {
				Write-Host "  Highest ATX: " -ForegroundColor Cyan -nonewline; Write-Host (B64_to_Hex -id2convert $resultsNodeHighestATX.id.id) -ForegroundColor Green
			}
			Write-Host "ATX Base64_ID: " -ForegroundColor Cyan -nonewline; Write-Host $resultsNodeHighestATX.id.id -ForegroundColor Green
			Write-Host "        Layer: " -ForegroundColor Cyan -nonewline; Write-Host $resultsNodeHighestATX.layer.number -ForegroundColor Green
			Write-Host "     NumUnits: " -ForegroundColor Cyan -nonewline; Write-Host $resultsNodeHighestATX.numUnits -ForegroundColor Green
			Write-Host "      PrevATX: " -ForegroundColor Cyan -nonewline; Write-Host $resultsNodeHighestATX.prevAtx.id -ForegroundColor Green
			Write-Host "    SmesherID: " -ForegroundColor Cyan -nonewline; Write-Host $resultsNodeHighestATX.smesherId.id -ForegroundColor Green
		}
		Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Yellow
		Write-Host "ELG - The number of Epoch when the node will be eligible for rewards. " -ForegroundColor DarkGray

		Write-Host `n
		$newline = "`r`n"
            
		#Version Check
		if ($null -ne $gitVersion) {
			$currentVersion = $gitVersion -replace "[^.0-9]"
			Write-Host "Github Go-Spacemesh version: $($gitVersion)" -ForegroundColor Green
			foreach ($node in ($object | Where-Object { $_.synced -notmatch "Offline" })) {
				$node.version = $node.version -replace "[^.0-9]"
				if ([version]$node.version -lt [version]$currentVersion) {
					Write-Host "Info:" -ForegroundColor White -nonewline; Write-Host " --> Some of your nodes are Outdated!" -ForegroundColor DarkYellow
					break
				}
			}
		}		
                
		if ("Offline" -in $object.synced) {
			Write-Host "Info:" -ForegroundColor White -nonewline; Write-Host " --> Some of your nodes are Offline!" -ForegroundColor DarkYellow
			if ($emailEnable -eq "True" -And (isValidEmail($myEmail))) {
				$Body = "Warning, some nodes are offline!"
        
				foreach ($node in $nodeList) {
					if (!$node.online) {
						$Body = $body + $newLine + $node.name + " " + $node.Host + " " + $node.Smeshing 
						if (!$node.emailsent) {
							$OKtoSend = "True"
							$node.emailsent = "True"
						}
					}
				}
                        
				if ($OKtoSend) {
					$From = "001smmonitor@gmail.com"
					$To = $myEmail
					$Subject = "Your Spacemesh node is offline"
                    
					# Define the SMTP server details
					$SMTPServer = "smtp.gmail.com"
					$SMTPPort = 587
					$SMTPUsername = "001smmonitor@gmail.com"
					$SMTPPassword = "uehd zqix qrbh gejb"
        
					# Create a new email object
					$Email = New-Object System.Net.Mail.MailMessage
					$Email.From = $From
					$Email.To.Add($To)
					$Email.Subject = $Subject
					$Email.Body = $Body
					# Uncomment below to send HTML formatted email
					#$Email.IsBodyHTML = $true
        
					# Create an SMTP client object and send the email
					$SMTPClient = New-Object System.Net.Mail.SmtpClient($SMTPServer, $SMTPPort)
					$SMTPClient.EnableSsl = $true
					$SMTPClient.Credentials = New-Object System.Net.NetworkCredential($SMTPUsername, $SMTPPassword)
                    
					Try {
						$SMTPClient.Send($Email)
					}
					Catch {
						Write-Host "oops! SMTP error, please check your settings." -ForegroundColor DarkRed
					}
					Finally {
						Write-Host "Email sent..." -ForegroundColor DarkYellow
						$OKtoSend = ""
					}
				}
			}
		}
        
		$currentDate = Get-Date -Format HH:mm:ss
		# Refresh
		Write-Host `n                
		Write-Host "Last refresh: " -ForegroundColor Yellow -nonewline; Write-Host "$currentDate" -ForegroundColor Green;
        
		# Get original position of cursor
		$originalPosition = $host.UI.RawUI.CursorPosition
        
		# Refresh Timeout
		$iterations = [math]::Ceiling($tableRefreshTimeSeconds / 5)       
		for ($i = 0; $i -lt $iterations; $i++) {
			Write-Host -NoNewline "." -ForegroundColor Cyan
			Start-Sleep 5
		}
		$clearmsg = " " * ([System.Console]::WindowWidth - 1)  
		[Console]::SetCursorPosition($originalPosition.X, $originalPosition.Y)
		[System.Console]::Write($clearmsg) 
		[Console]::SetCursorPosition($originalPosition.X, $originalPosition.Y)
		Write-Host "Updating..." -NoNewline -ForegroundColor Cyan
        
		$HoursElapsed = $Stopwatch.Elapsed.TotalHours
		if ($HoursElapsed -ge 1) {
			$gitNewVersion = Get-gitNewVersion
			if ($gitNewVersion) {
				$gitVersion = $gitNewVersion
			}
			$Stopwatch.Restart()
		}
	}
}

function IsValidEmail { 
	param([string]$Email)
	$Regex = '^([\w-\.]+)@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.)|(([\w-]+\.)+))([a-zA-Z]{2,4}|[0-9]{1,3})(\]?)$'
        
	try {
		$obj = [mailaddress]$Email
		if ($obj.Address -match $Regex) {
			return $True
		}
		return $False
	}
	catch {
		return $False
	} 
}
        
function B64_to_Hex {
	param (
		[Parameter(Position = 0, Mandatory = $true)]
		[string]$id2convert
	)
	[System.BitConverter]::ToString([System.Convert]::FromBase64String($id2convert)).Replace("-", "")
}
function Hex_to_B64 {
	param (
		[Parameter(Position = 0, Mandatory = $true)]
		[string]$id2convert
	)
	$NODE_ID_BYTES = for ($i = 0; $i -lt $id2convert.Length; $i += 2) { [Convert]::ToByte($id2convert.Substring($i, 2), 16) }
	[System.Convert]::ToBase64String($NODE_ID_BYTES)
}
function ColorizeMyObject {
	param (
		[Parameter(ValueFromPipeline = $true)]
		$InputObject,
        
		[Parameter(Mandatory = $true)]
		[System.Collections.ArrayList]$ColumnRules
	)
        
	begin {
		$dataBuffer = @()
	}
        
	process {
		$dataBuffer += $InputObject
	}
        
	end {
		$headers = $dataBuffer[0].PSObject.Properties.Name
        
		$maxWidths = @{}
		foreach ($header in $headers) {
			$headerLength = "$header".Length
			$dataMaxLength = ($dataBuffer | ForEach-Object { "$($_.$header)".Length } | Measure-Object -Maximum).Maximum
			$maxWidths[$header] = [Math]::Max($headerLength, $dataMaxLength)
		}
            
		$headers | ForEach-Object { 
			$paddedHeader = $_.PadRight($maxWidths[$_])
			Write-Host $paddedHeader -NoNewline; 
			Write-Host "  " -NoNewline 
		}
		Write-Host ""
        
		$headers | ForEach-Object {
			$dashes = '-' * $maxWidths[$_]
			Write-Host $dashes -NoNewline
			Write-Host "  " -NoNewline
		}
		Write-Host ""
            
		foreach ($row in $dataBuffer) {
			foreach ($header in $headers) {
				$propertyValue = "$($row.$header)"
				$foregroundColor = $null
				$backgroundColor = $null
        
				foreach ($rule in $ColumnRules) {
					if ($header -eq $rule.Column) {
						if ($propertyValue -like $rule.Value) {
							$foregroundColor = $rule.ForegroundColor
							if ($rule.BackgroundColor) {
								$backgroundColor = $rule.BackgroundColor
							}
							#break
						}
					}
				}
        
				$paddedValue = $propertyValue.PadRight($maxWidths[$header])
        
				if ($foregroundColor -or $backgroundColor) {
					if ($backgroundColor) {
						Write-Host $paddedValue -NoNewline -ForegroundColor $foregroundColor -BackgroundColor $backgroundColor
					}
					else {
						Write-Host $paddedValue -NoNewline -ForegroundColor $foregroundColor
					}
				}
				else {
					Write-Host $paddedValue -NoNewline
				}
        
				Write-Host "  " -NoNewline
			}
			Write-Host ""
		}
	}
}

function Get-gitNewVersion {
	.{
		$gitNewVersion = Invoke-RestMethod -Method 'GET' -uri "https://api.github.com/repos/spacemeshos/go-spacemesh/releases/latest" 2>$null
		if ($gitNewVersion) {
			$gitNewVersion = $gitNewVersion.tag_name
		}
	} | Out-Null
	return $gitNewVersion
}
        
function printSMMonitorLogo {
	Clear-Host
	$foregroundColor = "Green"
	$highlightColor = "Yellow"
	$charDelay = 0  # milliseconds
	$colDelay = 0  # milliseconds
	$logoWidth = 86  # Any time you change the logo, all rows have to be the exact width.  Then assign to this var.
	$logoHeight = 9  # Any time you change the logo, recount the rows and assign to this var.
        
	$screenWidth = $host.UI.RawUI.WindowSize.Width
	$screenHeight = $host.UI.RawUI.WindowSize.Height
	$horizontalOffset = [Math]::Max(0, [Math]::Ceiling(($screenWidth - $logoWidth) / 2))
	$verticalOffset = [Math]::Max(0, [Math]::Ceiling(($screenHeight - $logoHeight) / 2))
        
	$asciiArt = @"
      _________   _____               _____                 __  __                    
/\   /   _____/  /     \             /     \   ____   ____ |__|/  |_  ___________   /\
\/   \_____  \  /  \ /  \   ______  /  \ /  \ /  _ \ /    \|  \   __\/  _ \_  __ \  \/
/\   /        \/    Y    \ /_____/ /    Y    (  <_> )   |  \  ||  | (  <_> )  | \/  /\
\/  /_______  /\____|__  /         \____|__  /\____/|___|  /__||__|  \____/|__|     \/
              \/         \/                  \/            \/                               
                 _____________________________________________________________________     
                /_____/_____/_____/_____/_____/  https://github.com/xeliuqa/SM-Monitor     
                                                              https://www.spacemesh.io     
"@
    
	$lines = $asciiArt -split "`n"
                                                            
	for ($col = 1; $col -le $lines[0].Length; $col++) {
		for ($row = 1; $row -le $lines.Length; $row++) {
			$char = if ($col - 1 -lt $lines[$row - 1].Length) { $lines[$row - 1][$col - 1] } else { ' ' }
			$CursorPosition = [System.Management.Automation.Host.Coordinates]::new($col + $horizontalOffset, $row + $verticalOffset)
			$host.UI.RawUI.CursorPosition = $CursorPosition
			if ($char -eq ' ') {
				Write-Host $char -NoNewline
			}
			else {
				Write-Host $char -NoNewline -ForegroundColor $highlightColor
			}
			Start-Sleep -Milliseconds $charDelay
		}
		for ($row = 1; $row -le $lines.Length; $row++) {
			$char = if ($col - 1 -lt $lines[$row - 1].Length) { $lines[$row - 1][$col - 1] } else { ' ' }
			$CursorPosition = [System.Management.Automation.Host.Coordinates]::new($col + $horizontalOffset, $row + $verticalOffset)
			$host.UI.RawUI.CursorPosition = $CursorPosition
			if ($char -eq ' ') {
				Write-Host $char -NoNewline
			}
			else {
				Write-Host $char -NoNewline -ForegroundColor $foregroundColor
			}
		}
		Start-Sleep -Milliseconds $colDelay
	}
                                                            
	$CursorPosition = [System.Management.Automation.Host.Coordinates]::new(0, $lines.Length + $verticalOffset + 1)
	$host.UI.RawUI.CursorPosition = $CursorPosition
	# Start-Sleep $logoDelay
	# Clear-Host
}

function applyColumnRules {
	# Colors: Black, Blue, Cyan, DarkBlue, DarkCyan, DarkGray, DarkGreen, DarkMagenta, DarkRed, DarkYellow, Gray, Green, Magenta, Red, White, Yellow
	return	@(
		@{ Column = "Name"; Value = "*"; ForegroundColor = "Cyan"; BackgroundColor = $DefaultBackgroundColor },
		@{ Column = "SmesherID"; Value = "*"; ForegroundColor = "Yellow"; BackgroundColor = $DefaultBackgroundColor },
		@{ Column = "Host"; Value = "*"; ForegroundColor = "White"; BackgroundColor = $DefaultBackgroundColor },
		@{ Column = "Port"; ForegroundColor = "White"; BackgroundColor = $DefaultBackgroundColor },
		@{ Column = "Peers"; Value = "*"; ForegroundColor = "DarkCyan"; BackgroundColor = $DefaultBackgroundColor },
		@{ Column = "Peers"; Value = "0"; ForegroundColor = "DarkGray"; BackgroundColor = $DefaultBackgroundColor },
		@{ Column = "SU"; Value = "*"; ForegroundColor = "Yellow"; BackgroundColor = $DefaultBackgroundColor },
		@{ Column = "SizeTiB"; Value = "*"; ForegroundColor = "White"; BackgroundColor = $DefaultBackgroundColor },
		@{ Column = "Synced"; Value = "True"; ForegroundColor = "Green"; BackgroundColor = $DefaultBackgroundColor },
		@{ Column = "Synced"; Value = "False"; ForegroundColor = "DarkRed"; BackgroundColor = $DefaultBackgroundColor },
		@{ Column = "Synced"; Value = "Offline"; ForegroundColor = "DarkGray"; BackgroundColor = $DefaultBackgroundColor },
		@{ Column = "Layer Top Verified"; Value = "*"; ForegroundColor = "White"; BackgroundColor = $DefaultBackgroundColor },
		@{ Column = "Version"; Value = "*"; ForegroundColor = "Red"; BackgroundColor = $DefaultBackgroundColor },
		@{ Column = "Version"; Value = $gitVersion; ForegroundColor = "Green"; BackgroundColor = $DefaultBackgroundColor },
		@{ Column = "Version"; Value = "Offline"; ForegroundColor = "DarkGray"; BackgroundColor = $DefaultBackgroundColor },
		@{ Column = "Smeshing"; Value = "*"; ForegroundColor = "Yellow"; BackgroundColor = $DefaultBackgroundColor },
		@{ Column = "Smeshing"; Value = "True"; ForegroundColor = "Green"; BackgroundColor = $DefaultBackgroundColor },
		@{ Column = "Smeshing"; Value = "False"; ForegroundColor = "DarkRed"; BackgroundColor = $DefaultBackgroundColor },
		@{ Column = "Smeshing"; Value = "Offline"; ForegroundColor = "DarkGray"; BackgroundColor = $DefaultBackgroundColor },
		@{ Column = "RWD"; Value = "*"; ForegroundColor = "Yellow"; BackgroundColor = $DefaultBackgroundColor },
		@{ Column = "ELG"; Value = "*"; ForegroundColor = "Green"; BackgroundColor = $DefaultBackgroundColor },
		@{ Column = "ELG"; Value = "-"; ForegroundColor = "White"; BackgroundColor = $DefaultBackgroundColor }
		@{ Column = "ELG"; Value = $poetWait; ForegroundColor = "Yellow"; BackgroundColor = $DefaultBackgroundColor }
	)
}

main
    
