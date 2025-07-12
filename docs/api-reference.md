# API Reference

This document provides detailed information about the PowerShell functions and APIs used in the SCCM to Intune Migration Tool.

## Core Functions

### Configuration Management

#### `Import-SCCMModule`
Loads the Configuration Manager PowerShell module.

**Syntax:**
```powershell
Import-SCCMModule
```

**Returns:**
- `[bool]` - True if module loaded successfully, False otherwise

**Example:**
```powershell
if (Import-SCCMModule) {
    Write-Host "SCCM module loaded successfully"
}
```

#### `Test-IntuneWin32AppModule`
Verifies and installs the IntuneWin32App PowerShell module if needed.

**Syntax:**
```powershell
Test-IntuneWin32AppModule
```

**Returns:**
- `[bool]` - True if module is available, False otherwise

### SCCM Application Functions

#### `Get-SCCMApplicationByName`
Searches for SCCM applications by name with support for wildcards.

**Syntax:**
```powershell
Get-SCCMApplicationByName -ApplicationName <string>
```

**Parameters:**
- `ApplicationName` [string] - Name or partial name of the application

**Returns:**
- `[object]` - SCCM Application object(s) or null if not found

**Example:**
```powershell
$app = Get-SCCMApplicationByName -ApplicationName "Adobe Reader"
if ($app) {
    Write-Host "Found application: $($app.LocalizedDisplayName)"
}
```

#### `Test-SCCMAppMigratability`
Analyzes an SCCM application for Intune migration compatibility.

**Syntax:**
```powershell
Test-SCCMAppMigratability -SCCMApp <object>
```

**Parameters:**
- `SCCMApp` [object] - SCCM Application object

**Returns:**
- `[hashtable]` with properties:
  - `IsMigratable` [bool] - Whether the app can be migrated
  - `Reason` [string] - Explanation of migration status
  - `MigrationType` [string] - Type of migration (Win32, Win32 (MSI), etc.)
  - `ParsedData` [array] - Parsed deployment type data

**Example:**
```powershell
$migrationInfo = Test-SCCMAppMigratability -SCCMApp $sccmApp
if ($migrationInfo.IsMigratable) {
    Write-Host "Application can be migrated as: $($migrationInfo.MigrationType)"
} else {
    Write-Host "Cannot migrate: $($migrationInfo.Reason)"
}
```

#### `ConvertFrom-SDMPackageXML`
Parses SCCM SDM Package XML to extract deployment type information.

**Syntax:**
```powershell
ConvertFrom-SDMPackageXML -XMLContent <string> -AppName <string>
```

**Parameters:**
- `XMLContent` [string] - SCCM SDMPackageXML content
- `AppName` [string] - Application name for logging

**Returns:**
- `[array]` - Array of parsed deployment type objects

### Source File Functions

#### `Find-SourceFile`
Locates source files for an SCCM application.

**Syntax:**
```powershell
Find-SourceFile -SCCMApp <object> -MigrationInfo <hashtable>
```

**Parameters:**
- `SCCMApp` [object] - SCCM Application object
- `MigrationInfo` [hashtable] - Migration analysis results

**Returns:**
- `[hashtable]` with source file information or null if not found

**Example:**
```powershell
$sourceInfo = Find-SourceFile -SCCMApp $app -MigrationInfo $migrationInfo
if ($sourceInfo) {
    Write-Host "Found source file: $($sourceInfo.FileName)"
    Write-Host "Size: $([math]::Round($sourceInfo.FileSize / 1MB, 2)) MB"
}
```

#### `Get-FileVersionInfo`
Extracts version information from executable or MSI files.

**Syntax:**
```powershell
Get-FileVersionInfo -FilePath <string>
```

**Parameters:**
- `FilePath` [string] - Path to the file

**Returns:**
- `[hashtable]` with version information:
  - `FileVersion` [string]
  - `ProductVersion` [string]
  - `CompanyName` [string]
  - `ProductName` [string]
  - `FileDescription` [string]

#### `Get-MSIVersionInfo`
Specialized function for extracting metadata from MSI files.

