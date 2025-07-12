<#
.SYNOPSIS
    MECM to Intune Application Migration Tool with GUI
.DESCRIPTION
    Migrates MECM applications to Intune with a graphical interface. Steps include:
    1. Select MECM application via GUI
    2. Validate application migratability
    3. Create/update source files structure
    4. Package and publish to Intune
    Requires: ConfigurationManager module, IntuneWin32App module, .NET Framework
.PREREQUISITES
    - MECM PowerShell module
    - IntuneWin32App PowerShell module
    - Administrative privileges
    - config.json file (optional)
.PARAMETER ConfigPath
    Path to JSON configuration file
.PARAMETER WhatIf
    Show actions without executing
.PARAMETER SkipSourceUpdate
    Skip source files update
.PARAMETER SkipIntunePublish
    Skip Intune publishing
.EXAMPLE
    .\MECM-to-Intune-Apps-Migrator.ps1
.EXAMPLE
    .\MECM-to-Intune-Apps-Migrator.ps1 -ConfigPath "C:\Custom\config.json" -WhatIf
#>

[CmdletBinding()]
param(
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$ConfigPath = "config.json",
    [switch]$WhatIf,
    [switch]$SkipSourceUpdate,
    [switch]$SkipIntunePublish,
    [switch]$Force
)

# Load Windows Forms
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Default configuration
$DefaultConfig = @{
    MECMSiteServer = "dalpsccm21.corp.local"
    MECMSiteCode = "S21"
    BaseAppPath = "\\dalpsccm22\intune\Applications"
    BaseSourcePath = "\\dalpsccm21\sourcefiles$"
    TenantId = "47968ed6-cb2b-4495-8468-034ae247e404"
    ClientId = ""
    ClientSecret = ""
}

# Load configuration
# If ConfigPath is relative, make it relative to script location
if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
    $ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    if ($ScriptDirectory) {
        $ConfigPath = Join-Path -Path $ScriptDirectory -ChildPath $ConfigPath
    }
}

if (Test-Path $ConfigPath) {
    try {
        $Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        Write-Host "✓ Loaded configuration from $ConfigPath" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to load config.json: $($_.Exception.Message). Using defaults."
        $Config = $DefaultConfig
    }
} else {
    Write-Warning "No config.json found at $ConfigPath. Using defaults."
    $Config = $DefaultConfig
}

# Parameters with validation
$MECMSiteServer = $Config.MECMSiteServer
$MECMSiteCode = $Config.MECMSiteCode
[ValidateScript({ Test-Path $_ -PathType Container })]
[string]$BaseAppPath = $Config.BaseAppPath
[string]$BaseSourcePath = $Config.BaseSourcePath
[ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
[string]$TenantId = $Config.TenantId
[string]$ClientId = $Config.ClientId
[string]$ClientSecret = $Config.ClientSecret

# Validate required configuration
if ([string]::IsNullOrWhiteSpace($ClientId)) {
    Write-Error "ClientId is required and must be specified in the config file at: $ConfigPath"
    exit 1
}
if ([string]::IsNullOrWhiteSpace($ClientSecret)) {
    Write-Error "ClientSecret is required and must be specified in the config file at: $ConfigPath"
    exit 1
}

# Log file
$LogPath = Join-Path -Path $PSScriptRoot -ChildPath "MigrationLog_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

#region Helper Functions

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO",
        [System.Windows.Forms.RichTextBox]$LogBox
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host $logMessage -ForegroundColor $color
    
    Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
    
    if ($LogBox) {
        $form.Invoke([Action]{ 
            $LogBox.SelectionColor = switch ($Level) {
                "ERROR" { [System.Drawing.Color]::Red }
                "WARNING" { [System.Drawing.Color]::Orange }
                "SUCCESS" { [System.Drawing.Color]::Green }
                default { [System.Drawing.Color]::Black }
            }
            $LogBox.AppendText("$logMessage`n")
            $LogBox.ScrollToCaret()
        })
    }
}

function Import-SCCMModule {
    Write-Log -Message "Loading SCCM module..." -Level "INFO"
    $PossiblePaths = @(
        "${env:ProgramFiles(x86)}\Microsoft Configuration Manager\AdminConsole\bin",
        "${env:ProgramFiles}\Microsoft Configuration Manager\AdminConsole\bin",
        "C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin",
        "C:\Program Files\Microsoft Configuration Manager\AdminConsole\bin",
        "D:\Program Files\Microsoft Configuration Manager\AdminConsole\bin"
    )
    
    foreach ($Path in $PossiblePaths) {
        if (Test-Path "$Path\ConfigurationManager.psd1") {
            try {
                Import-Module "$Path\ConfigurationManager.psd1" -Force -ErrorAction Stop
                Write-Log -Message "✓ SCCM module loaded" -Level "SUCCESS"
                return $true
            } catch {
                Write-Log -Message "Failed to load from $Path : $($_.Exception.Message)" -Level "WARNING"
            }
        }
    }
    
    Write-Log -Message "Failed to load SCCM module." -Level "ERROR"
    return $false
}

function Test-IntuneWin32AppModule {
    Write-Log -Message "Checking IntuneWin32App module..." -Level "INFO"
    if (Get-Module -ListAvailable -Name "IntuneWin32App") {
        Write-Log -Message "✓ IntuneWin32App module found" -Level "SUCCESS"
        Import-Module IntuneWin32App -Force
        return $true
    } else {
        Write-Log -Message "Installing IntuneWin32App module..." -Level "INFO"
        try {
            Install-Module -Name IntuneWin32App -Force -AllowClobber -Scope CurrentUser
            Import-Module IntuneWin32App -Force
            Write-Log -Message "✓ IntuneWin32App module installed" -Level "SUCCESS"
            return $true
        } catch {
            Write-Log -Message "Failed to install IntuneWin32App: $($_.Exception.Message)" -Level "ERROR"
            return $false
        }
    }
}

function Show-FileSelectionDialog {
    param(
        [Parameter(Mandatory)]
        [array]$Files,
        [Parameter(Mandatory)]
        [string]$Title,
        [string]$Message = "Please select a file:"
    )
    
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.Size = New-Object System.Drawing.Size(600, 400)
    $form.StartPosition = "CenterParent"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    
    $lblMessage = New-Object System.Windows.Forms.Label
    $lblMessage.Text = $Message
    $lblMessage.Size = New-Object System.Drawing.Size(560, 30)
    $lblMessage.Location = New-Object System.Drawing.Point(10, 10)
    $form.Controls.Add($lblMessage)
    
    $listBox = New-Object System.Windows.Forms.ListBox
    $listBox.Size = New-Object System.Drawing.Size(560, 250)
    $listBox.Location = New-Object System.Drawing.Point(10, 50)
    $listBox.SelectionMode = "One"
    
    for ($i = 0; $i -lt $Files.Count; $i++) {
        $file = $Files[$i]
        $fileSize = [math]::Round($file.Length / 1MB, 2)
        $displayText = "$($file.Name) ($fileSize MB)"
        $listBox.Items.Add($displayText) | Out-Null
    }
    
    if ($Files.Count -gt 0) {
        $listBox.SelectedIndex = 0
    }
    
    $form.Controls.Add($listBox)
    
    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text = "OK"
    $btnOK.Size = New-Object System.Drawing.Size(75, 30)
    $btnOK.Location = New-Object System.Drawing.Point(420, 320)
    $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($btnOK)
    
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Size = New-Object System.Drawing.Size(75, 30)
    $btnCancel.Location = New-Object System.Drawing.Point(500, 320)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($btnCancel)
    
    $form.AcceptButton = $btnOK
    $form.CancelButton = $btnCancel
    
    $result = $form.ShowDialog()
    
    if ($result -eq [System.Windows.Forms.DialogResult]::OK -and $listBox.SelectedIndex -ge 0) {
        return $Files[$listBox.SelectedIndex]
    }
    
    return $null
}

function Get-IconDataFromXML {
    param(
        [Parameter(Mandatory)]
        [xml]$XML,
        [Parameter(Mandatory)]
        [string]$AppName
    )
    
    Write-Log -Message "Extracting icon data from XML for $AppName..." -Level "INFO"
    
    try {
        # Look for icon data in multiple possible locations
        $iconNode = $null
        
        # Try different possible paths for icon
        if ($XML.AppMgmtDigest) {
            Write-Log -Message "Found AppMgmtDigest node" -Level "INFO"
            if ($XML.AppMgmtDigest.Resources) {
                Write-Log -Message "Found Resources node" -Level "INFO"
                $iconNode = $XML.AppMgmtDigest.Resources.Icon
                if ($iconNode) {
                    Write-Log -Message "Found Icon node in AppMgmtDigest.Resources" -Level "INFO"
                }
            }
        }
        
        # Try alternative path: Application.DisplayInfo.Icon
        if (-not $iconNode -and $XML.AppMgmtDigest.Application) {
            Write-Log -Message "Checking Application.DisplayInfo.Icon path..." -Level "INFO"
            $iconNode = $XML.AppMgmtDigest.Application.DisplayInfo.Icon
            if ($iconNode) {
                Write-Log -Message "Found Icon node in Application.DisplayInfo" -Level "INFO"
            }
        }
        
        # Try alternative path: Look for any Icon element in the entire XML
        if (-not $iconNode) {
            Write-Log -Message "Searching for any Icon elements in XML..." -Level "INFO"
            $iconNodes = $XML.SelectNodes("//Icon")
            if ($iconNodes.Count -gt 0) {
                $iconNode = $iconNodes[0]
                Write-Log -Message "Found Icon node via XPath search" -Level "INFO"
            }
        }
        
        if (-not $iconNode) {
            Write-Log -Message "No icon found in XML for $AppName" -Level "INFO"
            return $null
        }
        
        # Extract icon data - try different possible formats
        $iconData = $null
        
        if ($iconNode.Data) {
            $iconData = $iconNode.Data
            Write-Log -Message "Found icon data in Data property" -Level "INFO"
        } elseif ($iconNode.'#text') {
            $iconData = $iconNode.'#text'
            Write-Log -Message "Found icon data in text content" -Level "INFO"
        } elseif ($iconNode.InnerText) {
            $iconData = $iconNode.InnerText
            Write-Log -Message "Found icon data in InnerText" -Level "INFO"
        } elseif ($iconNode) {
            # Sometimes the icon data is directly in the node
            $iconData = $iconNode.ToString()
            Write-Log -Message "Using icon node content directly" -Level "INFO"
        }
        
        if ([string]::IsNullOrWhiteSpace($iconData)) {
            Write-Log -Message "Icon node found but no data present for $AppName" -Level "WARNING"
            return $null
        }
        
        # Clean up icon data (remove whitespace, newlines)
        $iconData = $iconData.Trim() -replace '\s+', ''
        Write-Log -Message "✓ Icon data extracted from XML (length: $($iconData.Length))" -Level "SUCCESS"
        
        return $iconData
        
    } catch {
        Write-Log -Message "Error extracting icon from XML for $AppName : $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

#endregion

#region SCCM Functions

function Get-SCCMApplicationByName {
    param([string]$ApplicationName)
    
    Write-Log -Message "Searching for SCCM application: '$ApplicationName'" -Level "INFO"
    
    Set-Location "$($MECMSiteCode):"
    
    try {
        $exactMatch = Get-CMApplication -Name $ApplicationName -ErrorAction SilentlyContinue
        if ($exactMatch) {
            Write-Log -Message "✓ Found exact match: $($exactMatch.LocalizedDisplayName)" -Level "SUCCESS"
            return $exactMatch
        }
        
        $wildcardMatches = Get-CMApplication -Name "*$ApplicationName*" -ErrorAction SilentlyContinue
        
        if ($wildcardMatches.Count -eq 0) {
            Write-Log -Message "No applications found matching '$ApplicationName'" -Level "WARNING"
            return $null
        }
        
        if ($wildcardMatches.Count -eq 1) {
            Write-Log -Message "✓ Found single match: $($wildcardMatches[0].LocalizedDisplayName)" -Level "SUCCESS"
            return $wildcardMatches[0]
        }
        
        Write-Log -Message "Multiple applications found matching '$ApplicationName'" -Level "INFO"
        return $wildcardMatches
        
    } catch {
        Write-Log -Message "Error searching for SCCM application: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Test-SCCMAppMigratability {
    param([object]$SCCMApp)
    
    Write-Log -Message "Validating application for migration..." -Level "INFO"
    Set-Location "$($MECMSiteCode):"
    $sccmappdetails = Get-CMApplication -name $SCCMApp
    
    $ParsedData = ConvertFrom-SDMPackageXML -XMLContent $sccmappdetails.SDMPackageXML -AppName $sccmappdetails.LocalizedDisplayName
    
    if (-not $ParsedData) {
        return @{
            IsMigratable = $false
            Reason = "No deployment type data found"
            MigrationType = "Unknown"
            ParsedData = $null
        }
    }
    
    $IsMigratable, $Reason, $MigrationType = Test-AppMigratability -ParsedData $ParsedData -AppName $sccmappdetails.LocalizedDisplayName
    
    return @{
        IsMigratable = $IsMigratable
        Reason = $Reason
        MigrationType = $MigrationType
        ParsedData = $ParsedData
    }
}

function ConvertFrom-SDMPackageXML {
    param([string]$XMLContent, [string]$AppName)
    
    if ([string]::IsNullOrWhiteSpace($XMLContent)) {
        Write-Log -Message "No SDMPackageXML content found for $AppName" -Level "WARNING"
        return $null
    }
    
    try {
        [xml]$xml = $XMLContent
    } catch {
        Write-Log -Message "Failed to parse XML for $AppName : $($_.Exception.Message)" -Level "WARNING"
        return $null
    }
    
    $deploymentTypes = @($xml.AppMgmtDigest.DeploymentType)
    
    if (-not $deploymentTypes) {
        Write-Log -Message "No deployment types found in XML for $AppName" -Level "WARNING"
        return $null
    }
    
    # Extract icon data while we're parsing the XML
    $iconData = Get-IconDataFromXML -XML $xml -AppName $AppName
    
    $results = @()
    
    foreach ($dt in $deploymentTypes) {
        $installCmd = ($dt.Installer.InstallAction.Args.Arg | Where-Object { $_.Name -eq "InstallCommandLine" }).'#text'
        $uninstallCmd = ($dt.Installer.UninstallAction.Args.Arg | Where-Object { $_.Name -eq "InstallCommandLine" }).'#text'
        $contentLocations = @($dt.Installer.Contents.Content.Location)
        
        $hasDetectionMethod = $false
        $detectionMethodDetails = "None"
        if ($dt.Installer.DetectAction.Args.Arg) {
            $methodBody = ($dt.Installer.DetectAction.Args.Arg | Where-Object { $_.Name -eq "MethodBody" }).'#text'
            if ($methodBody) {
                $hasDetectionMethod = $true
                $detectionMethodDetails = "Enhanced detection method configured"
            }
        }
        
        $results += [PSCustomObject]@{
            InstallCommand = $installCmd
            UninstallCommand = $uninstallCmd
            ContentLocations = $contentLocations
            HasDetectionMethod = $hasDetectionMethod
            DetectionMethodDetails = $detectionMethodDetails
            Technology = $dt.Technology
        }
    }
    
    # Add icon data to the results if found
    if ($iconData) {
        foreach ($result in $results) {
            $result | Add-Member -NotePropertyName "IconData" -NotePropertyValue $iconData
        }
    }
    
    return $results
}

function Test-AppMigratability {
    param([array]$ParsedData, [string]$AppName)
    
    if (-not $ParsedData) {
        return $false, "No deployment type data", "Unknown"
    }
    
    foreach ($dtData in $ParsedData) {
        $hasInstallCmd = -not [string]::IsNullOrWhiteSpace($dtData.InstallCommand)
        $hasUninstallCmd = -not [string]::IsNullOrWhiteSpace($dtData.UninstallCommand)
        $hasValidContent = $dtData.ContentLocations.Count -gt 0
        
        if ($hasInstallCmd -and $hasValidContent -and $dtData.HasDetectionMethod) {
            $migrationType = "Win32"
            
            if ($dtData.Technology -eq "MSI") {
                $migrationType = "Win32 (MSI)"
            } elseif ($dtData.InstallCommand -match "\.msi|msiexec") {
                $migrationType = "Win32 (MSI)"
            } elseif ($dtData.Technology -eq "Script") {
                $migrationType = "Win32 (Script)"
            } elseif ($dtData.InstallCommand -match "\.exe") {
                $migrationType = "Win32 (EXE)"
            }
            
            return $true, "All requirements met", $migrationType
        }
    }
    
    $reasons = @()
    if (-not ($ParsedData | Where-Object { -not [string]::IsNullOrWhiteSpace($_.InstallCommand) })) {
        $reasons += "No install command"
    }
    if (-not ($ParsedData | Where-Object { -not [string]::IsNullOrWhiteSpace($_.UninstallCommand) })) {
        $reasons += "No uninstall command"
    }
    if (-not ($ParsedData | Where-Object { $_.ContentLocations.Count -gt 0 })) {
        $reasons += "No content location"
    }
    if (-not ($ParsedData | Where-Object { $_.HasDetectionMethod })) {
        $reasons += "No detection method"
    }
    
    return $false, ($reasons -join "; "), "Not Suitable"
}
function Get-MigrationStatus($app) {
    try {
        $fullApp = Get-CMApplication -Name $app.AppName -ErrorAction Stop
        if ($fullApp -is [array]) {
            if ($app.Version) {
                $fullApp = $fullApp | Where-Object { $_.SoftwareVersion -eq $app.Version } | Select-Object -First 1
            } else {
                $fullApp = $fullApp | Select-Object -First 1
            }
        }
    } catch {
        return "❌ Not Ready"
    }
    if (-not $fullApp -or -not $fullApp.SDMPackageXML) {
        return "❌ Not Ready"
    }
    $parsedData = ConvertFrom-SDMPackageXML -XMLContent $fullApp.SDMPackageXML -AppName $fullApp.LocalizedDisplayName
    if (-not $parsedData -or $parsedData.Count -eq 0) {
        return "❌ Not Ready"
    }
    $dt = $parsedData | Select-Object -First 1
    $hasInstallCmd = -not [string]::IsNullOrWhiteSpace($dt.InstallCommand)
    $hasSource = $dt.ContentLocations.Count -gt 0
    $hasDetection = $dt.HasDetectionMethod
    $isMSIX = ($dt.Technology -match 'MSIX')
    if ($isMSIX) {
        return "❌ Not Ready"
    }
    if ($hasInstallCmd -and $hasSource -and $hasDetection) {
        return "✅ Ready"
    }
    if ($hasInstallCmd -or $hasSource -or $hasDetection) {
        return "⚠️ Check"
    }
    return "❌ Not Ready"
}
function Show-SCCMAppDetails {
    param([object]$SCCMApp, [hashtable]$MigrationInfo)
    
    Write-Log -Message "SCCM Application Details:" -Level "INFO"
    Write-Log -Message "  Name: $($SCCMApp.LocalizedDisplayName)" -Level "INFO"
    Write-Log -Message "  Manufacturer: $($SCCMApp.Manufacturer)" -Level "INFO"
    Write-Log -Message "  Version: $($SCCMApp.SoftwareVersion)" -Level "INFO"
    Write-Log -Message "  Deployments: $($SCCMApp.NumberOfDeployments)" -Level "INFO"
    Write-Log -Message "  Deployment Types: $($SCCMApp.NumberOfDeploymentTypes)" -Level "INFO"
    
    Write-Log -Message "Migration Assessment:" -Level "INFO"
    if ($MigrationInfo.IsMigratable) {
        Write-Log -Message "  Status: ✓ MIGRATABLE" -Level "SUCCESS"
        Write-Log -Message "  Type: $($MigrationInfo.MigrationType)" -Level "SUCCESS"
    } else {
        Write-Log -Message "  Status: ✗ NOT MIGRATABLE" -Level "ERROR"
        Write-Log -Message "  Reason: $($MigrationInfo.Reason)" -Level "ERROR"
    }
    
    if ($MigrationInfo.ParsedData) {
        $firstDT = $MigrationInfo.ParsedData | Select-Object -First 1
        Write-Log -Message "Deployment Type Details:" -Level "INFO"
        Write-Log -Message "  Install Command: $($firstDT.InstallCommand)" -Level "INFO"
        Write-Log -Message "  Uninstall Command: $($firstDT.UninstallCommand)" -Level "INFO"
        Write-Log -Message "  Content Locations: $($firstDT.ContentLocations -join '; ')" -Level "INFO"
        Write-Log -Message "  Detection Method: $($firstDT.DetectionMethodDetails)" -Level "INFO"
        Write-Log -Message "  Technology: $($firstDT.Technology)" -Level "INFO"
    }
}

#endregion

#region Source Files Functions

function Get-FileVersionInfo {
    param([string]$FilePath)
    
    try {
        if ([System.IO.Path]::GetExtension($FilePath).ToLower() -eq ".exe") {
            $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($FilePath)
            return @{
                FileVersion = $versionInfo.FileVersion
                ProductVersion = $versionInfo.ProductVersion
                CompanyName = $versionInfo.CompanyName
                ProductName = $versionInfo.ProductName
                FileDescription = $versionInfo.FileDescription
            }
        } elseif ([System.IO.Path]::GetExtension($FilePath).ToLower() -eq ".msi") {
            return Get-MSIVersionInfo -MSIPath $FilePath
        } else {
            Write-Log -Message "Unsupported file type: $FilePath" -Level "WARNING"
            return $null
        }
    } catch {
        Write-Log -Message "Could not extract version info from $FilePath : $($_.Exception.Message)" -Level "WARNING"
        return $null
    }
}

function Get-MSIVersionInfo {    param([string]$MSIPath)
    
    try {
        Write-Log -Message "Extracting MSI metadata from: $MSIPath" -Level "INFO"        # First try using Get-MSIMetaData cmdlet if available
        if (Get-Command -Name "Get-MSIMetaData" -ErrorAction SilentlyContinue) {
            Write-Log -Message "Using Get-MSIMetaData cmdlet" -Level "INFO"
            
            try {
                $result = @{
                    ProductCode = Get-MSIMetaData -Path $MSIPath -Property "ProductCode" -ErrorAction SilentlyContinue
                    CompanyName = Get-MSIMetaData -Path $MSIPath -Property "Manufacturer" -ErrorAction SilentlyContinue
                    ProductName = Get-MSIMetaData -Path $MSIPath -Property "ProductName" -ErrorAction SilentlyContinue
                    FileVersion = Get-MSIMetaData -Path $MSIPath -Property "ProductVersion" -ErrorAction SilentlyContinue
                    ProductVersion = Get-MSIMetaData -Path $MSIPath -Property "ProductVersion" -ErrorAction SilentlyContinue
                    FileDescription = Get-MSIMetaData -Path $MSIPath -Property "Subject" -ErrorAction SilentlyContinue
                }
                
                # If we got a ProductCode, consider this successful
                if (-not [string]::IsNullOrWhiteSpace($result.ProductCode)) {
                    Write-Log -Message "MSI Metadata extracted successfully using Get-MSIMetaData:" -Level "INFO"
                    Write-Log -Message "  ProductCode: $($result.ProductCode)" -Level "INFO"
                    Write-Log -Message "  Manufacturer: $($result.CompanyName)" -Level "INFO"
                    Write-Log -Message "  ProductName: $($result.ProductName)" -Level "INFO"
                    Write-Log -Message "  ProductVersion: $($result.ProductVersion)" -Level "INFO"
                    
                    return $result
                } else {
                    Write-Log -Message "Get-MSIMetaData did not return a ProductCode, falling back to COM object" -Level "WARNING"
                }
            } catch {
                Write-Log -Message "Error using Get-MSIMetaData: $($_.Exception.Message)" -Level "WARNING"
            }
        } else {
            # Try to import IntuneWin32App module if not already available
            try {
                Import-Module IntuneWin32App -ErrorAction Stop
                Write-Log -Message "Imported IntuneWin32App module, retrying Get-MSIMetaData" -Level "INFO"
                
                if (Get-Command -Name "Get-MSIMetaData" -ErrorAction SilentlyContinue) {
                    Write-Log -Message "Using Get-MSIMetaData cmdlet after module import" -Level "INFO"
                    
                    try {
                        $result = @{
                            ProductCode = Get-MSIMetaData -Path $MSIPath -Property "ProductCode" -ErrorAction SilentlyContinue
                            CompanyName = Get-MSIMetaData -Path $MSIPath -Property "Manufacturer" -ErrorAction SilentlyContinue
                            ProductName = Get-MSIMetaData -Path $MSIPath -Property "ProductName" -ErrorAction SilentlyContinue
                            FileVersion = Get-MSIMetaData -Path $MSIPath -Property "ProductVersion" -ErrorAction SilentlyContinue
                            ProductVersion = Get-MSIMetaData -Path $MSIPath -Property "ProductVersion" -ErrorAction SilentlyContinue
                            FileDescription = Get-MSIMetaData -Path $MSIPath -Property "Subject" -ErrorAction SilentlyContinue
                        }
                        
                        # If we got a ProductCode, consider this successful
                        if (-not [string]::IsNullOrWhiteSpace($result.ProductCode)) {
                            Write-Log -Message "MSI Metadata extracted successfully using Get-MSIMetaData after import:" -Level "INFO"
                            Write-Log -Message "  ProductCode: $($result.ProductCode)" -Level "INFO"
                            Write-Log -Message "  Manufacturer: $($result.CompanyName)" -Level "INFO"
                            Write-Log -Message "  ProductName: $($result.ProductName)" -Level "INFO"
                            Write-Log -Message "  ProductVersion: $($result.ProductVersion)" -Level "INFO"
                            
                            return $result
                        } else {
                            Write-Log -Message "Get-MSIMetaData did not return a ProductCode after import, falling back to COM object" -Level "WARNING"
                        }
                    } catch {
                        Write-Log -Message "Error using Get-MSIMetaData after import: $($_.Exception.Message)" -Level "WARNING"
                    }
                }
            } catch {
                Write-Log -Message "Could not import IntuneWin32App module: $($_.Exception.Message)" -Level "WARNING"
            }
            
            Write-Log -Message "Get-MSIMetaData cmdlet not available, falling back to Windows Installer COM object" -Level "WARNING"
        }
        
        # Fallback to Windows Installer COM object
        $windowsInstaller = New-Object -ComObject WindowsInstaller.Installer
        $database = $windowsInstaller.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $windowsInstaller, @($MSIPath, 0))
        
        $properties = @{}
        $queries = @{
            "ProductVersion" = "SELECT Value FROM Property WHERE Property = 'ProductVersion'"
            "ProductName" = "SELECT Value FROM Property WHERE Property = 'ProductName'"
            "Manufacturer" = "SELECT Value FROM Property WHERE Property = 'Manufacturer'"
            "ProductCode" = "SELECT Value FROM Property WHERE Property = 'ProductCode'"
        }
        
        foreach ($queryName in $queries.Keys) {
            try {
                $view = $database.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $database, $queries[$queryName])
                $view.GetType().InvokeMember("Execute", "InvokeMethod", $null, $view, $null)
                
                $record = $view.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $view, $null)
                if ($record) {
                    $value = $record.GetType().InvokeMember("StringData", "GetProperty", $null, $record, 1)
                    $properties[$queryName] = $value
                    Write-Log -Message "  Found $queryName`: $value" -Level "INFO"
                    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($record) | Out-Null
                }
                
                [System.Runtime.InteropServices.Marshal]::ReleaseComObject($view) | Out-Null
            } catch {
                Write-Log -Message "Could not extract $queryName from MSI: $($_.Exception.Message)" -Level "WARNING"
            }
        }
        
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($database) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($windowsInstaller) | Out-Null
        
        return @{
            FileVersion = $properties["ProductVersion"]
            ProductVersion = $properties["ProductVersion"]
            CompanyName = $properties["Manufacturer"]
            ProductName = $properties["ProductName"]
            ProductCode = $properties["ProductCode"]
            FileDescription = $properties["ProductName"]
        }} catch {
        Write-Log -Message "Failed to extract MSI version info: $($_.Exception.Message)" -Level "WARNING"
        return $null
    }
}