**Syntax:**
```powershell
Get-MSIVersionInfo -MSIPath <string>
```

**Parameters:**
- `MSIPath` [string] - Path to MSI file

**Returns:**
- `[hashtable]` with MSI-specific information including ProductCode

### Icon Management

#### `Export-SCCMAppIcon`
Extracts application icon from SCCM application data.

**Syntax:**
```powershell
Export-SCCMAppIcon -SCCMApp <object> -DestinationPath <string> [-MigrationInfo <hashtable>]
```

**Parameters:**
- `SCCMApp` [object] - SCCM Application object
- `DestinationPath` [string] - Output directory path
- `MigrationInfo` [hashtable] - Optional migration analysis data

**Returns:**
- `[hashtable]` with icon information or null if no icon found

#### `Save-IconData`
Saves Base64 icon data to file with appropriate format detection.

**Syntax:**
```powershell
Save-IconData -IconData <string> -DestinationPath <string> -SCCMApp <object>
```

**Parameters:**
- `IconData` [string] - Base64 encoded icon data
- `DestinationPath` [string] - Output directory
- `SCCMApp` [object] - SCCM Application object

**Returns:**
- `[hashtable]` with saved icon details

### Directory Management

#### `New-VersionDirectory`
Creates the organized directory structure for application packaging.

**Syntax:**
```powershell
New-VersionDirectory -SourceFileInfo <hashtable> -Publisher <object> -Application <object> -Version <string> -SCCMApp <object> [-MigrationInfo <hashtable>]
```

**Parameters:**
- `SourceFileInfo` [hashtable] - Source file information
- `Publisher` [object] - Publisher information
- `Application` [object] - Application information
- `Version` [string] - Application version
- `SCCMApp` [object] - SCCM Application object
- `MigrationInfo` [hashtable] - Optional migration data

**Returns:**
- `[string]` - Path to created version directory

### Package Configuration

#### `New-PackageConstructorJSON`
Generates the PackageConstructor.json file with application metadata.

**Syntax:**
```powershell
New-PackageConstructorJSON -VersionPath <string> -SCCMApp <object> -SourceFileInfo <hashtable> -MigrationInfo <hashtable> -Publisher <object> -Application <object> -Version <string>
```

**Parameters:**
- `VersionPath` [string] - Version directory path
- `SCCMApp` [object] - SCCM Application object
- `SourceFileInfo` [hashtable] - Source file information
- `MigrationInfo` [hashtable] - Migration analysis data
- `Publisher` [object] - Publisher information
- `Application` [object] - Application information
- `Version` [string] - Application version

**Returns:**
- `[string]` - Path to created JSON file

#### `Get-OptimalDetectionMethod`
Determines the best detection method for an application.

**Syntax:**
```powershell
Get-OptimalDetectionMethod -SourceFileInfo <hashtable> -SCCMApp <object> -MigrationInfo <hashtable>
```

**Returns:**
- `[hashtable]` with detection method configuration

### Intune Integration

#### `Invoke-IntunePackaging`
Packages and publishes the application to Microsoft Intune.

**Syntax:**
```powershell
Invoke-IntunePackaging -VersionPath <string> -SourceFileInfo <hashtable>
```

**Parameters:**
- `VersionPath` [string] - Path to version directory
- `SourceFileInfo` [hashtable] - Source file information

**Returns:**
- `[bool]` - True if successful, False otherwise

### Utility Functions

#### `Write-Log`
Centralized logging function with multiple output targets.

**Syntax:**
```powershell
Write-Log -Message <string> [-Level <string>] [-LogBox <RichTextBox>]
```

**Parameters:**
- `Message` [string] - Log message
- `Level` [string] - Log level (INFO, WARNING, ERROR, SUCCESS)
- `LogBox` [RichTextBox] - Optional GUI log control

**Example:**
```powershell
Write-Log -Message "Starting migration process" -Level "INFO"
Write-Log -Message "Application not found" -Level "WARNING"
Write-Log -Message "Migration completed successfully" -Level "SUCCESS"
```