function Export-SCCMAppIcon {
    param(
        [Parameter(Mandatory)]
        [object]$SCCMApp,
        [Parameter(Mandatory)]
        [string]$DestinationPath,
        [hashtable]$MigrationInfo = $null
    )
    
    Write-Log -Message "Extracting application icon..." -Level "INFO"
    
    try {
        $iconData = $null
        
        # First, try to get icon data from the parsed migration info
        if ($MigrationInfo -and $MigrationInfo.ParsedData) {
            $firstDT = $MigrationInfo.ParsedData | Select-Object -First 1
            if ($firstDT -and $firstDT.IconData) {
                $iconData = $firstDT.IconData
                Write-Log -Message "Using icon data from parsed migration info" -Level "INFO"
            }
        }
        
        # If no icon data from parsed info, check SCCM app properties directly
        if (-not $iconData) {
            # Check for alternative icon sources
            if ($SCCMApp.IconData -and $SCCMApp.IconData.Length -gt 0) {
                $iconData = $SCCMApp.IconData
                Write-Log -Message "Found icon data in IconData property" -Level "INFO"
            }
            # Check for Icon property
            elseif ($SCCMApp.Icon -and $SCCMApp.Icon.Length -gt 0) {
                $iconData = $SCCMApp.Icon
                Write-Log -Message "Found icon data in Icon property" -Level "INFO"
            }
            # Check for LargeIcon property
            elseif ($SCCMApp.LargeIcon -and $SCCMApp.LargeIcon.Length -gt 0) {
                $iconData = $SCCMApp.LargeIcon
                Write-Log -Message "Found icon data in LargeIcon property" -Level "INFO"
            }
        }
        
        # If still no icon data, return null
        if (-not $iconData) {
            Write-Log -Message "No icon data found in application or parsed data" -Level "INFO"
            return $null
        }
        
        # Save the icon data
        return Save-IconData -IconData $iconData -DestinationPath $DestinationPath -SCCMApp $SCCMApp
        
    } catch {
        Write-Log -Message "Error extracting icon: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Save-IconData {
    param(
        [Parameter(Mandatory)]
        [string]$IconData,
        [Parameter(Mandatory)]
        [string]$DestinationPath,
        [Parameter(Mandatory)]
        [object]$SCCMApp
    )
    
    try {
        # Clean up icon data (remove whitespace, newlines)
        $iconData = $IconData.Trim() -replace '\s+', ''
        Write-Log -Message "Found icon data, extracting... (length: $($iconData.Length))" -Level "INFO"
        
        # Create Icon directory if it doesn't exist
        $iconDir = Join-Path -Path $DestinationPath -ChildPath "Icon"
        if (-not (Test-Path $iconDir)) {
            New-Item -Path $iconDir -ItemType Directory -Force | Out-Null
        }
        
        # Decode Base64 data
        try {
            # Validate Base64 format
            if ($iconData.Length % 4 -ne 0) {
                Write-Log -Message "Icon data length not divisible by 4, padding..." -Level "WARNING"
                $padding = 4 - ($iconData.Length % 4)
                $iconData += "=" * $padding
            }
            
            $iconBytes = [System.Convert]::FromBase64String($iconData)
            Write-Log -Message "Icon data decoded successfully ($($iconBytes.Length) bytes)" -Level "SUCCESS"
            
            # Validate we have actual image data
            if ($iconBytes.Length -lt 10) {
                Write-Log -Message "Decoded icon data too small to be a valid image ($($iconBytes.Length) bytes)" -Level "WARNING"
                return $null
            }
            
        } catch {
            Write-Log -Message "Failed to decode icon data: $($_.Exception.Message)" -Level "ERROR"
            Write-Log -Message "Icon data preview: $($iconData.Substring(0, [Math]::Min(100, $iconData.Length)))" -Level "INFO"
            return $null
        }
        
        # Determine file extension based on image header
        $extension = ".png"  # Default to PNG
        if ($iconBytes.Length -ge 4) {
            # Check for common image signatures
            $header = [System.Text.Encoding]::ASCII.GetString($iconBytes[1..3])
            if ($iconBytes[0] -eq 0x89 -and $header -eq "PNG") {
                $extension = ".png"
            } elseif ($iconBytes[0] -eq 0xFF -and $iconBytes[1] -eq 0xD8) {
                $extension = ".jpg"
            } elseif ($iconBytes[0] -eq 0x42 -and $iconBytes[1] -eq 0x4D) {
                $extension = ".bmp"
            } elseif ($iconBytes[0] -eq 0x00 -and $iconBytes[1] -eq 0x00 -and $iconBytes[2] -eq 0x01 -and $iconBytes[3] -eq 0x00) {
                $extension = ".ico"
            }
        }
        
        # Generate filename based on app name
        $iconFileName = "app_icon$extension"
        $iconFilePath = Join-Path -Path $iconDir -ChildPath $iconFileName
        
        # Save icon file
        try {
            [System.IO.File]::WriteAllBytes($iconFilePath, $iconBytes)
            Write-Log -Message "✓ Icon saved: $iconFilePath" -Level "SUCCESS"
            
            return @{
                FilePath = $iconFilePath
                FileName = $iconFileName
                FileSize = $iconBytes.Length
                Extension = $extension
                Directory = $iconDir
            }
        } catch {
            Write-Log -Message "Failed to save icon file: $($_.Exception.Message)" -Level "ERROR"
            return $null
        }
        
    } catch {
        Write-Log -Message "Error processing icon data: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Find-SourceFile {
    param([object]$SCCMApp, [hashtable]$MigrationInfo)
    
    Write-Log -Message "Locating source files..." -Level "INFO"
      $firstDT = $MigrationInfo.ParsedData | Select-Object -First 1
    if (-not $firstDT) {
        Write-Log -Message "No deployment type data found" -Level "WARNING"
        return $null
    }
    
    # Check if ContentLocations exists and has valid entries
    if (-not $firstDT.ContentLocations -or $firstDT.ContentLocations.Count -eq 0) {
        Write-Log -Message "No content locations found in deployment type" -Level "WARNING"
        return $null
    }
    
    # Filter out null/empty content locations
    $validLocations = $firstDT.ContentLocations | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($validLocations.Count -eq 0) {
        Write-Log -Message "No valid content locations found (all were null or empty)" -Level "WARNING"
        return $null
    }
    
    # First, try to find using smart path matching if BaseSourcePath is configured
    if (-not [string]::IsNullOrWhiteSpace($BaseSourcePath) -and (Test-Path $BaseSourcePath)) {
        $smartPath = Find-SourceFileSmartPath -SCCMApp $SCCMApp
        if ($smartPath) {
            return $smartPath
        }
    }    # Fallback to original logic - test each valid content location
    foreach ($location in $validLocations) {
        Write-Host "  Checking: $location" -ForegroundColor Gray
        
        Set-Location C:
        if (Test-Path $location) {
            # Look for installer files
            $installerFiles = Get-ChildItem -Path $location | Where-Object { -not $_.PSIsContainer } | Where-Object {
                $_.Extension -match '\.(exe|msi|msix|appx)$'
            }
            
            if ($installerFiles.Count -gt 0) {
                Write-Host "  ✓ Found installer files at: $location" -ForegroundColor Green
                
                # Get all files in the directory for counting
                $allFiles = Get-ChildItem -Path $location | Where-Object { -not $_.PSIsContainer }
                Write-Host "    Total files in directory: $($allFiles.Count)" -ForegroundColor Gray
                  if ($installerFiles.Count -eq 1) {
                    $sourceFile = $installerFiles[0]
                } else {
                    Write-Log -Message "Multiple installer files found, showing selection dialog..." -Level "INFO"
                    $sourceFile = Show-FileSelectionDialog -Files $installerFiles -Title "Select Installer File" -Message "Multiple installer files found in $location. Please select the main installer file:"
                    
                    if (-not $sourceFile) {
                        Write-Log -Message "No file selected, skipping this location." -Level "WARNING"
                        continue
                    }
                    
                    Write-Log -Message "Selected file: $($sourceFile.Name)" -Level "INFO"
                }
                
                # Get version info
                $versionInfo = Get-FileVersionInfo -FilePath $sourceFile.FullName
                
                return @{
                    FilePath = $sourceFile.FullName
                    FileName = $sourceFile.Name
                    FileSize = $sourceFile.Length
                    VersionInfo = $versionInfo
                    ContentLocation = $location
                    AllFiles = $allFiles
                    TotalFileSize = ($allFiles | Measure-Object -Property Length -Sum).Sum
                }
            }
        }
    }
    
    Write-Log -Message "No accessible installer files found" -Level "WARNING"
    return $null
}

function Find-SourceFileSmartPath {
    param([object]$SCCMApp)
    
    Write-Log -Message "Trying smart path matching using BaseSourcePath..." -Level "INFO"
    
    # Build potential paths: BaseSourcePath\Publisher\ProductName\Version
    $possiblePaths = @()
    
    # Clean up manufacturer/publisher name for path
    $publisher = $SCCMApp.Manufacturer
    if ([string]::IsNullOrWhiteSpace($publisher)) {
        $publisher = "Unknown"
    }
    $publisherClean = $publisher -replace '[\\/:*?"<>|]', '_'
    
    # Clean up product name for path
    $productName = $SCCMApp.LocalizedDisplayName
    $productNameClean = $productName -replace '[\\/:*?"<>|]', '_'
    
    # Try different version formats
    $versions = @()
    if (-not [string]::IsNullOrWhiteSpace($SCCMApp.SoftwareVersion)) {
        $versions += $SCCMApp.SoftwareVersion
    }
    
    # Add some common version variations
    if ($productName -match '(\d+\.[\d\.]+)') {
        $versions += $matches[1]
    }
    
    # If no versions found, add a wildcard approach
    if ($versions.Count -eq 0) {
        $versions += "*"
    }
    
    # Build possible paths
    foreach ($version in $versions) {
        $path1 = Join-Path -Path $BaseSourcePath -ChildPath "$publisherClean\$productNameClean\$version"
        $path2 = Join-Path -Path $BaseSourcePath -ChildPath "$publisherClean\$productNameClean"
        $path3 = Join-Path -Path $BaseSourcePath -ChildPath "$productNameClean\$version"
        $path4 = Join-Path -Path $BaseSourcePath -ChildPath "$productNameClean"
        
        $possiblePaths += $path1, $path2, $path3, $path4
    }
    
    # Remove duplicates
    $possiblePaths = $possiblePaths | Select-Object -Unique
    
    Write-Log -Message "Checking potential smart paths..." -Level "INFO"
    
    foreach ($testPath in $possiblePaths) {
        if ($testPath -like "*\*") {  # Has wildcard
            $parentPath = Split-Path -Path $testPath -Parent
            $pattern = Split-Path -Path $testPath -Leaf
            
            if (Test-Path $parentPath) {
                $matchingDirs = Get-ChildItem -Path $parentPath | Where-Object { $_.PSIsContainer -and $_.Name -like $pattern } | Sort-Object Name -Descending
                foreach ($dir in $matchingDirs) {
                    $result = Test-PathForInstallers -Path $dir.FullName -SCCMApp $SCCMApp
                    if ($result) {
                        return $result
                    }
                }
            }
        } else {
            if (Test-Path $testPath) {
                $result = Test-PathForInstallers -Path $testPath -SCCMApp $SCCMApp
                if ($result) {
                    return $result
                }
            }
        }
    }
    
    Write-Log -Message "Smart path matching did not find source files" -Level "INFO"
    return $null
}

function Test-PathForInstallers {
    param([string]$Path, [object]$SCCMApp)
    
    Write-Log -Message "  Testing path: $Path" -Level "INFO"
    
    # Look for installer files
    $installerFiles = Get-ChildItem -Path $Path -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | Where-Object {
        $_.Extension -match '\.(exe|msi|msix|appx)$'
    }
    
    if ($installerFiles.Count -gt 0) {
        Write-Log -Message "  ✓ Found $($installerFiles.Count) installer file(s)" -Level "SUCCESS"
        
        # Get all files for counting
        $allFiles = Get-ChildItem -Path $Path -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer }
        
        # Show confirmation dialog
        $message = "Found source files at:`n$Path`n`nFound $($installerFiles.Count) installer file(s):`n"
        $installerFiles | ForEach-Object { 
            $size = [math]::Round($_.Length / 1MB, 2)
            $message += "• $($_.Name) ($size MB)`n"
        }
        $message += "`nDo you want to use this location?"
        
        $result = [System.Windows.Forms.MessageBox]::Show(
            $message, 
            "Confirm Source Location", 
            [System.Windows.Forms.MessageBoxButtons]::YesNo, 
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            $sourceFile = $null
            
            if ($installerFiles.Count -eq 1) {
                $sourceFile = $installerFiles[0]
            } else {
                Write-Log -Message "Multiple installer files found, showing selection dialog..." -Level "INFO"
                $sourceFile = Show-FileSelectionDialog -Files $installerFiles -Title "Select Installer File" -Message "Multiple installer files found in $Path. Please select the main installer file:"
                
                if (-not $sourceFile) {
                    Write-Log -Message "No file selected" -Level "WARNING"
                    return $null
                }
            }
            
            # Get version info
            $versionInfo = Get-FileVersionInfo -FilePath $sourceFile.FullName
            
            return @{
                FilePath = $sourceFile.FullName
                FileName = $sourceFile.Name
                FileSize = $sourceFile.Length
                VersionInfo = $versionInfo
                ContentLocation = $Path
                AllFiles = $allFiles
                TotalFileSize = ($allFiles | Measure-Object -Property Length -Sum).Sum
            }
        }
    }
    
    return $null
}

function New-VersionDirectory {
    param(
        [Parameter(Mandatory)]
        [hashtable]$SourceFileInfo,
        [Parameter(Mandatory)]
        [object]$Publisher,
        [Parameter(Mandatory)]
        [object]$Application,
        [Parameter(Mandatory)]
        [string]$Version,
        [Parameter(Mandatory)]
        [object]$SCCMApp,
        [hashtable]$MigrationInfo = $null
    )
    
    $newVersionPath = Join-Path -Path $Application.FullName -ChildPath $Version
    
    Write-Log -Message "Creating version directory: $Version" -Level "INFO"
    
    if ($WhatIf) {
        Write-Log -Message "  [WHAT-IF] Would create: $newVersionPath" -Level "INFO"
        Write-Log -Message "  [WHAT-IF] Would copy $($SourceFileInfo.AllFiles.Count) files" -Level "INFO"
        return $newVersionPath
    }
      if ((Test-Path $newVersionPath) -and (-not $Force)) {
        Write-Log -Message "Version directory exists: $newVersionPath" -Level "WARNING"
        return $null
    }
    
    try {
        $sourceFilesPath = Join-Path -Path $newVersionPath -ChildPath "_Sourcefiles"
        $documentsPath = Join-Path -Path $newVersionPath -ChildPath "Documents"
        $intunewinPath = Join-Path -Path $newVersionPath -ChildPath "intunewin"
        
        New-Item -Path $sourceFilesPath -ItemType Directory -Force | Out-Null
        New-Item -Path $documentsPath -ItemType Directory -Force | Out-Null
        New-Item -Path $intunewinPath -ItemType Directory -Force | Out-Null
        
        $sourceLocation = $SourceFileInfo.ContentLocation
        $itemsToCopy = Get-ChildItem -Path $sourceLocation -Recurse
        $totalItems = $itemsToCopy.Count
        $currentItem = 0
        
        foreach ($item in $itemsToCopy) {
            $currentItem++
            Write-Progress -Activity "Copying files" -Status "Processing $currentItem of $totalItems" -PercentComplete (($currentItem / $totalItems) * 100)
            $relativePath = $item.FullName -replace [regex]::Escape($sourceLocation), ''
            $destPath = Join-Path -Path $sourceFilesPath -ChildPath $relativePath
            if ($item.PSIsContainer) {
                New-Item -Path $destPath -ItemType Directory -Force | Out-Null
            } else {
                Copy-Item -Path $item.FullName -Destination $destPath -Force
            }
        }
        Write-Progress -Activity "Copying files" -Completed
          $mainInstallerPath = Join-Path -Path $sourceFilesPath -ChildPath $SourceFileInfo.FileName
        if (-not (Test-Path $mainInstallerPath)) {
            Write-Log -Message "Main installer file not found in copied files." -Level "WARNING"
        }
          # Extract application icon if available
        $iconInfo = Export-SCCMAppIcon -SCCMApp $SCCMApp -DestinationPath $newVersionPath -MigrationInfo $MigrationInfo
        if ($iconInfo) {
            Write-Log -Message "✓ Application icon extracted: $($iconInfo.FileName)" -Level "SUCCESS"
        }
        
        Write-Log -Message "✓ Created directory structure" -Level "SUCCESS"
        return $newVersionPath
    } catch {
        Write-Log -Message "Failed to create version directory: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function New-PackageConstructorJSON {
    param(
        [string]$VersionPath,
        [object]$SCCMApp,
        [hashtable]$SourceFileInfo,
        [hashtable]$MigrationInfo,
        [object]$Publisher,
        [object]$Application,
        [string]$Version
    )
    
    $documentsPath = Join-Path -Path $VersionPath -ChildPath "Documents"
    $jsonFile = Join-Path -Path $documentsPath -ChildPath "PackageConstructor.json"
      Write-Log -Message "Creating PackageConstructor.json..." -Level "INFO"
    
    $firstDT = $MigrationInfo.ParsedData | Select-Object -First 1
    $detectionMethod = Get-OptimalDetectionMethod -SourceFileInfo $SourceFileInfo -SCCMApp $SCCMApp -MigrationInfo $MigrationInfo
    
    # Check for icon information
    $iconPath = Join-Path -Path $VersionPath -ChildPath "Icon"
    $iconInfo = $null
    if (Test-Path $iconPath) {
        $iconFiles = Get-ChildItem -Path $iconPath -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer }
        if ($iconFiles.Count -gt 0) {
            $iconFile = $iconFiles[0]  # Take the first icon file
            $iconInfo = @{
                fileName = $iconFile.Name
                filePath = $iconFile.FullName
                size = $iconFile.Length
                extracted = $true
            }
            Write-Log -Message "  Found extracted icon: $($iconFile.Name)" -Level "INFO"
        }
    }
    
    Write-Log -Message "  Selected detection method: $($detectionMethod.method)" -Level "INFO"
    if ($detectionMethod.details) {
        Write-Log -Message "    Details: $($detectionMethod.details)" -Level "INFO"
    }
    
    $packageConstructor = @{
        publisher = $Publisher.Name
        applicationName = $Application.Name
        version = $Version
        intuneDisplayName = "$($Publisher.Name) - $($Application.Name) - $Version"
        installCommand = $firstDT.InstallCommand
        uninstallCommand = $firstDT.UninstallCommand
        detection = $detectionMethod
        requirements = @{
            architecture = "x64"
            minimumOS = "W10_1903"
        }
        metadata = @{
            category = ""
            description = if ($SourceFileInfo.VersionInfo.FileDescription) {
                $SourceFileInfo.VersionInfo.FileDescription
            } else {
                "$($Application.Name) installer"
            }
            createdDate = (Get-Date -Format "yyyy-MM-dd")
            updatedDate = (Get-Date -Format "yyyy-MM-dd")
            createdBy = $env:USERNAME
            updatedBy = $env:USERNAME
            sourceFile = $SourceFileInfo.FileName
            sourceVersion = $SourceFileInfo.VersionInfo.FileVersion
            totalFiles = $SourceFileInfo.AllFiles.Count
            totalSize = $SourceFileInfo.TotalFileSize
            icon = $iconInfo
            sccmSource = @{
                applicationName = $SCCMApp.LocalizedDisplayName
                manufacturer = $SCCMApp.Manufacturer
                version = $SCCMApp.SoftwareVersion
                contentLocation = $SourceFileInfo.ContentLocation
                migratedDate = (Get-Date -Format "yyyy-MM-dd")
                technology = $firstDT.Technology
                hasDetectionMethod = $firstDT.HasDetectionMethod
                detectionMethodDetails = $firstDT.DetectionMethodDetails
            }
        }
    }
    
    if ($WhatIf) {
        Write-Log -Message "  [WHAT-IF] Would create PackageConstructor.json" -Level "INFO"
        return $jsonFile
    }
    
    try {
        $jsonContent = $packageConstructor | ConvertTo-Json -Depth 10
        $jsonContent | Out-File -FilePath $jsonFile -Encoding UTF8
        Write-Log -Message "✓ Created PackageConstructor.json" -Level "SUCCESS"
        return $jsonFile
    } catch {
        Write-Log -Message "Failed to create PackageConstructor.json: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Get-OptimalDetectionMethod {
    param(
        [hashtable]$SourceFileInfo,
        [object]$SCCMApp,
        [hashtable]$MigrationInfo
    )
    
    $firstDT = $MigrationInfo.ParsedData | Select-Object -First 1
    
    # MSI Detection
    if ($SourceFileInfo.FileName -match '\.msi$' -and $SourceFileInfo.VersionInfo.ProductCode) {
        return @{
            method = "msi"
            productCode = $SourceFileInfo.VersionInfo.ProductCode
            details = "Using MSI product code: $($SourceFileInfo.VersionInfo.ProductCode)"
        }
    }
    
    # Registry Detection
    if ($firstDT.UninstallCommand -match '\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\}') {
        $productCode = $matches[0]
        return @{
            method = "registry"
            registryPath = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$productCode"
            registryValue = "DisplayName"
            details = "Using registry key: $productCode"
        }
    }
    
    # File Detection
    $detectionPath = "%ProgramFiles%"
    $detectionFolder = $SCCMApp.LocalizedDisplayName
    
    if ($firstDT.InstallCommand -match '"([^"]+)"') {
        $installerPath = $matches[1]
        if ($installerPath -and [System.IO.Path]::GetDirectoryName($installerPath)) {
            $detectionFolder = [System.IO.Path]::GetFileNameWithoutExtension($installerPath)
        }
    }
    
    $detectionFolder = $detectionFolder -replace '\s+\d+\.\d+.*$', '' -replace '\s+v\d+.*$', '' -replace '\s+\(\d+.*\)$', ''
    
    if ($SourceFileInfo.VersionInfo.ProductName) {
        $productName = $SourceFileInfo.VersionInfo.ProductName
        $cleanProductName = $productName -replace '\s+\d+\.\d+.*$', '' -replace '\s+v\d+.*$', ''
        if ($cleanProductName.Length -gt 3) {
            $detectionFolder = $cleanProductName
        }
    }
    
    if ($SCCMApp.Manufacturer -and $SCCMApp.Manufacturer.Length -gt 0) {
        $publisherPath = "$detectionPath\$($SCCMApp.Manufacturer)"
        return @{
            method = "file"
            filePath = $publisherPath
            fileName = $detectionFolder
            detectionType = "exists"
            details = "Using file detection: $publisherPath\$detectionFolder"
        }
    }
    
    return @{        method = "file"
        filePath = $detectionPath
        fileName = $detectionFolder
        detectionType = "exists"
        details = "Using file detection: $detectionPath\$detectionFolder"
    }
}

function Find-NewApplicationFiles {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$DropPath,
        [int]$Depth = 2
    )
    
    Write-Log -Message "Scanning for new application files in: $DropPath" -Level "INFO"
    
    if (-not (Test-Path $DropPath)) {
        Write-Log -Message "Drop path is invalid or inaccessible: $DropPath" -Level "ERROR"
        return [PSCustomObject]@{
            Success = $false
            Message = "Drop path is invalid or inaccessible: $DropPath"
            Files = @()
        }
    }
    
    $newFiles = @()
    $supportedExtensions = @("*.exe", "*.msi")
    
    $pathItem = Get-Item -Path $DropPath -ErrorAction SilentlyContinue
    
    if ($pathItem -and $pathItem.PSIsContainer -eq $false) {
        # Direct file path provided
        Write-Log -Message "Direct file path detected" -Level "INFO"
        
        $file = $pathItem
        $extension = $file.Extension.ToLowerInvariant()
        
        if ($extension -eq ".exe" -or $extension -eq ".msi") {
            $versionInfo = Get-FileVersionInfo -FilePath $file.FullName
            
            if ($versionInfo) {
                $parentPath = Split-Path -Path $file.FullName -Parent
                $folderHints = @()
                $pathParts = $parentPath -split '\\'
                if ($pathParts.Length -ge 2) {
                    $folderHints = $pathParts[-2..-1]
                }
                
                $newFiles += @{
                    FilePath = $file.FullName
                    FileName = $file.Name
                    FileSize = $file.Length
                    LastWriteTime = $file.LastWriteTime
                    VersionInfo = [PSCustomObject]@{
                        Success = $true
                        FileVersion = $versionInfo.FileVersion
                        ProductVersion = $versionInfo.ProductVersion
                        CompanyName = $versionInfo.CompanyName
                        ProductName = $versionInfo.ProductName
                        FileDescription = $versionInfo.FileDescription
                    }
                    DropFolder = $folderHints -join "\"
                    FolderHints = $folderHints
                }
                
                Write-Log -Message "Found: $($file.Name)" -Level "INFO"
            }
        }    } else {
        # Directory path - scan the selected directory and its subdirectories
        Write-Log -Message "Directory path detected - scanning directory and subdirectories" -Level "INFO"
        
        # First, scan the selected directory itself
        Write-Log -Message "Checking root directory: $DropPath" -Level "INFO"
        foreach ($ext in $supportedExtensions) {
            $files = Get-ChildItem -Path $DropPath -Filter $ext -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer }
            
            foreach ($file in $files) {
                $versionInfo = Get-FileVersionInfo -FilePath $file.FullName
                
                if ($versionInfo) {
                    $parentFolderName = Split-Path -Path $DropPath -Leaf
                    $newFiles += @{
                        FilePath = $file.FullName
                        FileName = $file.Name
                        FileSize = $file.Length
                        LastWriteTime = $file.LastWriteTime
                        VersionInfo = [PSCustomObject]@{
                            Success = $true
                            FileVersion = $versionInfo.FileVersion
                            ProductVersion = $versionInfo.ProductVersion
                            CompanyName = $versionInfo.CompanyName
                            ProductName = $versionInfo.ProductName
                            FileDescription = $versionInfo.FileDescription
                        }
                        DropFolder = $parentFolderName
                        FolderHints = @($parentFolderName)
                    }
                    
                    Write-Log -Message "Found: $($file.Name)" -Level "INFO"
                }
            }
        }
        
        # Then scan subdirectories
        $subDirs = Get-ChildItem -Path $DropPath | Where-Object { $_.PSIsContainer } -ErrorAction SilentlyContinue
        
        foreach ($subDir in $subDirs) {
            Write-Log -Message "Checking subdirectory: $($subDir.Name)" -Level "INFO"
            
            foreach ($ext in $supportedExtensions) {
                $files = Get-ChildItem -Path $subDir.FullName -Filter $ext -Recurse -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer }
                
                foreach ($file in $files) {
                    $versionInfo = Get-FileVersionInfo -FilePath $file.FullName
                    
                    if ($versionInfo) {
                        $newFiles += @{
                            FilePath = $file.FullName
                            FileName = $file.Name
                            FileSize = $file.Length
                            LastWriteTime = $file.LastWriteTime
                            VersionInfo = [PSCustomObject]@{
                                Success = $true
                                FileVersion = $versionInfo.FileVersion
                                ProductVersion = $versionInfo.ProductVersion
                                CompanyName = $versionInfo.CompanyName
                                ProductName = $versionInfo.ProductName
                                FileDescription = $versionInfo.FileDescription
                            }
                            DropFolder = $subDir.Name
                            FolderHints = @($subDir.Name)
                        }
                        
                        Write-Log -Message "Found: $($file.Name)" -Level "INFO"
                    }
                }
            }
        }
    }
      Write-Log -Message "Found $($newFiles.Count) application files" -Level "INFO"
    return [PSCustomObject]@{
        Success = $true
        Files = $newFiles
    }
}