#### `Show-FileSelectionDialog`
Displays a dialog for selecting files when multiple options are available.

**Syntax:**
```powershell
Show-FileSelectionDialog -Files <array> -Title <string> [-Message <string>]
```

**Parameters:**
- `Files` [array] - Array of file objects
- `Title` [string] - Dialog title
- `Message` [string] - Optional dialog message

**Returns:**
- `[object]` - Selected file object or null if cancelled

## Data Structures

### SourceFileInfo Object
```powershell
@{
    FilePath = "C:\path\to\installer.msi"
    FileName = "installer.msi"
    FileSize = 52428800  # Size in bytes
    VersionInfo = @{
        FileVersion = "1.2.3.4"
        ProductVersion = "1.2.3"
        CompanyName = "Example Corp"
        ProductName = "Example Application"
        ProductCode = "{12345678-1234-1234-1234-123456789012}"  # MSI only
    }
    ContentLocation = "\\server\share\app\source"
    AllFiles = @()  # Array of all files in source directory
    TotalFileSize = 104857600  # Total size of all files
}
```

### MigrationInfo Object
```powershell
@{
    IsMigratable = $true
    Reason = "All requirements met"
    MigrationType = "Win32 (MSI)"
    ParsedData = @(
        @{
            InstallCommand = "msiexec /i installer.msi /quiet"
            UninstallCommand = "msiexec /x {ProductCode} /quiet"
            ContentLocations = @("\\server\share\source")
            HasDetectionMethod = $true
            DetectionMethodDetails = "Enhanced detection method configured"
            Technology = "MSI"
            IconData = "base64-encoded-icon-data"
        }
    )
}
```

### PackageConstructor JSON Schema
```json
{
    "publisher": "string",
    "applicationName": "string", 
    "version": "string",
    "intuneDisplayName": "string",
    "installCommand": "string",
    "uninstallCommand": "string",
    "detection": {
        "method": "msi|registry|file",
        "productCode": "string",  // MSI only
        "registryPath": "string",  // Registry only
        "registryValue": "string",  // Registry only
        "filePath": "string",  // File only
        "fileName": "string",  // File only
        "detectionType": "exists|version"  // File only
    },
    "requirements": {
        "architecture": "x64|x86",
        "minimumOS": "W10_1903|W10_1909|etc"
    },
    "metadata": {
        "category": "string",
        "description": "string",
        "createdDate": "YYYY-MM-DD",
        "createdBy": "string",
        "sourceFile": "string",
        "totalFiles": "number",
        "totalSize": "number",
        "icon": {
            "fileName": "string",
            "filePath": "string",
            "size": "number",
            "extracted": "boolean"
        }
    }
}
```

## Error Handling

### Common Error Patterns

```powershell
try {
    # Operation that might fail
    $result = Invoke-SomeOperation
    Write-Log -Message "Operation successful" -Level "SUCCESS"
}
catch {
    Write-Log -Message "Operation failed: $($_.Exception.Message)" -Level "ERROR"
    return $false
}
```

### Error Categories

- **Connection Errors**: SCCM or Intune connectivity issues
- **Permission Errors**: File system or API permission problems  
- **Validation Errors**: Invalid data or configuration
- **Processing Errors**: File operations or parsing failures

## Configuration Schema

### config.json Structure
```json
{
    "SCCMSiteServer": "string - FQDN of SCCM site server",
    "SCCMSiteCode": "string - 3 character site code", 
    "BaseAppPath": "string - Output path for packages",
    "BaseSourcePath": "string - Path to SCCM source files",
    "TenantId": "string - Azure AD tenant ID",
    "ClientId": "string - Azure app registration client ID",
    "ClientSecret": "string - Azure app registration secret"
}
```

## Script Parameters

### Command Line Parameters
```powershell
[CmdletBinding()]
param(
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$ConfigPath = "config.json",
    
    [switch]$WhatIf,
    
    [switch]$SkipSourceUpdate,
    
    [switch]$SkipIntunePublish,
    
    [switch]$Force
)
```

---

For implementation examples and usage patterns, see the [User Guide](user-guide.md).