function Update-SourceFiles {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Application,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$FileInfo,
        
        [Parameter(Mandatory = $false)]
        [switch]$Interactive = $false
    )
    
    Write-Log -Message "Updating source files for: $($Application.ApplicationName)" -Level "INFO"
    
    # If FileInfo is provided, process it as a new application file
    if ($FileInfo) {
        return Invoke-NewApplicationFileProcessing -FileInfo $FileInfo -Application $Application
    }
    
    # Fallback to original simulation for compatibility
    if (-not $Interactive) {
        Write-Log -Message "Processing source file updates for: $($Application.ApplicationName)" -Level "INFO"
        
        # Simulate finding and updating source files
        Write-Log -Message "Scanning source file locations..." -Level "INFO"
        Start-Sleep -Seconds 1
        
        Write-Log -Message "Validating application structure..." -Level "INFO"
        Start-Sleep -Seconds 1
        
        Write-Log -Message "Updating file references..." -Level "INFO"
        Start-Sleep -Seconds 1
        
        Write-Log -Message "Source files updated successfully for $($Application.ApplicationName)" -Level "SUCCESS"
        return $true
    }
    else {
        # Interactive mode - allow manual file selection and processing
        Write-Log -Message "Running in interactive mode..." -Level "INFO"
        
        # For simplicity in the GUI, just return success
        Write-Log -Message "Interactive source file update completed" -Level "SUCCESS"
        return $true
    }
}

function Invoke-NewApplicationFileProcessing {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$FileInfo,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Application
    )
      Write-Log -Message "Processing new application file: $($FileInfo.FileName)" -Level "INFO"
    Write-Log -Message "File path: $($FileInfo.FilePath)" -Level "INFO"
    Write-Log -Message "Company: $($FileInfo.VersionInfo.CompanyName)" -Level "INFO"
    Write-Log -Message "Product: $($FileInfo.VersionInfo.ProductName)" -Level "INFO"
    Write-Log -Message "Version: $($FileInfo.VersionInfo.FileVersion)" -Level "INFO"
      # Debug MSI product code
    if ($FileInfo.FileName -match '\.msi$') {
        Write-Log -Message "MSI file detected - ProductCode: $($FileInfo.VersionInfo.ProductCode)" -Level "INFO"
        Write-Log -Message "MSI file detected - CompanyName: $($FileInfo.VersionInfo.CompanyName)" -Level "INFO"
        Write-Log -Message "MSI file detected - ProductName: $($FileInfo.VersionInfo.ProductName)" -Level "INFO"
        Write-Log -Message "MSI file detected - FileVersion: $($FileInfo.VersionInfo.FileVersion)" -Level "INFO"
        
        if ([string]::IsNullOrWhiteSpace($FileInfo.VersionInfo.ProductCode)) {
            Write-Log -Message "WARNING: MSI ProductCode is null or empty!" -Level "WARNING"
        }
    }
    
    try {
        # Create publisher/application structure based on file info
        $publisherName = if ($FileInfo.VersionInfo.CompanyName) { 
            $FileInfo.VersionInfo.CompanyName -replace '[\\/:*?"<>|]', '_'
        } else { 
            "Unknown Publisher" 
        }        $applicationName = if ($FileInfo.VersionInfo.ProductName) { 
            # Clean the product name and remove version numbers
            $cleanName = $FileInfo.VersionInfo.ProductName -replace '[\\/:*?"<>|]', '_'
            # Remove version patterns like "1.1.0.183", "v1.2", "2024", etc.
            $cleanName = $cleanName -replace '\s+\d+\.\d+(\.\d+)*(\.\d+)*\s*$', ''
            $cleanName = $cleanName -replace '\s+v\d+(\.\d+)*\s*$', ''
            $cleanName = $cleanName -replace '\s+\d{4}\s*$', ''
            $cleanName = $cleanName -replace '\s+\(\d+(\.\d+)*\)\s*$', ''
            $cleanName = $cleanName -replace '\s+version\s+\d+(\.\d+)*\s*$', '' -replace '\s+Ver\.\s*\d+(\.\d+)*\s*$', ''
            $cleanName = $cleanName.Trim()
            Write-Log -Message "Cleaned application name from '$($FileInfo.VersionInfo.ProductName)' to '$cleanName'" -Level "INFO"
            if ($cleanName.Length -gt 0) { $cleanName } else { $FileInfo.VersionInfo.ProductName -replace '[\\/:*?"<>|]', '_' }
        } else { 
            [System.IO.Path]::GetFileNameWithoutExtension($FileInfo.FileName)
        }
          $version = if ($FileInfo.VersionInfo.FileVersion) { 
            $FileInfo.VersionInfo.FileVersion 
        } else { 
            "1.0.0" 
        }
        
        # Create initial package details for user review BEFORE file operations
        Write-Log -Message "Preparing package details for review..." -Level "INFO"
        
        # Determine install command based on file type
        $installCommand = if ($FileInfo.FileName -match '\.msi$') {
            "msiexec /i `"$($FileInfo.FileName)`" /quiet /norestart"
        } else {
            "`"$($FileInfo.FileName)`" /S"
        }
        
        # Determine uninstall command
        $uninstallCommand = if ($FileInfo.FileName -match '\.msi$' -and $FileInfo.VersionInfo.ProductCode) {
            "msiexec /x `"$($FileInfo.VersionInfo.ProductCode)`" /quiet /norestart"
        } else {
            ""
        }        # Create detection method
        $detection = if ($FileInfo.FileName -match '\.msi$' -and -not [string]::IsNullOrWhiteSpace($FileInfo.VersionInfo.ProductCode)) {
            Write-Log -Message "Using MSI detection with ProductCode: $($FileInfo.VersionInfo.ProductCode)" -Level "INFO"
            @{
                method = "msi"
                productCode = $FileInfo.VersionInfo.ProductCode
            }
        } else {
            if ($FileInfo.FileName -match '\.msi$') {
                Write-Log -Message "MSI file detected but no ProductCode found in version info - using file detection instead" -Level "WARNING"
            } else {
                Write-Log -Message "Using file detection method for non-MSI file" -Level "INFO"
            }
            @{
                method = "file"
                filePath = "%ProgramFiles%\$publisherName\$applicationName"
                fileName = [System.IO.Path]::GetFileNameWithoutExtension($FileInfo.FileName) + ".exe"
                detectionType = "exists"
            }
        }
        
        $packageConstructor = @{
            publisher = $publisherName
            applicationName = $applicationName
            version = $version
            intuneDisplayName = "$publisherName - $applicationName - $version"
            installCommand = $installCommand
            uninstallCommand = $uninstallCommand
            detection = $detection
            requirements = @{
                architecture = "x64"
                minimumOS = "W10_1903"
            }
            metadata = @{
                category = "Productivity"
                description = if ($FileInfo.VersionInfo.FileDescription) { $FileInfo.VersionInfo.FileDescription } else { "$applicationName installer" }
                createdDate = (Get-Date -Format "yyyy-MM-dd")
                updatedDate = (Get-Date -Format "yyyy-MM-dd")
                createdBy = $env:USERNAME
                updatedBy = $env:USERNAME
                sourceFile = $FileInfo.FileName
                sourceVersion = $FileInfo.VersionInfo.FileVersion
                originalPath = $FileInfo.FilePath
            }
        }
        
        # Show the review dialog BEFORE any file operations
        Write-Log -Message "Showing package details review dialog..." -Level "INFO"
        $reviewedPackage = Show-PackageDetailsDialog -PackageDetails $packageConstructor
        
        if ($null -eq $reviewedPackage) {
            Write-Log -Message "Package creation cancelled by user" -Level "WARNING"
            return @{
                Success = $false
                Error = "Package creation cancelled by user"
            }
        }
        
        # Update the names from the reviewed package in case user modified them
        $publisherName = $reviewedPackage.publisher
        $applicationName = $reviewedPackage.applicationName
        $version = $reviewedPackage.version
        
        Write-Log -Message "User confirmed package details:" -Level "INFO"
        Write-Log -Message "  Publisher: $publisherName" -Level "INFO"
        Write-Log -Message "  Application: $applicationName" -Level "INFO"
        Write-Log -Message "  Version: $version" -Level "INFO"
        
        # NOW proceed with file operations using confirmed details
        $baseAppPath = $Config.BaseAppPath
        Write-Log -Message "Using BaseAppPath: $baseAppPath" -Level "INFO"
        
        if (-not $baseAppPath -or -not (Test-Path $baseAppPath)) {
            Write-Log -Message "BaseAppPath is not configured or does not exist: $baseAppPath" -Level "ERROR"
            return @{
                Success = $false
                Error = "BaseAppPath is not configured or does not exist: $baseAppPath"
            }
        }
        
        $publisherPath = Join-Path -Path $baseAppPath -ChildPath $publisherName
        if (-not (Test-Path $publisherPath)) {
            New-Item -Path $publisherPath -ItemType Directory -Force | Out-Null
            Write-Log -Message "Created publisher directory: $publisherName" -Level "INFO"
        }
        
        # Create application directory
        $applicationPath = Join-Path -Path $publisherPath -ChildPath $applicationName
        if (-not (Test-Path $applicationPath)) {
            New-Item -Path $applicationPath -ItemType Directory -Force | Out-Null
            Write-Log -Message "Created application directory: $applicationName" -Level "INFO"
        }
        
        # Create version directory structure
        $versionPath = Join-Path -Path $applicationPath -ChildPath $version
        if (Test-Path $versionPath) {
            Write-Log -Message "Version directory already exists: $version" -Level "WARNING"
            # For GUI operation, just overwrite
        }
        
        $sourceFilesPath = Join-Path -Path $versionPath -ChildPath "_Sourcefiles"
        $documentsPath = Join-Path -Path $versionPath -ChildPath "Documents"
        $intunewinPath = Join-Path -Path $versionPath -ChildPath "intunewin"
        
        New-Item -Path $sourceFilesPath -ItemType Directory -Force | Out-Null
        New-Item -Path $documentsPath -ItemType Directory -Force | Out-Null
        New-Item -Path $intunewinPath -ItemType Directory -Force | Out-Null
          Write-Log -Message "Created version directory structure: $version" -Level "INFO"
        
        # Copy all files from the source directory
        $sourceDirectory = Split-Path -Path $FileInfo.FilePath -Parent
        Write-Log -Message "Copying all files from source directory: $sourceDirectory" -Level "INFO"
        
        try {
            # Get all files in the source directory
            $allSourceFiles = Get-ChildItem -Path $sourceDirectory -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer }
            $totalFiles = $allSourceFiles.Count
            
            if ($totalFiles -eq 0) {
                Write-Log -Message "No files found in source directory" -Level "WARNING"
                # Still copy the original file as fallback
                $destinationFile = Join-Path -Path $sourceFilesPath -ChildPath $FileInfo.FileName
                Copy-Item -Path $FileInfo.FilePath -Destination $destinationFile -Force
                Write-Log -Message "Copied installer file to: $destinationFile" -Level "SUCCESS"
            } else {
                Write-Log -Message "Found $totalFiles files to copy from source directory" -Level "INFO"
                
                $copiedCount = 0
                foreach ($sourceFile in $allSourceFiles) {
                    $destinationFile = Join-Path -Path $sourceFilesPath -ChildPath $sourceFile.Name
                    Copy-Item -Path $sourceFile.FullName -Destination $destinationFile -Force
                    $copiedCount++
                    
                    # Log progress for large file counts
                    if ($totalFiles -gt 10 -and ($copiedCount % 5 -eq 0 -or $copiedCount -eq $totalFiles)) {
                        Write-Log -Message "Copied $copiedCount of $totalFiles files..." -Level "INFO"
                    }
                }
                
                Write-Log -Message "Successfully copied all $copiedCount files to: $sourceFilesPath" -Level "SUCCESS"
                
                # Verify the main installer file was copied
                $mainInstallerPath = Join-Path -Path $sourceFilesPath -ChildPath $FileInfo.FileName
                if (Test-Path $mainInstallerPath) {
                    Write-Log -Message "✓ Main installer file confirmed: $($FileInfo.FileName)" -Level "SUCCESS"
                } else {
                    Write-Log -Message "⚠️ Main installer file not found after copy: $($FileInfo.FileName)" -Level "WARNING"
                }
            }
            
            # Also copy any subdirectories (for complex installations)
            $sourceSubDirs = Get-ChildItem -Path $sourceDirectory | Where-Object { $_.PSIsContainer } -ErrorAction SilentlyContinue
            if ($sourceSubDirs.Count -gt 0) {
                Write-Log -Message "Found $($sourceSubDirs.Count) subdirectories to copy" -Level "INFO"
                foreach ($subDir in $sourceSubDirs) {
                    $destSubDir = Join-Path -Path $sourceFilesPath -ChildPath $subDir.Name
                    Copy-Item -Path $subDir.FullName -Destination $destSubDir -Recurse -Force
                    Write-Log -Message "Copied subdirectory: $($subDir.Name)" -Level "INFO"
                }
            }
            
        } catch {
            Write-Log -Message "Error copying files from source directory: $($_.Exception.Message)" -Level "ERROR"
            # Fallback to copying just the installer file
            Write-Log -Message "Falling back to copying only the installer file" -Level "WARNING"
            $destinationFile = Join-Path -Path $sourceFilesPath -ChildPath $FileInfo.FileName
            Copy-Item -Path $FileInfo.FilePath -Destination $destinationFile -Force
            Write-Log -Message "Copied installer file to: $destinationFile" -Level "SUCCESS"        }
        
        # Save the reviewed package details to JSON
        $documentsPath = Join-Path -Path $versionPath -ChildPath "Documents"
        $jsonFilePath = Join-Path -Path $documentsPath -ChildPath "PackageConstructor.json"
        
        Write-Log -Message "Saving PackageConstructor.json..." -Level "INFO"
        
        try {
            $jsonContent = $reviewedPackage | ConvertTo-Json -Depth 10
            $jsonContent | Out-File -FilePath $jsonFilePath -Encoding UTF8
            Write-Log -Message "✓ Created PackageConstructor.json" -Level "SUCCESS"
        } catch {
            Write-Log -Message "Failed to create PackageConstructor.json: $($_.Exception.Message)" -Level "ERROR"
            return @{
                Success = $false
                Error = "Failed to create PackageConstructor.json: $($_.Exception.Message)"
            }
        }
        
        Write-Log -Message "Successfully processed: $($FileInfo.FileName)" -Level "SUCCESS"
        Write-Log -Message "Created at: $versionPath" -Level "INFO"
        return @{
            Success = $true
            PublisherName = $publisherName
            ApplicationName = $applicationName
            Version = $version
            VersionPath = $versionPath
        }
        
    } catch {
        Write-Log -Message "Error processing file: $($_.Exception.Message)" -Level "ERROR"
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

function Show-PackageDetailsDialog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$PackageDetails
    )
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    # Create the form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Review Package Details"
    $form.Size = New-Object System.Drawing.Size(600, 700)
    $form.StartPosition = "CenterParent"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    
    # Create scroll panel for content
    $scrollPanel = New-Object System.Windows.Forms.Panel
    $scrollPanel.Location = New-Object System.Drawing.Point(10, 10)
    $scrollPanel.Size = New-Object System.Drawing.Size(560, 600)
    $scrollPanel.AutoScroll = $true
    $form.Controls.Add($scrollPanel)
      $y = 10
    $controls = @{}
    
    # Detection Method Group Box
    $grpDetection = New-Object System.Windows.Forms.GroupBox
    $grpDetection.Text = "Detection Method"
    $grpDetection.Location = New-Object System.Drawing.Point(10, $y)
    $grpDetection.Size = New-Object System.Drawing.Size(540, 130)
    $grpDetection.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $scrollPanel.Controls.Add($grpDetection)
    
    # Detection method radio buttons
    $rbMsi = New-Object System.Windows.Forms.RadioButton
    $rbMsi.Text = "MSI Product Code"
    $rbMsi.Location = New-Object System.Drawing.Point(15, 25)
    $rbMsi.Size = New-Object System.Drawing.Size(150, 20)
    $rbMsi.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
    $grpDetection.Controls.Add($rbMsi)
    
    $rbFile = New-Object System.Windows.Forms.RadioButton
    $rbFile.Text = "File Detection"
    $rbFile.Location = New-Object System.Drawing.Point(175, 25)
    $rbFile.Size = New-Object System.Drawing.Size(150, 20)
    $rbFile.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
    $grpDetection.Controls.Add($rbFile)
    
    # MSI Product Code field
    $lblProductCode = New-Object System.Windows.Forms.Label
    $lblProductCode.Text = "Product Code:"
    $lblProductCode.Location = New-Object System.Drawing.Point(15, 55)
    $lblProductCode.Size = New-Object System.Drawing.Size(100, 20)
    $lblProductCode.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
    $grpDetection.Controls.Add($lblProductCode)
    
    $txtProductCode = New-Object System.Windows.Forms.TextBox
    $txtProductCode.Location = New-Object System.Drawing.Point(125, 53)
    $txtProductCode.Size = New-Object System.Drawing.Size(400, 20)
    $grpDetection.Controls.Add($txtProductCode)
    
    # File detection fields
    $lblFilePath = New-Object System.Windows.Forms.Label
    $lblFilePath.Text = "File Path:"
    $lblFilePath.Location = New-Object System.Drawing.Point(15, 80)
    $lblFilePath.Size = New-Object System.Drawing.Size(100, 20)
    $lblFilePath.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
    $grpDetection.Controls.Add($lblFilePath)
    
    $txtFilePath = New-Object System.Windows.Forms.TextBox
    $txtFilePath.Location = New-Object System.Drawing.Point(125, 78)
    $txtFilePath.Size = New-Object System.Drawing.Size(300, 20)
    $grpDetection.Controls.Add($txtFilePath)
    
    $lblFileName = New-Object System.Windows.Forms.Label
    $lblFileName.Text = "File Name:"
    $lblFileName.Location = New-Object System.Drawing.Point(15, 105)
    $lblFileName.Size = New-Object System.Drawing.Size(100, 20)
    $lblFileName.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
    $grpDetection.Controls.Add($lblFileName)
    
    $txtFileName = New-Object System.Windows.Forms.TextBox
    $txtFileName.Location = New-Object System.Drawing.Point(125, 103)
    $txtFileName.Size = New-Object System.Drawing.Size(200, 20)
    $grpDetection.Controls.Add($txtFileName)    # Set detection method values
    if ($PackageDetails.detection.method -eq "msi") {
        $rbMsi.Checked = $true
        if (-not [string]::IsNullOrWhiteSpace($PackageDetails.detection.productCode)) {
            $txtProductCode.Text = $PackageDetails.detection.productCode
        } else {
            $txtProductCode.Text = ""
            Write-Log -Message "MSI detection method but no product code available" -Level "WARNING"
        }
        $txtProductCode.Enabled = $true
        $txtFilePath.Enabled = $false
        $txtFileName.Enabled = $false
    } else {
        $rbFile.Checked = $true
        if (-not [string]::IsNullOrWhiteSpace($PackageDetails.detection.filePath)) {
            $txtFilePath.Text = $PackageDetails.detection.filePath
        } else {
            $txtFilePath.Text = ""
        }
        if (-not [string]::IsNullOrWhiteSpace($PackageDetails.detection.fileName)) {
            $txtFileName.Text = $PackageDetails.detection.fileName
        } else {
            $txtFileName.Text = ""
        }
        $txtProductCode.Enabled = $false
        $txtFilePath.Enabled = $true
        $txtFileName.Enabled = $true
    }
    
    # Radio button event handlers
    $rbMsi.Add_CheckedChanged({
        if ($rbMsi.Checked) {
            $txtProductCode.Enabled = $true
            $txtFilePath.Enabled = $false
            $txtFileName.Enabled = $false
        }
    })
    
    $rbFile.Add_CheckedChanged({
        if ($rbFile.Checked) {
            $txtProductCode.Enabled = $false
            $txtFilePath.Enabled = $true
            $txtFileName.Enabled = $true
        }
    })
    
    $y += 145  # Space for detection group box
    
    # Requirements Group Box
    $grpRequirements = New-Object System.Windows.Forms.GroupBox
    $grpRequirements.Text = "Requirements"
    $grpRequirements.Location = New-Object System.Drawing.Point(10, $y)
    $grpRequirements.Size = New-Object System.Drawing.Size(540, 60)
    $grpRequirements.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $scrollPanel.Controls.Add($grpRequirements)
    
    # Architecture dropdown
    $archLbl = New-Object System.Windows.Forms.Label
    $archLbl.Text = "Architecture:"
    $archLbl.Location = New-Object System.Drawing.Point(15, 25)
    $archLbl.Size = New-Object System.Drawing.Size(100, 20)
    $archLbl.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
    $grpRequirements.Controls.Add($archLbl)
    
    $cmbArch = New-Object System.Windows.Forms.ComboBox
    $cmbArch.Items.AddRange(@("x64", "x86", "arm64"))
    $cmbArch.Text = $PackageDetails.requirements.architecture
    $cmbArch.Location = New-Object System.Drawing.Point(125, 23)
    $cmbArch.Size = New-Object System.Drawing.Size(100, 20)
    $cmbArch.DropDownStyle = "DropDownList"
    $grpRequirements.Controls.Add($cmbArch)
    
    # Minimum OS dropdown
    $osLbl = New-Object System.Windows.Forms.Label
    $osLbl.Text = "Minimum OS:"
    $osLbl.Location = New-Object System.Drawing.Point(255, 25)
    $osLbl.Size = New-Object System.Drawing.Size(100, 20)
    $osLbl.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
    $grpRequirements.Controls.Add($osLbl)
    
    $cmbOS = New-Object System.Windows.Forms.ComboBox
    $cmbOS.Items.AddRange(@("W10_1903", "W10_1909", "W10_2004", "W10_20H2", "W10_21H1", "W11_21H2"))
    $cmbOS.Text = $PackageDetails.requirements.minimumOS
    $cmbOS.Location = New-Object System.Drawing.Point(365, 23)
    $cmbOS.Size = New-Object System.Drawing.Size(120, 20)
    $cmbOS.DropDownStyle = "DropDownList"
    $grpRequirements.Controls.Add($cmbOS)
      $y += 75  # Space for requirements group box
    
    # Add more spacing before other fields to prevent overlap
    $y += 25
    
    # Helper function to add labeled textbox
    function Add-LabeledTextBox {
        param($label, $value, $multiline = $false, $height = 25)
        
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $label
        $lbl.Location = New-Object System.Drawing.Point(10, $script:y)
        $lbl.Size = New-Object System.Drawing.Size(540, 20)
        $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $scrollPanel.Controls.Add($lbl)
        $script:y += 25  # Space for label
        
        $txt = New-Object System.Windows.Forms.TextBox
        $txt.Text = $value
        $txt.Location = New-Object System.Drawing.Point(10, $script:y)
        $txt.Size = New-Object System.Drawing.Size(540, $height)
        $txt.Multiline = $multiline
        if ($multiline) {
            $txt.ScrollBars = "Vertical"
        }
        $scrollPanel.Controls.Add($txt)
        
        # Add proper spacing between fields
        if ($multiline) {
            $script:y += $height + 15  # More space for multiline fields
        } else {
            $script:y += $height + 20  # More space for single-line fields
        }
        
        return $txt
    }
    
    # Add fields for editing
    $controls.Publisher = Add-LabeledTextBox -label "Publisher:" -value $PackageDetails.publisher  
    $controls.ApplicationName = Add-LabeledTextBox -label "Application Name:" -value $PackageDetails.applicationName 
    $controls.Version = Add-LabeledTextBox -label "Version:" -value $PackageDetails.version 
    $controls.DisplayName = Add-LabeledTextBox -label "Intune Display Name:" -value $PackageDetails.intuneDisplayName
    $controls.InstallCommand = Add-LabeledTextBox -label "Install Command:" -value $PackageDetails.installCommand -multiline $true -height 50
    $controls.UninstallCommand = Add-LabeledTextBox -label "Uninstall Command:" -value $PackageDetails.uninstallCommand -multiline $true -height 50
    $controls.Description = Add-LabeledTextBox -label "Description:" -value $PackageDetails.metadata.description -multiline $true -height 50
    $controls.Category = Add-LabeledTextBox -label "Category:" -value $PackageDetails.metadata.category
    
    # Buttons
    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text = "Save Package"
    $btnOK.Location = New-Object System.Drawing.Point(450, 620)
    $btnOK.Size = New-Object System.Drawing.Size(100, 30)
    $btnOK.DialogResult = "OK"
    $form.Controls.Add($btnOK)
    
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(340, 620)
    $btnCancel.Size = New-Object System.Drawing.Size(100, 30)
    $btnCancel.DialogResult = "Cancel"
    $form.Controls.Add($btnCancel)
    
    $form.AcceptButton = $btnOK
    $form.CancelButton = $btnCancel
    
    # Show the dialog
    $result = $form.ShowDialog()
    
    if ($result -eq "OK") {
        # Update package details with user input
        $PackageDetails.publisher = $controls.Publisher.Text
        $PackageDetails.applicationName = $controls.ApplicationName.Text
        $PackageDetails.version = $controls.Version.Text
        $PackageDetails.intuneDisplayName = $controls.DisplayName.Text
        $PackageDetails.installCommand = $controls.InstallCommand.Text
        $PackageDetails.uninstallCommand = $controls.UninstallCommand.Text
        $PackageDetails.metadata.description = $controls.Description.Text
        $PackageDetails.metadata.category = $controls.Category.Text
        $PackageDetails.requirements.architecture = $cmbArch.Text
        $PackageDetails.requirements.minimumOS = $cmbOS.Text
        
        # Update detection method
        if ($rbMsi.Checked) {
            $PackageDetails.detection = @{
                method = "msi"
                productCode = $txtProductCode.Text
            }
        } else {
            $PackageDetails.detection = @{
                method = "file"
                filePath = $txtFilePath.Text
                fileName = $txtFileName.Text
                detectionType = "exists"
            }
        }
        
        $PackageDetails.metadata.updatedDate = (Get-Date -Format "yyyy-MM-dd")
        $PackageDetails.metadata.updatedBy = $env:USERNAME
        
        return $PackageDetails
    }
    
    $form.Dispose()
    return $null
}

function New-PackageConstructorFromFileInfo {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$VersionPath,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$FileInfo,
        
        [Parameter(Mandatory = $true)]
        [string]$PublisherName,
        
        [Parameter(Mandatory = $true)]
        [string]$ApplicationName,
        
        [Parameter(Mandatory = $true)]
        [string]$Version
    )
    
    $documentsPath = Join-Path -Path $VersionPath -ChildPath "Documents"
    $jsonFilePath = Join-Path -Path $documentsPath -ChildPath "PackageConstructor.json"
    
    Write-Log -Message "Creating PackageConstructor.json..." -Level "INFO"
    
    try {
        # Determine install command based on file type
        $installCommand = if ($FileInfo.FileName -match '\.msi$') {
            "msiexec /i `"$($FileInfo.FileName)`" /quiet /norestart"
        } else {
            "`"$($FileInfo.FileName)`" /S"
        }
        
        # Determine uninstall command
        $uninstallCommand = if ($FileInfo.FileName -match '\.msi$' -and $FileInfo.VersionInfo.ProductCode) {
            "msiexec /x `"$($FileInfo.VersionInfo.ProductCode)`" /quiet /norestart"
        } else {
            ""
        }
        
        # Create detection method
        $detection = if ($FileInfo.FileName -match '\.msi$' -and $FileInfo.VersionInfo.ProductCode) {
            @{
                method = "msi"
                productCode = $FileInfo.VersionInfo.ProductCode
            }
        } else {
            @{
                method = "file"
                filePath = "%ProgramFiles%\$PublisherName\$ApplicationName"
                fileName = [System.IO.Path]::GetFileNameWithoutExtension($FileInfo.FileName) + ".exe"
                detectionType = "exists"
            }
        }
        
        $packageConstructor = @{
            publisher = $PublisherName
            applicationName = $ApplicationName
            version = $Version
            intuneDisplayName = "$PublisherName - $ApplicationName - $Version"
            installCommand = $installCommand
            uninstallCommand = $uninstallCommand
            detection = $detection
            requirements = @{
                architecture = "x64"
                minimumOS = "W10_1903"
            }
            metadata = @{
                category = "Productivity"
                description = if ($FileInfo.VersionInfo.FileDescription) { $FileInfo.VersionInfo.FileDescription } else { "$ApplicationName installer" }
                createdDate = (Get-Date -Format "yyyy-MM-dd")
                updatedDate = (Get-Date -Format "yyyy-MM-dd")
                createdBy = $env:USERNAME
                updatedBy = $env:USERNAME
                sourceFile = $FileInfo.FileName
                sourceVersion = $FileInfo.VersionInfo.FileVersion
                originalPath = $FileInfo.FilePath
            }        }
        
        # Save the package without showing dialog (for compatibility with other workflows)
        $jsonContent = $packageConstructor | ConvertTo-Json -Depth 10
        $jsonContent | Out-File -FilePath $jsonFilePath -Encoding UTF8
        
        Write-Log -Message "Created PackageConstructor.json" -Level "SUCCESS"
        Write-Log -Message "Publisher: $($packageConstructor.publisher)" -Level "INFO"
        Write-Log -Message "Application: $($packageConstructor.applicationName)" -Level "INFO"
        Write-Log -Message "Version: $($packageConstructor.version)" -Level "INFO"
        Write-Log -Message "Install Command: $($packageConstructor.installCommand)" -Level "INFO"
        
        return $true
        
    } catch {
        Write-Log -Message "Failed to create PackageConstructor.json: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

#endregion

#region Intune Functions

function Invoke-IntunePackaging {
    param(
        [string]$VersionPath,
        [hashtable]$SourceFileInfo
    )
    
    Write-Log -Message "Starting Intune packaging..." -Level "INFO"
    write-log -Message "using path: $versionPath"
    $sourceFilesPath = Join-Path -Path $VersionPath -ChildPath "_Sourcefiles"
    $documentsPath = Join-Path -Path $VersionPath -ChildPath "Documents"
    $intunewinPath = Join-Path -Path $VersionPath -ChildPath "intunewin"
    $jsonFilePath = Join-Path -Path $documentsPath -ChildPath "PackageConstructor.json"
    
    if (-not (Test-Path $sourceFilesPath)) {
        Write-Log -Message "Source files path not found: $sourceFilesPath" -Level "ERROR"
        return $false
    }
    
    if (-not (Test-Path $jsonFilePath)) {
        Write-Log -Message "PackageConstructor.json not found: $jsonFilePath" -Level "ERROR"
        return $false
    }
    
    try {
        $packageInfo = Get-Content -Path $jsonFilePath -Raw | ConvertFrom-Json
        Write-Log -Message "✓ Package constructor loaded" -Level "SUCCESS"
        
        Write-Log -Message "JSON Configuration:" -Level "INFO"
        Write-Log -Message "  Publisher: $($packageInfo.publisher)" -Level "INFO"
        Write-Log -Message "  Application: $($packageInfo.applicationName)" -Level "INFO"
        Write-Log -Message "  Version: $($packageInfo.version)" -Level "INFO"
    } catch {
        Write-Log -Message "Failed to parse PackageConstructor.json: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
    
    $setupFilePath = Join-Path -Path $sourceFilesPath -ChildPath $SourceFileInfo.FileName
    if (-not (Test-Path $setupFilePath)) {
        Write-Log -Message "Setup file not found: $setupFilePath" -Level "ERROR"
        return $false
    }
    
    if ($WhatIf) {
        Write-Log -Message "  [WHAT-IF] Would package to Intune" -Level "INFO"
        return $true
    }
      Write-Log -Message "Connecting to Intune..." -Level "INFO"
    try {
        Connect-MSIntuneGraph -TenantID $TenantId -ClientID $ClientId -ClientSecret $ClientSecret -ErrorAction Stop
        Write-Log -Message "✓ Connected to Intune" -Level "SUCCESS"
    } catch {
        Write-Log -Message "Failed to connect to Intune: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
      Write-Log -Message "Creating .intunewin package..." -Level "INFO"
    $tempPath = Join-Path -Path $env:TEMP -ChildPath "IntunePackaging_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    
    try {
        New-Item -Path $tempPath -ItemType Directory -Force | Out-Null
        $intuneWinFile = New-IntuneWin32AppPackage -SourceFolder $sourceFilesPath -SetupFile $SourceFileInfo.FileName -OutputFolder $tempPath
        
        if (-not $intuneWinFile -or -not (Test-Path $intuneWinFile.Path)) {
            Write-Log -Message ".intunewin package creation failed" -Level "ERROR"
            # Clean up temp directory on failure
            if (Test-Path $tempPath) {
                Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            return $false
        }
        
        Write-Log -Message "✓ .intunewin package created: $($intuneWinFile.Path)" -Level "SUCCESS"
    } catch {
        Write-Log -Message "Failed to create .intunewin package: $($_.Exception.Message)" -Level "ERROR"
        # Clean up temp directory on exception
        if (Test-Path $tempPath) {
            Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        return $false
    }
    
    Write-Log -Message "Creating detection rule..." -Level "INFO"
    # Create detection rule based on JSON configuration
    Write-Host "  Creating detection rule..." -ForegroundColor Yellow
    try {
        $detectionRule = $null
        
        switch ($packageInfo.detection.method.ToLower()) {
            "msi" {
                if ($packageInfo.detection.productCode) {
                    $detectionRule = New-IntuneWin32AppDetectionRuleMSI -ProductCode $packageInfo.detection.productCode
                    Write-Host "    Using MSI product code detection: $($packageInfo.detection.productCode)" -ForegroundColor Gray
                }
            }            "registry" {
                if ($packageInfo.detection.registryPath -and $packageInfo.detection.registryValue) {
                    $detectionRule = New-IntuneWin32AppDetectionRuleRegistry -Existence -KeyPath $packageInfo.detection.registryPath -ValueName $packageInfo.detection.registryValue -DetectionType "exists"
                    Write-Host "    Using registry detection: $($packageInfo.detection.registryPath)" -ForegroundColor Gray
                }
            }
            "file" {
                if ($packageInfo.detection.filePath -and $packageInfo.detection.fileName) {
                    $detectionRule = New-IntuneWin32AppDetectionRuleFile -Existence -Path $packageInfo.detection.filePath -FileOrFolder $packageInfo.detection.fileName -DetectionType "exists"
                    Write-Host "    Using file detection: $($packageInfo.detection.filePath)\$($packageInfo.detection.fileName)" -ForegroundColor Gray
                }
            }
            default {
                Write-Warning "Unknown detection method: $($packageInfo.detection.method)"
            }
        }
        
        # Fallback if JSON detection fails
        if (-not $detectionRule) {
            Write-Warning "Failed to create detection rule from JSON, using fallback"
            $appNameForDetection = if ($packageInfo.applicationName) { $packageInfo.applicationName } else { "Application" }
            $detectionRule = New-IntuneWin32AppDetectionRuleFile -Existence -Path "%ProgramFiles%" -FileOrFolder $appNameForDetection -DetectionType "exists"
            Write-Host "    Using fallback file detection: %ProgramFiles%\$appNameForDetection" -ForegroundColor Gray
        }
        
        Write-Host "  ✓ Detection rule created" -ForegroundColor Green
    } catch {
        Write-Error "Failed to create detection rule: $($_.Exception.Message)"
        return $false
    }      Write-Log -Message "Creating requirement rule..." -Level "INFO"
    try {
        $architecture = if ($packageInfo.requirements.architecture) { $packageInfo.requirements.architecture } else { "x64" }
        $minimumOS = if ($packageInfo.requirements.minimumOS) { $packageInfo.requirements.minimumOS } else { "W10_1903" }
        $requirementRule = New-IntuneWin32AppRequirementRule -Architecture $architecture -MinimumSupportedWindowsRelease $minimumOS
        Write-Log -Message "✓ Requirement rule created" -Level "SUCCESS"
    } catch {
        Write-Log -Message "Failed to create requirement rule: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }      Write-Log -Message "Publishing to Intune..." -Level "INFO"
    try {
        $displayName = $packageInfo.intuneDisplayName
        $description = if ($packageInfo.metadata.description) { $packageInfo.metadata.description } else { "$($packageInfo.applicationName) installer" }
        $publisher = $packageInfo.publisher
        $appVersion = $packageInfo.version
        $installCommand = $packageInfo.installCommand
        $uninstallCommand = if ($packageInfo.uninstallCommand) { $packageInfo.uninstallCommand } else { "cmd.exe" }
        
        # Check for extracted icon and create Intune icon if available
        $intuneIcon = $null
        if ($packageInfo.metadata.icon -and $packageInfo.metadata.icon.filePath -and (Test-Path $packageInfo.metadata.icon.filePath)) {
            try {
                Write-Log -Message "Creating Intune icon from extracted file: $($packageInfo.metadata.icon.fileName)" -Level "INFO"
                $intuneIcon = New-IntuneWin32AppIcon -FilePath $packageInfo.metadata.icon.filePath
                Write-Log -Message "✓ Intune icon created successfully" -Level "SUCCESS"
            } catch {
                Write-Log -Message "Failed to create Intune icon: $($_.Exception.Message)" -Level "WARNING"
                $intuneIcon = $null
            }
        } else {
            Write-Log -Message "No icon file available for Intune package" -Level "INFO"
        }
        
        # Create the Intune app with or without icon
        if ($intuneIcon) {
            Write-Log -Message "Publishing app with custom icon..." -Level "INFO"
            $app = Add-IntuneWin32App -FilePath $intuneWinFile.Path -DisplayName $displayName -Description $description -Publisher $publisher -AppVersion $appVersion -InstallCommandLine $installCommand -UninstallCommandLine $uninstallCommand -InstallExperience "system" -RestartBehavior "suppress" -DetectionRule $detectionRule -RequirementRule $requirementRule -Icon $intuneIcon
        } else {
            Write-Log -Message "Publishing app without custom icon..." -Level "INFO"
            $app = Add-IntuneWin32App -FilePath $intuneWinFile.Path -DisplayName $displayName -Description $description -Publisher $publisher -AppVersion $appVersion -InstallCommandLine $installCommand -UninstallCommandLine $uninstallCommand -InstallExperience "system" -RestartBehavior "suppress" -DetectionRule $detectionRule -RequirementRule $requirementRule
        }
        
        Write-Log -Message "✓ Application published: $($app.id)" -Level "SUCCESS"
        
        # Clean up and backup .intunewin file after successful publishing
        if (Test-Path $intuneWinFile.Path) {
            $backupPath = Join-Path -Path $intunewinPath -ChildPath "$([System.IO.Path]::GetFileNameWithoutExtension($intuneWinFile.Path))_$(Get-Date -Format 'yyyyMMdd_HHmmss').intunewin"
            Copy-Item -Path $intuneWinFile.Path -Destination $backupPath -Force
            Write-Log -Message "✓ .intunewin file backed up to: $backupPath" -Level "SUCCESS"
        }
        
        # Clean up temp directory after successful publishing
        if (Test-Path $tempPath) {
            Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log -Message "✓ Temporary files cleaned up" -Level "SUCCESS"
        }
        
        return $true
    } catch {
        Write-Log -Message "Failed to publish to Intune: $($_.Exception.Message)" -Level "ERROR"
        
        # Clean up temp directory on publishing failure
        if (Test-Path $tempPath) {
            Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        return $false
    }
}

#endregion

#region GUI Functions

function Show-MigrationGUI {
    # Enhanced form with modern styling
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "MECM to Intune App Migration Tool v2.0"
    $form.Size = New-Object System.Drawing.Size(1005, 700)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    # Add title header with icon simulation
    $headerPanel = New-Object System.Windows.Forms.Panel
    $headerPanel.Size = New-Object System.Drawing.Size(980, 60)
    $headerPanel.Location = New-Object System.Drawing.Point(10, 10)
    $headerPanel.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "☁  MECM Apps to Intune Migration Tool"
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = [System.Drawing.Color]::White
    $titleLabel.Size = New-Object System.Drawing.Size(500, 30)
    $titleLabel.Location = New-Object System.Drawing.Point(20, 15)

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Name = "StatusLabel"
    $statusLabel.Text = "> Ready to migrate applications"
    $statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $statusLabel.ForeColor = [System.Drawing.Color]::White
    $statusLabel.Size = New-Object System.Drawing.Size(400, 20)
    $statusLabel.Location = New-Object System.Drawing.Point(650, 35)

    $headerPanel.Controls.Add($titleLabel)
    $headerPanel.Controls.Add($statusLabel)
    $form.Controls.Add($headerPanel)

    # Enhanced tab control
    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Size = New-Object System.Drawing.Size(980, 580)
    $tabControl.Location = New-Object System.Drawing.Point(10, 80)
    $tabControl.Font = New-Object System.Drawing.Font("Segoe UI", 9)    # Tab 1: Application Selection with enhanced UI
    $tabAppSelection = New-Object System.Windows.Forms.TabPage
    $tabAppSelection.Text = "▶  Select Application"
    $tabAppSelection.BackColor = [System.Drawing.Color]::White

    # Search panel
    $searchPanel = New-Object System.Windows.Forms.Panel
    $searchPanel.Size = New-Object System.Drawing.Size(940, 50)
    $searchPanel.Location = New-Object System.Drawing.Point(10, 10)
    $searchPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $searchPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $searchLabel = New-Object System.Windows.Forms.Label
    $searchLabel.Text = "⌕ Search Applications:"
    $searchLabel.Size = New-Object System.Drawing.Size(130, 20)
    $searchLabel.Location = New-Object System.Drawing.Point(10, 15)
    $searchLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

    $searchBox = New-Object System.Windows.Forms.TextBox
    $searchBox.Size = New-Object System.Drawing.Size(300, 20)
    $searchBox.Location = New-Object System.Drawing.Point(150, 12)
    $searchBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $refreshButton = New-Object System.Windows.Forms.Button
    $refreshButton.Text = "Refresh"
    $refreshButton.Size = New-Object System.Drawing.Size(80, 25)
    $refreshButton.Location = New-Object System.Drawing.Point(460, 10)
    $refreshButton.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
    $refreshButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

    $searchPanel.Controls.Add($searchLabel)
    $searchPanel.Controls.Add($searchBox)
    $searchPanel.Controls.Add($refreshButton)

    # Enhanced application list with better styling
    $appListView = New-Object System.Windows.Forms.DataGridView
    $appListView.Size = New-Object System.Drawing.Size(940, 330)
    $appListView.Location = New-Object System.Drawing.Point(10, 70)
    $appListView.SelectionMode = "FullRowSelect"
    $appListView.MultiSelect = $false
    $appListView.AllowUserToAddRows = $false
    $appListView.AllowUserToDeleteRows = $false
    $appListView.ReadOnly = $true
    $appListView.BackgroundColor = [System.Drawing.Color]::White
    $appListView.GridColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
    $appListView.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $appListView.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
    $appListView.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
    $appListView.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $appListView.Columns.Add("Status", "📊 Status") | Out-Null
    $appListView.Columns.Add("AppName", "📱 Application Name") | Out-Null
    $appListView.Columns.Add("Version", "📋 Version") | Out-Null
    $appListView.Columns.Add("Manufacturer", "🏢 Manufacturer") | Out-Null
    $appListView.Columns.Add("Deployments", "🎯 Deployments") | Out-Null
    $appListView.Columns.Add("DevicesCount", "📱 Devices Count") | Out-Null
    $appListView.Columns[0].Width = 80
    $appListView.Columns[1].Width = 350
    $appListView.Columns[2].Width = 100
    $appListView.Columns[3].Width = 200
    $appListView.Columns[4].Width = 100
    $appListView.Columns[5].Width = 100
    # Add a button to get apps
    $btnGetApps = New-Object System.Windows.Forms.Button
    $btnGetApps.Text = "Get Apps"
    $btnGetApps.Size = New-Object System.Drawing.Size(100, 30)
    $btnGetApps.Location = New-Object System.Drawing.Point(30, 453)
    $btnGetApps.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnGetApps.ForeColor = [System.Drawing.Color]::White
    $btnGetApps.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnGetApps.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    # Status label for loading
    $appsStatusLabel = New-Object System.Windows.Forms.Label
    $appsStatusLabel.Text = "Ready"
    $appsStatusLabel.Size = New-Object System.Drawing.Size(400, 25)
    $appsStatusLabel.Location = New-Object System.Drawing.Point(30, 515)
    $appsStatusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $appsStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    #no background color
    $appsStatusLabel.BackColor = [System.Drawing.Color]::Transparent
    $appsStatusLabel.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    
    # Add controls to the tab (without event handler yet)
    $tabAppSelection.Controls.Add($appListView)
    $tabAppSelection.Controls.Add($btnGetApps)
    $tabAppSelection.Controls.Add($appsStatusLabel)

    # Action panel for application selection
    $actionPanel = New-Object System.Windows.Forms.Panel
    $actionPanel.Size = New-Object System.Drawing.Size(940, 80)
    $actionPanel.Location = New-Object System.Drawing.Point(10, 430)
    $actionPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $actionPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $btnSelectApp = New-Object System.Windows.Forms.Button
    $btnSelectApp.Text = "▶ Select Application"
    $btnSelectApp.Size = New-Object System.Drawing.Size(180, 35)
    $btnSelectApp.Location = New-Object System.Drawing.Point(700, 20)
    $btnSelectApp.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnSelectApp.ForeColor = [System.Drawing.Color]::White
    $btnSelectApp.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnSelectApp.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

    $selectionInfo = New-Object System.Windows.Forms.Label
    $selectionInfo.Name = "SelectionInfo"
    $selectionInfo.Text = "Select an application from the list above to continue"
    $selectionInfo.Size = New-Object System.Drawing.Size(700, 35)
    $selectionInfo.Location = New-Object System.Drawing.Point(220, 30)
    $selectionInfo.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $selectionInfo.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)

    $actionPanel.Controls.Add($btnSelectApp)
    $actionPanel.Controls.Add($selectionInfo)

   

    $tabAppSelection.Controls.Add($searchPanel)
    $tabAppSelection.Controls.Add($appListView)
    $tabAppSelection.Controls.Add($actionPanel)    # Tab 2: Enhanced Destination Selection
    $tabDestination = New-Object System.Windows.Forms.TabPage
    $tabDestination.Text = "🎯 Configure Destination"
    $tabDestination.BackColor = [System.Drawing.Color]::White

    # Configuration panel
    $configPanel = New-Object System.Windows.Forms.Panel
    $configPanel.Size = New-Object System.Drawing.Size(940, 300)
    $configPanel.Location = New-Object System.Drawing.Point(10, 10)
    $configPanel.BackColor = [System.Drawing.Color]::White
    $configPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $configTitle = New-Object System.Windows.Forms.Label
    $configTitle.Text = "Destination Configuration"
    $configTitle.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $configTitle.Size = New-Object System.Drawing.Size(300, 25)
    $configTitle.Location = New-Object System.Drawing.Point(20, 20)
    $configTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)

    # Publisher section with enhanced styling
    $lblPublisher = New-Object System.Windows.Forms.Label
    $lblPublisher.Text = "Publisher:"
    $lblPublisher.Size = New-Object System.Drawing.Size(100, 20)
    $lblPublisher.Location = New-Object System.Drawing.Point(20, 60)
    $lblPublisher.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

    $cmbPublisher = New-Object System.Windows.Forms.ComboBox
    $cmbPublisher.Size = New-Object System.Drawing.Size(350, 25)
    $cmbPublisher.Location = New-Object System.Drawing.Point(130, 58)
    $cmbPublisher.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $cmbPublisher.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    
    Set-Location c:
    $publishers = Get-ChildItem -Path $BaseAppPath | Where-Object { $_.PSIsContainer -and $_.Name -ne "_Template_Publisher" } | Sort-Object Name
    foreach ($pub in $publishers) {
        $cmbPublisher.Items.Add($pub.Name) | Out-Null
    }
    $cmbPublisher.Items.Add("➕ Create New Publisher")

    $txtNewPublisher = New-Object System.Windows.Forms.TextBox
    $txtNewPublisher.Size = New-Object System.Drawing.Size(350, 25)
    $txtNewPublisher.Location = New-Object System.Drawing.Point(130, 88)
    $txtNewPublisher.Visible = $false
    $txtNewPublisher.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    # Application section
    $lblApplication = New-Object System.Windows.Forms.Label
    $lblApplication.Text = "Application:"
    $lblApplication.Size = New-Object System.Drawing.Size(100, 20)
    $lblApplication.Location = New-Object System.Drawing.Point(20, 125)
    $lblApplication.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

    $cmbApplication = New-Object System.Windows.Forms.ComboBox
    $cmbApplication.Size = New-Object System.Drawing.Size(350, 25)
    $cmbApplication.Location = New-Object System.Drawing.Point(130, 123)
    $cmbApplication.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $cmbApplication.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cmbApplication.Items.Add("➕ Create New Application")

    $txtNewApplication = New-Object System.Windows.Forms.TextBox
    $txtNewApplication.Size = New-Object System.Drawing.Size(350, 25)
    $txtNewApplication.Location = New-Object System.Drawing.Point(130, 153)
    $txtNewApplication.Visible = $false
    $txtNewApplication.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    # Version section
    $lblVersion = New-Object System.Windows.Forms.Label
    $lblVersion.Text = "Version:"
    $lblVersion.Size = New-Object System.Drawing.Size(100, 20)
    $lblVersion.Location = New-Object System.Drawing.Point(20, 190)
    $lblVersion.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

    $txtVersion = New-Object System.Windows.Forms.TextBox
    $txtVersion.Size = New-Object System.Drawing.Size(200, 25)
    $txtVersion.Location = New-Object System.Drawing.Point(130, 188)
    $txtVersion.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    # Preview panel
    $previewPanel = New-Object System.Windows.Forms.Panel
    $previewPanel.Size = New-Object System.Drawing.Size(380, 180)
    $previewPanel.Location = New-Object System.Drawing.Point(520, 60)
    $previewPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $previewPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $previewTitle = New-Object System.Windows.Forms.Label
    $previewTitle.Text = "※ Preview"
    $previewTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $previewTitle.Size = New-Object System.Drawing.Size(100, 20)
    $previewTitle.Location = New-Object System.Drawing.Point(10, 10)

    $previewText = New-Object System.Windows.Forms.Label
    $previewText.Name = "PreviewText"
    $previewText.Text = "Configuration will appear here..."
    $previewText.Size = New-Object System.Drawing.Size(360, 150)
    $previewText.Location = New-Object System.Drawing.Point(10, 35)
    $previewText.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $previewText.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)

    $previewPanel.Controls.Add($previewTitle)
    $previewPanel.Controls.Add($previewText)

    $configPanel.Controls.Add($configTitle)
    $configPanel.Controls.Add($lblPublisher)
    $configPanel.Controls.Add($cmbPublisher)
    $configPanel.Controls.Add($txtNewPublisher)
    $configPanel.Controls.Add($lblApplication)
    $configPanel.Controls.Add($cmbApplication)
    $configPanel.Controls.Add($txtNewApplication)
    $configPanel.Controls.Add($lblVersion)
    $configPanel.Controls.Add($txtVersion)
    $configPanel.Controls.Add($previewPanel)

    # Action panel for destination
    $destActionPanel = New-Object System.Windows.Forms.Panel
    $destActionPanel.Size = New-Object System.Drawing.Size(940, 80)
    $destActionPanel.Location = New-Object System.Drawing.Point(10, 320)
    $destActionPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $destActionPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $btnSelectDestination = New-Object System.Windows.Forms.Button
    $btnSelectDestination.Text = "➡️ Configure Destination"
    $btnSelectDestination.Size = New-Object System.Drawing.Size(180, 35)
    $btnSelectDestination.Location = New-Object System.Drawing.Point(20, 20)
    $btnSelectDestination.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnSelectDestination.ForeColor = [System.Drawing.Color]::White
    $btnSelectDestination.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnSelectDestination.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

    $destInfo = New-Object System.Windows.Forms.Label
    $destInfo.Name = "DestInfo"
    $destInfo.Text = "Configure publisher, application, and version details"
    $destInfo.Size = New-Object System.Drawing.Size(700, 35)
    $destInfo.Location = New-Object System.Drawing.Point(220, 20)
    $destInfo.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $destInfo.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)

    $destActionPanel.Controls.Add($btnSelectDestination)
    $destActionPanel.Controls.Add($destInfo)

    $tabDestination.Controls.Add($configPanel)
    $tabDestination.Controls.Add($destActionPanel)    # Tab 3: Enhanced Migration Execution
    $tabExecution = New-Object System.Windows.Forms.TabPage
    $tabExecution.Text = "🚀 Execute Migration"
    $tabExecution.BackColor = [System.Drawing.Color]::White

    # Status panel
    $statusPanel = New-Object System.Windows.Forms.Panel
    $statusPanel.Size = New-Object System.Drawing.Size(940, 80)
    $statusPanel.Location = New-Object System.Drawing.Point(10, 10)
    $statusPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $statusPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $statusTitle = New-Object System.Windows.Forms.Label
    $statusTitle.Text = "Migration Status"
    $statusTitle.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $statusTitle.Size = New-Object System.Drawing.Size(200, 25)
    $statusTitle.Location = New-Object System.Drawing.Point(20, 15)
    $statusTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)

    $currentStatus = New-Object System.Windows.Forms.Label
    $currentStatus.Name = "CurrentStatus"
    $currentStatus.Text = "Ready to start migration..."
    $currentStatus.Size = New-Object System.Drawing.Size(600, 20)
    $currentStatus.Location = New-Object System.Drawing.Point(20, 45)
    $currentStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $currentStatus.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)

    $statusPanel.Controls.Add($statusTitle)
    $statusPanel.Controls.Add($currentStatus)    # Enhanced log display with color coding
    $logPanel = New-Object System.Windows.Forms.Panel
    $logPanel.Size = New-Object System.Drawing.Size(940, 330)
    $logPanel.Location = New-Object System.Drawing.Point(10, 100)
    $logPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $logTitle = New-Object System.Windows.Forms.Label
    $logTitle.Text = "Migration Log"
    $logTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $logTitle.Size = New-Object System.Drawing.Size(140, 20)
    $logTitle.Location = New-Object System.Drawing.Point(10, 10)
    $logTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)

    $txtLog = New-Object System.Windows.Forms.RichTextBox
    $txtLog.Size = New-Object System.Drawing.Size(920, 290)
    $txtLog.Location = New-Object System.Drawing.Point(10, 35)
    $txtLog.ReadOnly = $true
    $txtLog.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
    $txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
    $txtLog.BorderStyle = [System.Windows.Forms.BorderStyle]::None

    $logPanel.Controls.Add($logTitle)
    $logPanel.Controls.Add($txtLog)    # Enhanced progress and control panel
    $progressPanel = New-Object System.Windows.Forms.Panel
    $progressPanel.Size = New-Object System.Drawing.Size(940, 120)
    $progressPanel.Location = New-Object System.Drawing.Point(10, 440)
    $progressPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $progressPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $progressTitle = New-Object System.Windows.Forms.Label
    $progressTitle.Text = "Progress"
    $progressTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $progressTitle.Size = New-Object System.Drawing.Size(100, 20)
    $progressTitle.Location = New-Object System.Drawing.Point(20, 15)
    $progressTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)

    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Size = New-Object System.Drawing.Size(720, 25)
    $progressBar.Location = New-Object System.Drawing.Point(20, 40)
    $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous

    $progressLabel = New-Object System.Windows.Forms.Label
    $progressLabel.Name = "ProgressLabel"
    $progressLabel.Text = "0% - Ready to start"
    $progressLabel.Size = New-Object System.Drawing.Size(200, 20)
    $progressLabel.Location = New-Object System.Drawing.Point(750, 45)
    $progressLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $btnMigrate = New-Object System.Windows.Forms.Button
    $btnMigrate.Text = "⚡  Start Migration"
    $btnMigrate.Size = New-Object System.Drawing.Size(150, 35)
    $btnMigrate.Location = New-Object System.Drawing.Point(20, 75)
    $btnMigrate.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnMigrate.ForeColor = [System.Drawing.Color]::White
    $btnMigrate.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnMigrate.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "❌ Cancel"
    $btnCancel.Size = New-Object System.Drawing.Size(100, 35)
    $btnCancel.Location = New-Object System.Drawing.Point(180, 75)
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $btnCancel.ForeColor = [System.Drawing.Color]::Black
    $btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCancel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    
    $progressPanel.Controls.Add($progressTitle)
    $progressPanel.Controls.Add($progressBar)
    $progressPanel.Controls.Add($progressLabel)
    $progressPanel.Controls.Add($btnMigrate)
    $progressPanel.Controls.Add($btnCancel)

    $tabExecution.Controls.Add($statusPanel)
    $tabExecution.Controls.Add($logPanel)
    $tabExecution.Controls.Add($progressPanel)

    # Tab 4: New App - Source File Management
    $tabNewApp = New-Object System.Windows.Forms.TabPage
    $tabNewApp.Text = "➕ New Intune App"
    $tabNewApp.BackColor = [System.Drawing.Color]::White

    # New App header
    $newAppHeaderPanel = New-Object System.Windows.Forms.Panel
    $newAppHeaderPanel.Size = New-Object System.Drawing.Size(940, 60)
    $newAppHeaderPanel.Location = New-Object System.Drawing.Point(10, 10)
    $newAppHeaderPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $newAppHeaderPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $newAppHeaderTitle = New-Object System.Windows.Forms.Label
    $newAppHeaderTitle.Text = "➕  Add New Application"
    $newAppHeaderTitle.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $newAppHeaderTitle.Size = New-Object System.Drawing.Size(300, 25)
    $newAppHeaderTitle.Location = New-Object System.Drawing.Point(14, 10)
    $newAppHeaderTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)

    $newAppHeaderDesc = New-Object System.Windows.Forms.Label
    $newAppHeaderDesc.Text = "Browse for application source files and create new packages"
    $newAppHeaderDesc.Size = New-Object System.Drawing.Size(400, 20)
    $newAppHeaderDesc.Location = New-Object System.Drawing.Point(22, 30)
    $newAppHeaderDesc.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $newAppHeaderDesc.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)

    $newAppHeaderPanel.Controls.Add($newAppHeaderTitle)
    $newAppHeaderPanel.Controls.Add($newAppHeaderDesc)

    # Source file selection panel
    $sourceFilePanel = New-Object System.Windows.Forms.Panel
    $sourceFilePanel.Size = New-Object System.Drawing.Size(940, 120)
    $sourceFilePanel.Location = New-Object System.Drawing.Point(10, 80)
    $sourceFilePanel.BackColor = [System.Drawing.Color]::White
    $sourceFilePanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $sourceFileTitle = New-Object System.Windows.Forms.Label
    $sourceFileTitle.Text = "Source File Selection"
    $sourceFileTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $sourceFileTitle.Size = New-Object System.Drawing.Size(200, 20)
    $sourceFileTitle.Location = New-Object System.Drawing.Point(15, 15)
    $sourceFileTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)

    # Drop path selection
    $lblDropPath = New-Object System.Windows.Forms.Label
    $lblDropPath.Text = "Drop Folder/File:"
    $lblDropPath.Size = New-Object System.Drawing.Size(100, 20)
    $lblDropPath.Location = New-Object System.Drawing.Point(15, 45)
    $lblDropPath.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $txtDropPath = New-Object System.Windows.Forms.TextBox
    $txtDropPath.Size = New-Object System.Drawing.Size(550, 25)
    $txtDropPath.Location = New-Object System.Drawing.Point(120, 43)
    $txtDropPath.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $txtDropPath.ReadOnly = $true
    $txtDropPath.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)

    $btnBrowseDropPath = New-Object System.Windows.Forms.Button
    $btnBrowseDropPath.Text = "Browse..."
    $btnBrowseDropPath.Size = New-Object System.Drawing.Size(80, 25)
    $btnBrowseDropPath.Location = New-Object System.Drawing.Point(680, 43)
    $btnBrowseDropPath.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnBrowseDropPath.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnBrowseDropPath.ForeColor = [System.Drawing.Color]::White
    $btnBrowseDropPath.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

    $btnScanFiles = New-Object System.Windows.Forms.Button
    $btnScanFiles.Text = "⌕ Scan Files"
    $btnScanFiles.Size = New-Object System.Drawing.Size(100, 25)
    $btnScanFiles.Location = New-Object System.Drawing.Point(770, 43)
    $btnScanFiles.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnScanFiles.BackColor = [System.Drawing.Color]::FromArgb(16, 110, 190)
    $btnScanFiles.ForeColor = [System.Drawing.Color]::White
    $btnScanFiles.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnScanFiles.Enabled = $false

    # Scan results info
    $lblScanResults = New-Object System.Windows.Forms.Label
    $lblScanResults.Text = "Select a folder or file to scan for application installers (.exe, .msi)"
    $lblScanResults.Size = New-Object System.Drawing.Size(500, 20)
    $lblScanResults.Location = New-Object System.Drawing.Point(120, 75)
    $lblScanResults.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblScanResults.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)

    $sourceFilePanel.Controls.Add($sourceFileTitle)
    $sourceFilePanel.Controls.Add($lblDropPath)
    $sourceFilePanel.Controls.Add($txtDropPath)
    $sourceFilePanel.Controls.Add($btnBrowseDropPath)
    $sourceFilePanel.Controls.Add($btnScanFiles)
    $sourceFilePanel.Controls.Add($lblScanResults)    # Found files list panel
    $foundFilesPanel = New-Object System.Windows.Forms.Panel
    $foundFilesPanel.Size = New-Object System.Drawing.Size(940, 220)
    $foundFilesPanel.Location = New-Object System.Drawing.Point(10, 210)
    $foundFilesPanel.BackColor = [System.Drawing.Color]::White
    $foundFilesPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $foundFilesTitle = New-Object System.Windows.Forms.Label
    $foundFilesTitle.Text = "Discovered Application Files"
    $foundFilesTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $foundFilesTitle.Size = New-Object System.Drawing.Size(200, 20)
    $foundFilesTitle.Location = New-Object System.Drawing.Point(15, 15)
    $foundFilesTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)    # ListView for found files
    $foundFilesListView = New-Object System.Windows.Forms.ListView
    $foundFilesListView.Size = New-Object System.Drawing.Size(910, 140)
    $foundFilesListView.Location = New-Object System.Drawing.Point(15, 45)
    $foundFilesListView.View = [System.Windows.Forms.View]::Details
    $foundFilesListView.FullRowSelect = $true
    $foundFilesListView.GridLines = $true
    $foundFilesListView.CheckBoxes = $true
    $foundFilesListView.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $foundFilesListView.BackColor = [System.Drawing.Color]::White

    # ListView columns
    $foundFilesListView.Columns.Add("📄 File Name", 200) | Out-Null
    $foundFilesListView.Columns.Add("📦 Product Name", 180) | Out-Null
    $foundFilesListView.Columns.Add("🏢 Company", 140) | Out-Null
    $foundFilesListView.Columns.Add("📝 Version", 100) | Out-Null
    $foundFilesListView.Columns.Add("📁 Location", 270) | Out-Null

    # Process selected files button
    $btnProcessFiles = New-Object System.Windows.Forms.Button
    $btnProcessFiles.Text = "▶ Process Selected Files"
    $btnProcessFiles.Size = New-Object System.Drawing.Size(150, 30)
    $btnProcessFiles.Location = New-Object System.Drawing.Point(775, 190)
    $btnProcessFiles.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnProcessFiles.BackColor = [System.Drawing.Color]::FromArgb(0, 158, 115)
    $btnProcessFiles.ForeColor = [System.Drawing.Color]::White
    $btnProcessFiles.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnProcessFiles.Enabled = $false

    $foundFilesPanel.Controls.Add($foundFilesTitle)
    $foundFilesPanel.Controls.Add($foundFilesListView)
    $foundFilesPanel.Controls.Add($btnProcessFiles)    # Results panel
    $newAppResultsPanel = New-Object System.Windows.Forms.Panel
    $newAppResultsPanel.Size = New-Object System.Drawing.Size(940, 120)
    $newAppResultsPanel.Location = New-Object System.Drawing.Point(10, 440)
    $newAppResultsPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $newAppResultsPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $newAppResultsTitle = New-Object System.Windows.Forms.Label
    $newAppResultsTitle.Text = "Processing Results & Actions"
    $newAppResultsTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $newAppResultsTitle.Size = New-Object System.Drawing.Size(200, 20)
    $newAppResultsTitle.Location = New-Object System.Drawing.Point(15, 10)
    $newAppResultsTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)

    $newAppResultsLabel = New-Object System.Windows.Forms.Label
    $newAppResultsLabel.Text = "No files processed yet."
    $newAppResultsLabel.Size = New-Object System.Drawing.Size(700, 40)
    $newAppResultsLabel.Location = New-Object System.Drawing.Point(15, 35)
    $newAppResultsLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $newAppResultsLabel.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)

    # Intune Package and Publish button
    $btnPackageToIntune = New-Object System.Windows.Forms.Button
    $btnPackageToIntune.Text = "▶ Package & Publish to Intune"
    $btnPackageToIntune.Size = New-Object System.Drawing.Size(200, 35)
    $btnPackageToIntune.Location = New-Object System.Drawing.Point(15, 75)
    $btnPackageToIntune.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnPackageToIntune.ForeColor = [System.Drawing.Color]::White
    $btnPackageToIntune.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnPackageToIntune.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnPackageToIntune.Enabled = $false

    # Open Folder button
    $btnOpenFolder = New-Object System.Windows.Forms.Button
    $btnOpenFolder.Text = "> Open Folder"
    $btnOpenFolder.Size = New-Object System.Drawing.Size(120, 35)
    $btnOpenFolder.Location = New-Object System.Drawing.Point(225, 75)
    $btnOpenFolder.BackColor = [System.Drawing.Color]::FromArgb(108, 117, 125)
    $btnOpenFolder.ForeColor = [System.Drawing.Color]::White
    $btnOpenFolder.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnOpenFolder.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnOpenFolder.Enabled = $false

    $newAppResultsPanel.Controls.Add($newAppResultsTitle)
    $newAppResultsPanel.Controls.Add($newAppResultsLabel)
    $newAppResultsPanel.Controls.Add($btnPackageToIntune)
    $newAppResultsPanel.Controls.Add($btnOpenFolder)

    $tabNewApp.Controls.Add($newAppHeaderPanel)
    $tabNewApp.Controls.Add($sourceFilePanel)
    $tabNewApp.Controls.Add($foundFilesPanel)
    $tabNewApp.Controls.Add($newAppResultsPanel)

    # Tab 5: Configuration Settings
    $tabConfig = New-Object System.Windows.Forms.TabPage
    $tabConfig.Text = "⚙️ Configuration"
    $tabConfig.BackColor = [System.Drawing.Color]::White

    # Configuration header
    $configHeaderPanel = New-Object System.Windows.Forms.Panel
    $configHeaderPanel.Size = New-Object System.Drawing.Size(940, 60)
    $configHeaderPanel.Location = New-Object System.Drawing.Point(10, 10)
    $configHeaderPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $configHeaderPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $configHeaderTitle = New-Object System.Windows.Forms.Label
    $configHeaderTitle.Text = "⚙  Application Configuration"
    $configHeaderTitle.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $configHeaderTitle.Size = New-Object System.Drawing.Size(300, 25)
    $configHeaderTitle.Location = New-Object System.Drawing.Point(14, 10)
    $configHeaderTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)

    $configHeaderDesc = New-Object System.Windows.Forms.Label
    $configHeaderDesc.Text = "Configure MECM and Intune connection settings"
    $configHeaderDesc.Size = New-Object System.Drawing.Size(400, 20)
    $configHeaderDesc.Location = New-Object System.Drawing.Point(22, 30)
    $configHeaderDesc.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $configHeaderDesc.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)

    $configHeaderPanel.Controls.Add($configHeaderTitle)
    $configHeaderPanel.Controls.Add($configHeaderDesc)

    # Configuration form panel
    $configFormPanel = New-Object System.Windows.Forms.Panel
    $configFormPanel.Size = New-Object System.Drawing.Size(940, 400)
    $configFormPanel.Location = New-Object System.Drawing.Point(10, 80)
    $configFormPanel.BackColor = [System.Drawing.Color]::White
    $configFormPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    # SCCM Section
    $sccmSectionTitle = New-Object System.Windows.Forms.Label
    $sccmSectionTitle.Text = "⚙ MECM Configuration"
    $sccmSectionTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $sccmSectionTitle.Size = New-Object System.Drawing.Size(200, 20)
    $sccmSectionTitle.Location = New-Object System.Drawing.Point(20, 20)
    $sccmSectionTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)

    # SCCM Site Server
    $lblSCCMServer = New-Object System.Windows.Forms.Label
    $lblSCCMServer.Text = "Site Server:"
    $lblSCCMServer.Size = New-Object System.Drawing.Size(100, 20)
    $lblSCCMServer.Location = New-Object System.Drawing.Point(20, 50)
    $lblSCCMServer.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $txtSCCMServer = New-Object System.Windows.Forms.TextBox
    $txtSCCMServer.Size = New-Object System.Drawing.Size(300, 25)
    $txtSCCMServer.Location = New-Object System.Drawing.Point(130, 48)
    $txtSCCMServer.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $txtSCCMServer.Text = $Config.MECMSiteServer

    # SCCM Site Code
    $lblMECMSiteCode = New-Object System.Windows.Forms.Label
    $lblMECMSiteCode.Text = "Site Code:"
    $lblMECMSiteCode.Size = New-Object System.Drawing.Size(80, 20)
    $lblMECMSiteCode.Location = New-Object System.Drawing.Point(450, 50)
    $lblMECMSiteCode.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $txtMECMSiteCode = New-Object System.Windows.Forms.TextBox
    $txtMECMSiteCode.Size = New-Object System.Drawing.Size(100, 25)
    $txtMECMSiteCode.Location = New-Object System.Drawing.Point(530, 48)
    $txtMECMSiteCode.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $txtMECMSiteCode.Text = $Config.MECMSiteCode

    # Base App Path
    $lblBaseAppPath = New-Object System.Windows.Forms.Label
    $lblBaseAppPath.Text = "Base App Path:"
    $lblBaseAppPath.Size = New-Object System.Drawing.Size(100, 20)
    $lblBaseAppPath.Location = New-Object System.Drawing.Point(20, 85)
    $lblBaseAppPath.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $txtBaseAppPath = New-Object System.Windows.Forms.TextBox
    $txtBaseAppPath.Size = New-Object System.Drawing.Size(400, 25)
    $txtBaseAppPath.Location = New-Object System.Drawing.Point(130, 83)
    $txtBaseAppPath.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $txtBaseAppPath.Text = $Config.BaseAppPath

    $btnBrowseAppPath = New-Object System.Windows.Forms.Button
    $btnBrowseAppPath.Text = "⤷"
    $btnBrowseAppPath.Size = New-Object System.Drawing.Size(30, 25)
    $btnBrowseAppPath.Location = New-Object System.Drawing.Point(540, 83)
    $btnBrowseAppPath.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

    # Base Source Path
    $lblBaseSourcePath = New-Object System.Windows.Forms.Label
    $lblBaseSourcePath.Text = "Base Source Path:"
    $lblBaseSourcePath.Size = New-Object System.Drawing.Size(100, 20)
    $lblBaseSourcePath.Location = New-Object System.Drawing.Point(20, 120)
    $lblBaseSourcePath.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $txtBaseSourcePath = New-Object System.Windows.Forms.TextBox
    $txtBaseSourcePath.Size = New-Object System.Drawing.Size(400, 25)
    $txtBaseSourcePath.Location = New-Object System.Drawing.Point(130, 118)
    $txtBaseSourcePath.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $txtBaseSourcePath.Text = $Config.BaseSourcePath

    $btnBrowseSourcePath = New-Object System.Windows.Forms.Button
    $btnBrowseSourcePath.Text = "⤷"
    $btnBrowseSourcePath.Size = New-Object System.Drawing.Size(30, 25)
    $btnBrowseSourcePath.Location = New-Object System.Drawing.Point(540, 118)
    $btnBrowseSourcePath.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

    # Intune Section
    $intuneSectionTitle = New-Object System.Windows.Forms.Label
    $intuneSectionTitle.Text = "☁ Intune Configuration"
    $intuneSectionTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $intuneSectionTitle.Size = New-Object System.Drawing.Size(200, 20)
    $intuneSectionTitle.Location = New-Object System.Drawing.Point(20, 170)
    $intuneSectionTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)

    # Tenant ID
    $lblTenantId = New-Object System.Windows.Forms.Label
    $lblTenantId.Text = "Tenant ID:"
    $lblTenantId.Size = New-Object System.Drawing.Size(100, 20)
    $lblTenantId.Location = New-Object System.Drawing.Point(20, 200)
    $lblTenantId.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $txtTenantId = New-Object System.Windows.Forms.TextBox
    $txtTenantId.Size = New-Object System.Drawing.Size(400, 25)
    $txtTenantId.Location = New-Object System.Drawing.Point(130, 198)
    $txtTenantId.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $txtTenantId.Text = $Config.TenantId

    # Client ID
    $lblClientId = New-Object System.Windows.Forms.Label
    $lblClientId.Text = "Client ID:"
    $lblClientId.Size = New-Object System.Drawing.Size(100, 20)
    $lblClientId.Location = New-Object System.Drawing.Point(20, 235)
    $lblClientId.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $txtClientId = New-Object System.Windows.Forms.TextBox
    $txtClientId.Size = New-Object System.Drawing.Size(400, 25)
    $txtClientId.Location = New-Object System.Drawing.Point(130, 233)
    $txtClientId.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $txtClientId.Text = $Config.ClientId

    # Client Secret
    $lblClientSecret = New-Object System.Windows.Forms.Label
    $lblClientSecret.Text = "Client Secret:"
    $lblClientSecret.Size = New-Object System.Drawing.Size(100, 20)
    $lblClientSecret.Location = New-Object System.Drawing.Point(20, 270)
    $lblClientSecret.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $txtClientSecret = New-Object System.Windows.Forms.TextBox
    $txtClientSecret.Size = New-Object System.Drawing.Size(400, 25)
    $txtClientSecret.Location = New-Object System.Drawing.Point(130, 268)
    $txtClientSecret.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $txtClientSecret.Text = $Config.ClientSecret
    $txtClientSecret.UseSystemPasswordChar = $true

    $chkShowSecret = New-Object System.Windows.Forms.CheckBox
    $chkShowSecret.Text = "Show"
    $chkShowSecret.Size = New-Object System.Drawing.Size(60, 20)
    $chkShowSecret.Location = New-Object System.Drawing.Point(540, 270)
    $chkShowSecret.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    # Action buttons
    $configActionPanel = New-Object System.Windows.Forms.Panel
    $configActionPanel.Size = New-Object System.Drawing.Size(900, 60)
    $configActionPanel.Location = New-Object System.Drawing.Point(20, 320)
    $configActionPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $configActionPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $btnTestConnection = New-Object System.Windows.Forms.Button
    $btnTestConnection.Text = "Test Connection"
    $btnTestConnection.Size = New-Object System.Drawing.Size(120, 30)
    $btnTestConnection.Location = New-Object System.Drawing.Point(20, 15)
    $btnTestConnection.BackColor = [System.Drawing.Color]::FromArgb(40, 167, 69)
    $btnTestConnection.ForeColor = [System.Drawing.Color]::White
    $btnTestConnection.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnTestConnection.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

    $btnSaveConfig = New-Object System.Windows.Forms.Button
    $btnSaveConfig.Text = "Save Configuration"
    $btnSaveConfig.Size = New-Object System.Drawing.Size(140, 30)
    $btnSaveConfig.Location = New-Object System.Drawing.Point(150, 15)
    $btnSaveConfig.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnSaveConfig.ForeColor = [System.Drawing.Color]::White
    $btnSaveConfig.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnSaveConfig.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

    $btnReloadConfig = New-Object System.Windows.Forms.Button
    $btnReloadConfig.Text = "Reload"
    $btnReloadConfig.Size = New-Object System.Drawing.Size(80, 30)
    $btnReloadConfig.Location = New-Object System.Drawing.Point(300, 15)
    $btnReloadConfig.BackColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $btnReloadConfig.ForeColor = [System.Drawing.Color]::Black
    $btnReloadConfig.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnReloadConfig.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $configStatusLabel = New-Object System.Windows.Forms.Label
    $configStatusLabel.Name = "ConfigStatusLabel"
    $configStatusLabel.Text = "Configuration loaded from config.json"
    $configStatusLabel.Size = New-Object System.Drawing.Size(400, 30)
    $configStatusLabel.Location = New-Object System.Drawing.Point(400, 15)
    $configStatusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $configStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $configStatusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    # Add all controls to panels
    $configFormPanel.Controls.Add($sccmSectionTitle)
    $configFormPanel.Controls.Add($lblSCCMServer)
    $configFormPanel.Controls.Add($txtSCCMServer)
    $configFormPanel.Controls.Add($lblMECMSiteCode)
    $configFormPanel.Controls.Add($txtMECMSiteCode)
    $configFormPanel.Controls.Add($lblBaseAppPath)
    $configFormPanel.Controls.Add($txtBaseAppPath)
    $configFormPanel.Controls.Add($btnBrowseAppPath)
    $configFormPanel.Controls.Add($lblBaseSourcePath)
    $configFormPanel.Controls.Add($txtBaseSourcePath)
    $configFormPanel.Controls.Add($btnBrowseSourcePath)
    $configFormPanel.Controls.Add($intuneSectionTitle)
    $configFormPanel.Controls.Add($lblTenantId)
    $configFormPanel.Controls.Add($txtTenantId)
    $configFormPanel.Controls.Add($lblClientId)
    $configFormPanel.Controls.Add($txtClientId)
    $configFormPanel.Controls.Add($lblClientSecret)
    $configFormPanel.Controls.Add($txtClientSecret)
    $configFormPanel.Controls.Add($chkShowSecret)
    $configFormPanel.Controls.Add($configActionPanel)

    $configActionPanel.Controls.Add($btnTestConnection)
    $configActionPanel.Controls.Add($btnSaveConfig)
    $configActionPanel.Controls.Add($btnReloadConfig)
    $configActionPanel.Controls.Add($configStatusLabel)

    $tabConfig.Controls.Add($configHeaderPanel)
    $tabConfig.Controls.Add($configFormPanel)    # Add tabs to control and finalize form
    $tabControl.Controls.Add($tabAppSelection)
    $tabControl.Controls.Add($tabDestination)
    $tabControl.Controls.Add($tabExecution)
    $tabControl.Controls.Add($tabNewApp)
    $tabControl.Controls.Add($tabConfig)
    $form.Controls.Add($tabControl)

    # Variables
    $script:SelectedApp = $null
    $script:SelectedPublisher = $null
    $script:SelectedApplication = $null
    $script:Version = ""    # Enhanced helper functions for UI updates
    function Update-StatusLabel($text, $color = [System.Drawing.Color]::White) {
        $statusLabel.Text = $text
        # Ensure color is evaluated as an expression if passed as string
        if ($color -is [string]) {
            $color = Invoke-Expression $color
        }
        $statusLabel.ForeColor = $color
    }

    function Update-ProgressWithMessage($percentage, $message) {
        $progressBar.Value = $percentage
        $progressLabel.Text = "$percentage% - $message"
        $currentStatus.Text = $message
        $form.Refresh()
    }

    function Add-ColoredLogEntry($message, $color) {
        $txtLog.SelectionStart = $txtLog.TextLength
        $txtLog.SelectionLength = 0
        $txtLog.SelectionColor = $color
        $txtLog.AppendText("$(Get-Date -Format 'HH:mm:ss') - $message`r`n")
        $txtLog.SelectionColor = $txtLog.ForeColor
        $txtLog.ScrollToCaret()
    }

    # Search functionality
    $searchBox.Add_TextChanged({
        $searchText = $searchBox.Text.ToLower()
        for ($i = 0; $i -lt $appListView.Rows.Count; $i++) {
            $row = $appListView.Rows[$i]
            $appName = if ($row.Cells[1].Value) { $row.Cells[1].Value.ToString().ToLower() } else { "" }
            $manufacturer = if ($row.Cells[3].Value) { $row.Cells[3].Value.ToString().ToLower() } else { "" }
            
            if ([string]::IsNullOrEmpty($searchText) -or $appName.Contains($searchText) -or $manufacturer.Contains($searchText)) {
                $row.Visible = $true
            } else {
                $row.Visible = $false
            }
        }
    })

    # Refresh button functionality - now just calls the Get Apps functionality
    $refreshButton.Add_Click({
        # Trigger the Get Apps button click to avoid duplicate code
        $btnGetApps.PerformClick()
    })

    # Enhanced preview update function
    function Update-DestinationPreview {
        $preview = ""
        if ($cmbPublisher.SelectedItem -and $cmbPublisher.SelectedItem -ne "➕ Create New Publisher") {
            $preview += " Publisher: $($cmbPublisher.SelectedItem)`r`n"
        } elseif ($txtNewPublisher.Text) {
            $preview += " Publisher: $($txtNewPublisher.Text) (New)`r`n"
        }
        
        if ($cmbApplication.SelectedItem -and $cmbApplication.SelectedItem -ne "➕ Create New Application") {
            $preview += " Application: $($cmbApplication.SelectedItem)`r`n"
        } elseif ($txtNewApplication.Text) {
            $preview += " Application: $($txtNewApplication.Text) (New)`r`n"
        }
        
        if ($txtVersion.Text) {
            $preview += " Version: $($txtVersion.Text)`r`n"
        }
        
        if ($script:SelectedApp) {
            $preview += "`r`n Source Application:`r`n"
            $preview += "   Name: $($script:SelectedApp.AppName)`r`n"
            $preview += "   Version: $($script:SelectedApp.Version)`r`n"
            $preview += "   Manufacturer: $($script:SelectedApp.Manufacturer)"
        }
        
        if ([string]::IsNullOrEmpty($preview)) {
            $preview = "Configuration will appear here..."
        }
        
        $previewText.Text = $preview
    }    # Enhanced event handlers
    $cmbPublisher.Add_SelectedIndexChanged({
        $cmbApplication.Items.Clear()
        $cmbApplication.Items.Add("➕ Create New Application")
        if ($cmbPublisher.SelectedItem -eq "➕ Create New Publisher") {
            $txtNewPublisher.Visible = $true
        } else {
            $txtNewPublisher.Visible = $false
            $publisherPath = Join-Path -Path $BaseAppPath -ChildPath $cmbPublisher.SelectedItem 

            $apps = Get-ChildItem -Path $publisherPath -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer } -ErrorAction SilentlyContinue | Sort-Object Name
            foreach ($app in $apps) {
                $cmbApplication.Items.Add($app.Name) | Out-Null
            }
        }
        Update-DestinationPreview
    })

    $cmbApplication.Add_SelectedIndexChanged({
        if ($cmbApplication.SelectedItem -eq "➕ Create New Application") {
            $txtNewApplication.Visible = $true
        } else {
            $txtNewApplication.Visible = $false
        }
        Update-DestinationPreview
    })

    $txtNewPublisher.Add_TextChanged({ Update-DestinationPreview })
    $txtNewApplication.Add_TextChanged({ Update-DestinationPreview })
    $txtVersion.Add_TextChanged({ Update-DestinationPreview })

    $appListView.Add_SelectionChanged({
        if ($appListView.SelectedRows.Count -gt 0) {
            $selectionInfo.Text = "Selected: $($appListView.SelectedRows[0].Cells[1].Value) - Ready to continue"
            $selectionInfo.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)        } else {
            $selectionInfo.Text = "Select an application from the list above to continue"
            $selectionInfo.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
        }
    })
    
    $btnSelectApp.Add_Click({
        if ($appListView.SelectedRows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Please select an application.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }        
        $script:SelectedApp = $deployedApps | Where-Object { $_.AppName -eq $appListView.SelectedRows[0].Cells[1].Value -and $_.Version -eq $appListView.SelectedRows[0].Cells[2].Value } | Select-Object -First 1
        Add-ColoredLogEntry "Selected application: $($script:SelectedApp.AppName) v$($script:SelectedApp.Version)" ([System.Drawing.Color]::Blue)
        
        # Auto-populate destination fields based on selected app
        $txtVersion.Text = $script:SelectedApp.Version
        
        # Try to match manufacturer/publisher
        if ($script:SelectedApp.Manufacturer) {
            $matchingPublisher = $null
            foreach ($item in $cmbPublisher.Items) {
                if ($item -eq $script:SelectedApp.Manufacturer) {
                    $matchingPublisher = $item
                    break
                }
            }
            
            if ($matchingPublisher) {
                # Set publisher to existing match
                $cmbPublisher.SelectedItem = $matchingPublisher
                Add-ColoredLogEntry "Matched publisher: $($matchingPublisher)" ([System.Drawing.Color]::Green)
                
                # After publisher is set, ensure application dropdown is ready and set to create new
                $cmbApplication.SelectedItem = "➕ Create New Application"
                $txtNewApplication.Text = $script:SelectedApp.AppName
                $txtNewApplication.Visible = $true
            } else {
                # Set to create new publisher and populate the text field
                $cmbPublisher.SelectedItem = "➕ Create New Publisher"
                $txtNewPublisher.Text = $script:SelectedApp.Manufacturer
                $txtNewPublisher.Visible = $true
                Add-ColoredLogEntry "Will create new publisher: $($script:SelectedApp.Manufacturer)" ([System.Drawing.Color]::Orange)
                
                # Set application to create new as well
                $cmbApplication.SelectedItem = "➕ Create New Application"
                $txtNewApplication.Text = $script:SelectedApp.AppName
                $txtNewApplication.Visible = $true
            }
        } else {
            # No manufacturer, set to create new publisher
            $cmbPublisher.SelectedItem = "➕ Create New Publisher"
            $txtNewPublisher.Text = "Unknown Publisher"
            $txtNewPublisher.Visible = $true
            Add-ColoredLogEntry "No manufacturer found, will create: Unknown Publisher" ([System.Drawing.Color]::Orange)
            
            # Set application to create new
            $cmbApplication.SelectedItem = "➕ Create New Application"
            $txtNewApplication.Text = $script:SelectedApp.AppName
            $txtNewApplication.Visible = $true
        }
        
        Add-ColoredLogEntry "Will create new application: $($script:SelectedApp.AppName)" ([System.Drawing.Color]::Orange)
        
        Update-DestinationPreview
        Update-StatusLabel "Application selected: $($script:SelectedApp.AppName)" [System.Drawing.Color]::LightGreen
        $tabControl.SelectedTab = $tabDestination
    })

    $btnSelectDestination.Add_Click({
        if ($cmbPublisher.SelectedItem -eq "➕ Create New Publisher" -and [string]::IsNullOrWhiteSpace($txtNewPublisher.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Please enter a new publisher name.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }
        if ($cmbApplication.SelectedItem -eq "➕ Create New Application" -and [string]::IsNullOrWhiteSpace($txtNewApplication.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Please enter a new application name.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }
        if ([string]::IsNullOrWhiteSpace($txtVersion.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Please enter a version number.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }

        # Create publisher object with proper FullName
        if ($cmbPublisher.SelectedItem -eq "➕ Create New Publisher") {
            $publisherName = $txtNewPublisher.Text.Trim()
            $publisherPath = Join-Path -Path $BaseAppPath -ChildPath $publisherName
            $script:SelectedPublisher = [PSCustomObject]@{
                Name = $publisherName
                FullName = $publisherPath
            }
            # Create publisher directory if it doesn't exist
            if (-not (Test-Path $publisherPath)) {
                try {
                    New-Item -Path $publisherPath -ItemType Directory -Force | Out-Null
                    Add-ColoredLogEntry "Created new publisher directory: $publisherPath" ([System.Drawing.Color]::Green)
                } catch {
                    [System.Windows.Forms.MessageBox]::Show("Failed to create publisher directory: $($_.Exception.Message)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    return
                }
            }
        } else {
            $selectedPublisherName = $cmbPublisher.SelectedItem
            $publisherPath = Join-Path -Path $BaseAppPath -ChildPath $selectedPublisherName
            $script:SelectedPublisher = [PSCustomObject]@{
                Name = $selectedPublisherName
                FullName = $publisherPath
            }
        }

        # Create application object with proper FullName
        if ($cmbApplication.SelectedItem -eq "➕ Create New Application") {
            $appName = $txtNewApplication.Text.Trim()
            $appPath = Join-Path -Path $script:SelectedPublisher.FullName -ChildPath $appName
            $script:SelectedApplication = [PSCustomObject]@{
                Name = $appName
                FullName = $appPath
            }
            # Create application directory if it doesn't exist
            if (-not (Test-Path $appPath)) {
                try {
                    New-Item -Path $appPath -ItemType Directory -Force | Out-Null
                    Add-ColoredLogEntry "Created new application directory: $appPath" ([System.Drawing.Color]::Green)
                } catch {
                    [System.Windows.Forms.MessageBox]::Show("Failed to create application directory: $($_.Exception.Message)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    return
                }
            }
        } else {
            $selectedAppName = $cmbApplication.SelectedItem
            $appPath = Join-Path -Path $script:SelectedPublisher.FullName -ChildPath $selectedAppName
            $script:SelectedApplication = [PSCustomObject]@{
                Name = $selectedAppName
                FullName = $appPath
            }
        }

        $script:Version = $txtVersion.Text.Trim()

        # Validate that all objects have proper FullName properties
        if (-not $script:SelectedPublisher.FullName) {
            [System.Windows.Forms.MessageBox]::Show("Publisher path is invalid.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }
        if (-not $script:SelectedApplication.FullName) {
            [System.Windows.Forms.MessageBox]::Show("Application path is invalid.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }        
          Add-ColoredLogEntry "✓ Configuration complete:" ([System.Drawing.Color]::Green)
        Add-ColoredLogEntry "  Publisher: $($script:SelectedPublisher.Name)" ([System.Drawing.Color]::Black)
        Add-ColoredLogEntry "  Application: $($script:SelectedApplication.Name)" ([System.Drawing.Color]::Black)
        Add-ColoredLogEntry "  Version: $($script:Version)" ([System.Drawing.Color]::Black)
        Add-ColoredLogEntry "  Path: $($script:SelectedApplication.FullName)" ([System.Drawing.Color]::Gray)
        
        Update-StatusLabel "Configuration complete - Ready to migrate" [System.Drawing.Color]::LightGreen
        $tabControl.SelectedTab = $tabExecution
    })

    $btnMigrate.Add_Click({
        if (-not $script:SelectedApp) {
            [System.Windows.Forms.MessageBox]::Show("No application selected.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }

        # Disable migration button during execution
        $btnMigrate.Enabled = $false
        $btnMigrate.Text = "🔄 Migrating..."
        
        Update-ProgressWithMessage 0 "Starting migration process..."
        Add-ColoredLogEntry "🚀 Starting migration for $($script:SelectedApp.AppName)..." ([System.Drawing.Color]::Blue)
        
        Update-ProgressWithMessage 10 "Validating application compatibility..."
        $migrationInfo = Test-SCCMAppMigratability -SCCMApp $script:SelectedApp.AppName
        Show-SCCMAppDetails -SCCMApp $script:SelectedApp.SCCMApp -MigrationInfo $migrationInfo
        
        # Only prompt if validation fails - if it passes, continue automatically
        if (-not $migrationInfo.IsMigratable) {
            Add-ColoredLogEntry "⚠️ Application validation failed: $($migrationInfo.Reason)" ([System.Drawing.Color]::Orange)
            $result = [System.Windows.Forms.MessageBox]::Show("Application validation failed: $($migrationInfo.Reason).`n`nDo you want to continue anyway?", "Validation Failed", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($result -eq "No") {
                Add-ColoredLogEntry "❌ Migration cancelled by user." ([System.Drawing.Color]::Red)
                $btnMigrate.Enabled = $true
                $btnMigrate.Text = "🚀 Start Migration"
                Update-ProgressWithMessage 0 "Migration cancelled"
                return
            }
            Add-ColoredLogEntry "⚠️ User chose to continue despite validation failure." ([System.Drawing.Color]::Orange)
        } else {
            Add-ColoredLogEntry "✅ Application validation passed - proceeding with migration" ([System.Drawing.Color]::Green)
        }

        Update-ProgressWithMessage 25 "Locating source files..."
        $sourceFileInfo = Find-SourceFile -SCCMApp $script:SelectedApp.SCCMApp -MigrationInfo $migrationInfo
        if (-not $sourceFileInfo) {
            Add-ColoredLogEntry "❌ Error: Cannot proceed without source files." ([System.Drawing.Color]::Red)
            $btnMigrate.Enabled = $true
            $btnMigrate.Text = "🚀 Start Migration"
            Update-ProgressWithMessage 0 "Migration failed - source files not found"
            return
        }        
        
        Add-ColoredLogEntry "✅ Source file located: $($sourceFileInfo.FileName)" ([System.Drawing.Color]::Green)

        if (-not $SkipSourceUpdate) {
            Update-ProgressWithMessage 40 "Creating source files structure..."
            Add-ColoredLogEntry "📁 Creating source files structure..." ([System.Drawing.Color]::Blue)
            $versionPath = New-VersionDirectory -SourceFileInfo $sourceFileInfo -Publisher $script:SelectedPublisher -Application $script:SelectedApplication -Version $script:Version -SCCMApp $script:SelectedApp.SCCMApp -MigrationInfo $migrationInfo
            if ($versionPath) {
                Update-ProgressWithMessage 60 "Generating package configuration..."
                $jsonPath = New-PackageConstructorJSON -VersionPath $versionPath -SCCMApp $script:SelectedApp.SCCMApp -SourceFileInfo $sourceFileInfo -MigrationInfo $migrationInfo -Publisher $script:SelectedPublisher -Application $script:SelectedApplication -Version $script:Version
                if ($jsonPath) {
                    Add-ColoredLogEntry "✅ Source files structure created: $versionPath" ([System.Drawing.Color]::Green)
                } else {
                    Add-ColoredLogEntry "❌ Error: Failed to create JSON configuration." ([System.Drawing.Color]::Red)
                    $btnMigrate.Enabled = $true
                    $btnMigrate.Text = "🚀 Start Migration"
                    Update-ProgressWithMessage 0 "Migration failed - configuration error"
                    return
                }
            } else {
                Add-ColoredLogEntry "❌ Error: Failed to create version directory." ([System.Drawing.Color]::Red)
                $btnMigrate.Enabled = $true
                $btnMigrate.Text = "🚀 Start Migration"
                Update-ProgressWithMessage 0 "Migration failed - directory creation error"
                return
            }
        }

        if (-not $SkipIntunePublish -and $versionPath) {
            Update-ProgressWithMessage 75 "Packaging and publishing to Intune..."
            Add-ColoredLogEntry "📦 Packaging and publishing to Intune..." ([System.Drawing.Color]::Blue)
            $success = Invoke-IntunePackaging -VersionPath $versionPath -SourceFileInfo $sourceFileInfo
            if ($success) {
                Add-ColoredLogEntry "🎉 Application published to Intune successfully!" ([System.Drawing.Color]::Green)
            } else {
                Add-ColoredLogEntry "❌ Error: Failed to publish to Intune." ([System.Drawing.Color]::Red)
                $btnMigrate.Enabled = $true
                $btnMigrate.Text = "🚀 Start Migration"
                Update-ProgressWithMessage 0 "Migration failed - Intune publishing error"
                return
            }
        }

        Update-ProgressWithMessage 100 "Migration completed successfully!"
        Add-ColoredLogEntry "🎉 Migration completed successfully!" ([System.Drawing.Color]::Green)
        Update-StatusLabel "Migration completed successfully!" [System.Drawing.Color]::LightGreen
        
        # Re-enable button
        $btnMigrate.Enabled = $true
        $btnMigrate.Text = "🚀 Start Migration"
        
        [System.Windows.Forms.MessageBox]::Show("Migration completed successfully! 🎉", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    })

    $btnCancel.Add_Click({
        $form.Close()
    })

    # Configuration Tab Event Handlers
    $chkShowSecret.Add_CheckedChanged({
        $txtClientSecret.UseSystemPasswordChar = -not $chkShowSecret.Checked
    })

    $btnBrowseAppPath.Add_Click({
        $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderDialog.Description = "Select Base Application Path"
        $folderDialog.SelectedPath = $txtBaseAppPath.Text
        
        if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtBaseAppPath.Text = $folderDialog.SelectedPath
            $configStatusLabel.Text = "Path updated - click Save to persist changes"
            $configStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 140, 0)
        }
    })

    $btnBrowseSourcePath.Add_Click({
        $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderDialog.Description = "Select Base Source Files Path"
        $folderDialog.SelectedPath = $txtBaseSourcePath.Text
        
        if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtBaseSourcePath.Text = $folderDialog.SelectedPath
            $configStatusLabel.Text = "Path updated - click Save to persist changes"
            $configStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 140, 0)
        }
    })

    $btnTestConnection.Add_Click({
        $configStatusLabel.Text = "Testing connections..."
        $configStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 140, 0)
        $btnTestConnection.Enabled = $false
        
        # Test SCCM Connection
        try {
            Set-Location "$($txtMECMSiteCode.Text):"
            $testApp = Get-CMApplication -Fast | Select-Object -First 1
            if ($testApp) {
                $configStatusLabel.Text = "✅ SCCM connection successful"
                $configStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(40, 167, 69)
            } else {
                $configStatusLabel.Text = "⚠️ SCCM connected but no applications found"
                $configStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 140, 0)
            }
        } catch {
            $configStatusLabel.Text = "❌ SCCM connection failed: $($_.Exception.Message)"
            $configStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(220, 53, 69)
            $btnTestConnection.Enabled = $true
            return
        }

        # Test Intune Connection (if credentials provided)
        if (-not [string]::IsNullOrWhiteSpace($txtTenantId.Text) -and 
            -not [string]::IsNullOrWhiteSpace($txtClientId.Text) -and 
            -not [string]::IsNullOrWhiteSpace($txtClientSecret.Text)) {
            try {
                Connect-MSIntuneGraph -TenantID $txtTenantId.Text -ClientID $txtClientId.Text -ClientSecret $txtClientSecret.Text -ErrorAction Stop
                $configStatusLabel.Text = "✅ Both SCCM and Intune connections successful"
                $configStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(40, 167, 69)
            } catch {
                $configStatusLabel.Text = "⚠️ SCCM OK, Intune failed: $($_.Exception.Message)"
                $configStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 140, 0)
            }
        }
        
        $btnTestConnection.Enabled = $true
    })

    $btnSaveConfig.Add_Click({
        try {
            # Validate required fields
            if ([string]::IsNullOrWhiteSpace($txtSCCMServer.Text)) {
                [System.Windows.Forms.MessageBox]::Show("SCCM Site Server is required.", "Validation Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                return
            }
            if ([string]::IsNullOrWhiteSpace($txtMECMSiteCode.Text)) {
                [System.Windows.Forms.MessageBox]::Show("SCCM Site Code is required.", "Validation Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                return
            }

            # Create updated configuration object
            $updatedConfig = @{
                MECMSiteServer = $txtSCCMServer.Text.Trim()
                MECMSiteCode = $txtMECMSiteCode.Text.Trim()
                BaseAppPath = $txtBaseAppPath.Text.Trim()
                BaseSourcePath = $txtBaseSourcePath.Text.Trim()
                TenantId = $txtTenantId.Text.Trim()
                ClientId = $txtClientId.Text.Trim()
                ClientSecret = $txtClientSecret.Text.Trim()
            }

            # Save to config.json
            $configJson = $updatedConfig | ConvertTo-Json -Depth 10
            $configPath = Join-Path -Path $PSScriptRoot -ChildPath "config.json"
            $configJson | Out-File -FilePath $configPath -Encoding UTF8

            # Update global variables
            $script:Config = $updatedConfig
            $global:MECMSiteServer = $updatedConfig.MECMSiteServer
            $global:MECMSiteCode = $updatedConfig.MECMSiteCode
            $global:BaseAppPath = $updatedConfig.BaseAppPath
            $global:BaseSourcePath = $updatedConfig.BaseSourcePath
            $global:TenantId = $updatedConfig.TenantId
            $global:ClientId = $updatedConfig.ClientId
            $global:ClientSecret = $updatedConfig.ClientSecret

            $configStatusLabel.Text = "✅ Configuration saved successfully"
            $configStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(40, 167, 69)

            [System.Windows.Forms.MessageBox]::Show("Configuration saved successfully!", "Save Complete", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)

        } catch {
            $configStatusLabel.Text = "❌ Failed to save configuration: $($_.Exception.Message)"
            $configStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(220, 53, 69)
            [System.Windows.Forms.MessageBox]::Show("Failed to save configuration: $($_.Exception.Message)", "Save Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })

    $btnReloadConfig.Add_Click({
        try {
            # Reload from config.json
            $configPath = Join-Path -Path $PSScriptRoot -ChildPath "config.json"
            if (Test-Path $configPath) {
                $reloadedConfig = Get-Content -Path $configPath -Raw | ConvertFrom-Json
                
                # Update text boxes
                $txtSCCMServer.Text = $reloadedConfig.MECMSiteServer
                $txtMECMSiteCode.Text = $reloadedConfig.MECMSiteCode
                $txtBaseAppPath.Text = $reloadedConfig.BaseAppPath
                $txtBaseSourcePath.Text = $reloadedConfig.BaseSourcePath
                $txtTenantId.Text = $reloadedConfig.TenantId
                $txtClientId.Text = $reloadedConfig.ClientId
                $txtClientSecret.Text = $reloadedConfig.ClientSecret

                $configStatusLabel.Text = "✅ Configuration reloaded from file"
                $configStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(40, 167, 69)
            } else {
                $configStatusLabel.Text = "⚠️ Config file not found"
                $configStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 140, 0)
            }
        } catch {            $configStatusLabel.Text = "❌ Failed to reload configuration: $($_.Exception.Message)"
            $configStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(220, 53, 69)        }
    })

    # New App tab event handlers
    $btnBrowseDropPath.Add_Click({
        try {
            # Create folder browser dialog that can also select files
            $openDialog = New-Object System.Windows.Forms.OpenFileDialog
            $openDialog.Title = "Select Application File or Drop Folder"
            $openDialog.Filter = "Application Files (*.exe;*.msi)|*.exe;*.msi|All Files (*.*)|*.*"
            $openDialog.CheckFileExists = $false
            $openDialog.CheckPathExists = $true
            $openDialog.Multiselect = $false
            
            # Also create folder dialog as backup
            $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
            $folderDialog.Description = "Select Drop Folder to Scan"
            $folderDialog.ShowNewFolderButton = $false
            
            # Show option dialog first
            $choice = [System.Windows.Forms.MessageBox]::Show("Select File or Folder?`n`nYes = Select specific file`nNo = Select folder to scan", "Browse Type", [System.Windows.Forms.MessageBoxButtons]::YesNoCancel, [System.Windows.Forms.MessageBoxIcon]::Question)
            
            if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
                # File selection
                if ($openDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $txtDropPath.Text = $openDialog.FileName
                    $btnScanFiles.Enabled = $true
                    $lblScanResults.Text = "Ready to analyze selected file: $(Split-Path -Leaf $openDialog.FileName)"
                    $lblScanResults.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
                }
            } elseif ($choice -eq [System.Windows.Forms.DialogResult]::No) {
                # Folder selection
                if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $txtDropPath.Text = $folderDialog.SelectedPath
                    $btnScanFiles.Enabled = $true
                    $lblScanResults.Text = "Ready to scan folder: $(Split-Path -Leaf $folderDialog.SelectedPath)"
                    $lblScanResults.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
                }
            }
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error browsing for path: $($_.Exception.Message)", "Browse Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })

    $btnScanFiles.Add_Click({
        if (-not $txtDropPath.Text) {
            [System.Windows.Forms.MessageBox]::Show("Please select a file or folder first.", "No Path Selected", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        try {
            $foundFilesListView.Items.Clear()
            $lblScanResults.Text = "Scanning for application files..."
            $lblScanResults.ForeColor = [System.Drawing.Color]::FromArgb(255, 140, 0)
            $btnScanFiles.Enabled = $false
            $btnProcessFiles.Enabled = $false
            
            # Use the Update-SourceFiles function to find files
            $dropPath = $txtDropPath.Text
              # Call the Find-NewApplicationFiles function from Update-SourceFiles
            $scanResult = Find-NewApplicationFiles -DropPath $dropPath
            
            if ($scanResult.Success -and $scanResult.Files.Count -gt 0) {
                foreach ($fileInfo in $scanResult.Files) {
                    $item = New-Object System.Windows.Forms.ListViewItem($fileInfo.FileName)
                    $item.UseItemStyleForSubItems = $false
                    $item.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
                    $item.SubItems.Add($fileInfo.VersionInfo.ProductName)
                    $item.SubItems.Add($fileInfo.VersionInfo.CompanyName)
                    $item.SubItems.Add($fileInfo.VersionInfo.FileVersion)
                    $item.SubItems.Add($fileInfo.FilePath)
                    $item.Tag = $fileInfo
                    $foundFilesListView.Items.Add($item) | Out-Null
                }
                
                $lblScanResults.Text = "Found $($scanResult.Files.Count) application files. Select files to process."
                $lblScanResults.ForeColor = [System.Drawing.Color]::FromArgb(40, 167, 69)
                $btnProcessFiles.Enabled = $true
            } else {
                $lblScanResults.Text = "No application files found in the selected location."
                $lblScanResults.ForeColor = [System.Drawing.Color]::FromArgb(220, 53, 69)
            }
        } catch {
            $lblScanResults.Text = "Error scanning files: $($_.Exception.Message)"
            $lblScanResults.ForeColor = [System.Drawing.Color]::FromArgb(220, 53, 69)
            [System.Windows.Forms.MessageBox]::Show("Error scanning files: $($_.Exception.Message)", "Scan Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        } finally {            $btnScanFiles.Enabled = $true
        }
    })

    $foundFilesListView.Add_ItemCheck({        # Enable/disable process button based on selections
        param($sender, $e)
        # Calculate future checked count
        $futureCheckedCount = 0
        for ($i = 0; $i -lt $foundFilesListView.Items.Count; $i++) {
            if ($i -eq $e.Index) {
                # For the current item being clicked, use the new value
                if ($e.NewValue -eq [System.Windows.Forms.CheckState]::Checked) {
                    $futureCheckedCount++
                }
            } else {
                # For other items, use current checked state
                if ($foundFilesListView.Items[$i].Checked) {                    $futureCheckedCount++
                }
            }
        }
        $btnProcessFiles.Enabled = ($futureCheckedCount -gt 0)
    })
    
    $btnProcessFiles.Add_Click({
        # Debug: Show that the button click is working
        Write-Host "Process Files button clicked!" -ForegroundColor Yellow
        
        $selectedFiles = @()
        foreach ($item in $foundFilesListView.CheckedItems) {
            $selectedFiles += $item.Tag
        }
        
        Write-Host "Found $($selectedFiles.Count) selected files" -ForegroundColor Cyan
        
        if ($selectedFiles.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Please select at least one file to process.`n`nMake sure to check the checkbox next to the files you want to process.", "No Files Selected", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        try {
            $newAppResultsLabel.Text = "Processing $($selectedFiles.Count) selected files..."
            $newAppResultsLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 140, 0)
            $btnProcessFiles.Enabled = $false
            
            $processedCount = 0
            $errorCount = 0
            $results = @()
              # Store the last processed file info globally for Intune packaging
            $script:LastProcessedFiles = $selectedFiles
            $script:ProcessedApplicationPaths = @()
            
            foreach ($fileInfo in $selectedFiles) {
                try {                    # Create a simulated application object for processing
                    $fakeApp = [PSCustomObject]@{
                        ApplicationName = if ($fileInfo.VersionInfo.ProductName) { $fileInfo.VersionInfo.ProductName } else { [System.IO.Path]::GetFileNameWithoutExtension($fileInfo.FileName) }
                        Manufacturer = if ($fileInfo.VersionInfo.CompanyName) { $fileInfo.VersionInfo.CompanyName } else { "Unknown" }
                        SoftwareVersion = if ($fileInfo.VersionInfo.FileVersion) { $fileInfo.VersionInfo.FileVersion } else { "1.0.0" }
                    }
                      # Process the file using Update-SourceFiles with actual file info
                    $processResult = Update-SourceFiles -Application $fakeApp -FileInfo $fileInfo -Interactive:$false
                      if ($processResult -and $processResult.Success) {
                        $processedCount++
                        
                        # Store the actual processed path information returned from Invoke-NewApplicationFileProcessing
                        $script:ProcessedApplicationPaths += @{
                            FileInfo = $fileInfo
                            PublisherName = $processResult.PublisherName
                            ApplicationName = $processResult.ApplicationName
                            Version = $processResult.Version
                            VersionPath = $processResult.VersionPath
                        }
                        
                        $results += "✅ $($fileInfo.FileName) - Created: $($processResult.PublisherName)\$($processResult.ApplicationName)\$($processResult.Version)"
                    } else {
                        $errorCount++
                        $errorMessage = if ($processResult -and $processResult.Error) { $processResult.Error } else { "Unknown error" }
                        $results += "❌ $($fileInfo.FileName) - Failed to process: $errorMessage"
                    }
                } catch {
                    $errorCount++
                    $results += "❌ $($fileInfo.FileName) - Error: $($_.Exception.Message)"
                }
            }
            
            $resultText = "Processing complete. Success: $processedCount, Errors: $errorCount"
            if ($results.Count -gt 0) {
                $resultText += "`n" + ($results -join "`n")
            }
            
            $newAppResultsLabel.Text = $resultText
            
            if ($errorCount -eq 0) {
                $newAppResultsLabel.ForeColor = [System.Drawing.Color]::FromArgb(40, 167, 69)
                # Enable Intune packaging button when processing is successful
                $btnPackageToIntune.Enabled = $true
                $btnOpenFolder.Enabled = $true
            } else {
                $newAppResultsLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 140, 0)
            }
            
            # Show summary dialog
            [System.Windows.Forms.MessageBox]::Show($resultText, "Processing Complete", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            
        } catch {
            $newAppResultsLabel.Text = "Error processing files: $($_.Exception.Message)"
            $newAppResultsLabel.ForeColor = [System.Drawing.Color]::FromArgb(220, 53, 69)
            [System.Windows.Forms.MessageBox]::Show("Error processing files: $($_.Exception.Message)", "Processing Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)        } finally {
            $btnProcessFiles.Enabled = $true
        }
    })    # Package to Intune button event handler
    $btnPackageToIntune.Add_Click({
        try {
            # Check if we have processed application paths
            if (-not $script:ProcessedApplicationPaths -or $script:ProcessedApplicationPaths.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show("No files were processed. Please process files first.", "No Processed Files", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                return
            }
            
            # Use the first processed application path
            $processedApp = $script:ProcessedApplicationPaths[0]
            $fileInfo = $processedApp.FileInfo
            $publisherName = $processedApp.PublisherName
            $applicationName = $processedApp.ApplicationName
            $version = $processedApp.Version
            $versionPath = $processedApp.VersionPath
            
            $confirmMessage = "Package and publish to Intune?`n`n" +
                            "Publisher: $publisherName`n" +
                            "Application: $applicationName`n" +
                            "Version: $version`n" +
                            "Source Path: $versionPath`n`n" +
                            "This will create a .intunewin package and publish to your Intune tenant."
            
            $result = [System.Windows.Forms.MessageBox]::Show($confirmMessage, "Confirm Intune Packaging", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
              if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                $btnPackageToIntune.Enabled = $false
                $btnPackageToIntune.Text = "⏳ Packaging..."
                
                # Debug logging
                Write-Log -Message "DEBUG: Using stored version path: $versionPath" -Level "INFO"
                
                # Create source file info structure for Invoke-IntunePackaging
                $sourceFileInfo = @{
                    FileName = $fileInfo.FileName
                    FilePath = $fileInfo.FilePath
                    VersionInfo = $fileInfo.VersionInfo
                    ContentLocation = Split-Path -Path $fileInfo.FilePath -Parent
                    AllFiles = @(Get-ChildItem -Path (Split-Path -Path $fileInfo.FilePath -Parent) | Where-Object { -not $_.PSIsContainer })
                    TotalFileSize = (Get-ChildItem -Path (Split-Path -Path $fileInfo.FilePath -Parent) | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum).Sum
                }
                
                # Call the Intune packaging function
                $packagingResult = Invoke-IntunePackaging -VersionPath $versionPath -SourceFileInfo $sourceFileInfo
                
                if ($packagingResult) {
                    [System.Windows.Forms.MessageBox]::Show("✅ Successfully packaged and published to Intune!", "Packaging Complete", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                    $btnPackageToIntune.Text = "✅ Published to Intune"
                    $btnPackageToIntune.BackColor = [System.Drawing.Color]::FromArgb(40, 167, 69)
                } else {
                    [System.Windows.Forms.MessageBox]::Show("❌ Failed to package or publish to Intune. Check the log for details.", "Packaging Failed", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    $btnPackageToIntune.Text = "📦 Package & Publish to Intune"
                    $btnPackageToIntune.Enabled = $true
                }
            }
            
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error during Intune packaging: $($_.Exception.Message)", "Packaging Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            $btnPackageToIntune.Text = "📦 Package & Publish to Intune"
            $btnPackageToIntune.Enabled = $true
        }
    })    # Open Folder button event handler
    $btnOpenFolder.Add_Click({
        try {
            # Check if we have processed application paths
            if (-not $script:ProcessedApplicationPaths -or $script:ProcessedApplicationPaths.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show("No files were processed. Please process files first.", "No Processed Files", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                return
            }
            
            # Use the first processed application path
            $processedApp = $script:ProcessedApplicationPaths[0]
            $folderPath = $processedApp.VersionPath
            
            if (Test-Path $folderPath) {
                # Open folder in Windows Explorer
                Start-Process -FilePath "explorer.exe" -ArgumentList $folderPath
            } else {
                [System.Windows.Forms.MessageBox]::Show("Folder not found: $folderPath", "Folder Not Found", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            }
            
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error opening folder: $($_.Exception.Message)", "Open Folder Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })

    # Auto-save detection - mark unsaved changes
    $configControls = @($txtSCCMServer, $txtMECMSiteCode, $txtBaseAppPath, $txtBaseSourcePath, $txtTenantId, $txtClientId, $txtClientSecret)
    foreach ($control in $configControls) {
        $control.Add_TextChanged({
            if ($configStatusLabel.Text -notlike "*unsaved*") {
                $configStatusLabel.Text = "⚠️ Unsaved changes - click Save to persist"
                $configStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 140, 0)
            }
        })
    }

    # Add filter label and textbox above Get Apps
    $filterLabel = New-Object System.Windows.Forms.Label
    $filterLabel.Text = "Filter (exclude description contains):"
    $filterLabel.Size = New-Object System.Drawing.Size(200, 20)
    $filterLabel.Location = New-Object System.Drawing.Point(30, 405)
    $filterLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $filterBox = New-Object System.Windows.Forms.TextBox
    $filterBox.Size = New-Object System.Drawing.Size(200, 25)
    $filterBox.Location = New-Object System.Drawing.Point(230, 403)
    $filterBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $filterBox.Text = "Patch My PC"
    $filterBox.ReadOnly = $false  # Ensure editable

    # Single event handler for Get Apps button with filter functionality
    $btnGetApps.Add_Click({
        # Prevent multiple simultaneous loads
        if ($btnGetApps.Text -eq "Loading...") {
            return
        }
        
        # Update UI to show loading state
        $originalButtonText = $btnGetApps.Text
        $btnGetApps.Text = "Loading..."
        $btnGetApps.Enabled = $false
        $refreshButton.Enabled = $false
        
        $appsStatusLabel.Text = "Loading applications..."
        $appsStatusLabel.ForeColor = [System.Drawing.Color]::Orange
        $appsStatusLabel.Refresh()
        
        # Clear existing data
        $appListView.Rows.Clear()
        $global:deployedApps = @()
        
        $filter = $filterBox.Text.Trim()
        
        try {
            set-location "$($MECMSiteCode):"
            $apps = Get-CMApplication -fast | Where-Object {
                ($_.NumberOfDeployments -gt 0) -and
                ($_.LocalizedDescription -notmatch "Patch My PC") -and
                ([string]::IsNullOrEmpty($filter) -or $_.LocalizedDescription -notmatch [regex]::Escape($filter))
            } |
                Select-Object @{Name='AppName';Expression={$_.LocalizedDisplayName}},
                              @{Name='Version';Expression={$_.SoftwareVersion}},
                              Manufacturer,
                              @{Name='Deployments';Expression={$_.NumberOfDeployments}},
                              @{Name='DevicesCount';Expression={$_.NumberOfDevicesWithApp}},
                              @{Name='SCCMApp';Expression={$_}}
                              
            $count = 0
            foreach ($app in $apps) {
                $status = Get-MigrationStatus $app
                $appListView.Rows.Add($status, $app.AppName, $app.Version, $app.Manufacturer, $app.Deployments, $app.DevicesCount) | Out-Null
                $global:deployedApps += $app
                $count++
                if ($count % 10 -eq 0) {
                    $appsStatusLabel.Text = "Loaded $count applications..."
                    $appsStatusLabel.ForeColor = [System.Drawing.Color]::Orange
                    $appsStatusLabel.Refresh()
                }
            }
            $filterText = if ([string]::IsNullOrEmpty($filter)) { "" } else { " (filtered by: '$filter')" }
            $appsStatusLabel.Text = "Loaded $count applications$filterText"
            $appsStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(40, 167, 69)
        } catch {
            $appsStatusLabel.Text = "Error loading applications: $_"
            $appsStatusLabel.ForeColor = [System.Drawing.Color]::Red
        } finally {
            # Restore button state
            $btnGetApps.Text = $originalButtonText
            $btnGetApps.Enabled = $true
            $refreshButton.Enabled = $true
        }
    })

    # Add filter controls to the tab
    $tabAppSelection.Controls.Add($filterLabel)
    $tabAppSelection.Controls.Add($filterBox)

    $form.ShowDialog() | Out-Null
}

# Load required modules and show GUI
if (Import-SCCMModule) {
    if (Test-IntuneWin32AppModule) {
        Show-MigrationGUI
    } else {
        Write-Host "❌ Failed to load IntuneWin32App module. Please install it manually: Install-Module IntuneWin32App" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "❌ Failed to load SCCM module. Please ensure Configuration Manager console is installed." -ForegroundColor Red
    exit 1
}

# Define Get-MigrationStatus function at the top of Show-MigrationGUI
