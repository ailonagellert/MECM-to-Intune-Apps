# User Guide

This comprehensive guide will help you use the SCCM to Intune Migration Tool effectively and efficiently.

## Table of Contents

1. [Getting Started](#getting-started)
2. [Understanding the Interface](#understanding-the-interface)
3. [Migration Workflow](#migration-workflow)
4. [Application Types](#application-types)
5. [Best Practices](#best-practices)
6. [Troubleshooting](#troubleshooting)

## Getting Started

### Launching the Tool

1. Open PowerShell as Administrator (recommended)
2. Navigate to the tool directory
3. Run the migration tool:
   ```powershell
   .\Scripts\SCCM-to-Intune-Migrator.ps1
   ```

### First-Time Setup

When you first launch the tool, you'll need to:

1. **Configure SCCM Connection**
   - Enter your SCCM site server name
   - Provide the site code
   - Test the connection

2. **Configure Intune Connection**
   - Enter your Azure tenant information
   - Provide app registration details
   - Test authentication

3. **Set File Paths**
   - Configure source file locations
   - Set output directory for Intune packages

## Understanding the Interface

### Main Window Components

#### Configuration Tab
- **SCCM Settings**: Site server, site code, source paths
- **Intune Settings**: Tenant ID, client credentials
- **Save/Load**: Persist configuration settings

#### Migration Tab
- **Application Search**: Find SCCM applications to migrate
- **Migration Analysis**: View compatibility assessment
- **Process Files**: Extract and organize source files
- **Package Creation**: Generate Intune packages

#### Logs Tab
- **Real-time Logging**: See operations as they happen
- **Log Levels**: INFO, WARNING, ERROR, SUCCESS
- **Export Logs**: Save logs for troubleshooting

### Button Functions

| Button | Function |
|--------|----------|
| **Search Applications** | Find SCCM applications by name |
| **Analyze Migration** | Check application compatibility |
| **Process Files** | Extract and organize source files |
| **Package for Intune** | Create .intunewin package |
| **Open Folder** | View generated files |
| **Save Config** | Persist configuration settings |

## Migration Workflow

### Step 1: Search for Applications

1. **Enter Application Name**: Type partial or full application name
2. **Execute Search**: Click "Search Applications"
3. **Review Results**: See matching applications in the list
4. **Select Application**: Choose the application to migrate

### Step 2: Analyze Migration Compatibility

The tool will automatically analyze the selected application for:

#### ✅ Compatibility Checks
- **Install Command**: Valid installation command line
- **Uninstall Command**: Proper uninstallation method
- **Detection Method**: Registry, file, or MSI detection
- **Source Files**: Accessible installation files

#### ⚠️ Common Issues
- **Missing Detection Rules**: Application lacks detection methods
- **Inaccessible Source**: Source files not found or permissions issues
- **Complex Dependencies**: Application has SCCM-specific features
- **Unsupported Type**: App-V or other unsupported package types

### Step 3: Process Source Files

1. **Validate Source Location**: Confirm source files are accessible
2. **Create Directory Structure**: Organize files for Intune
3. **Extract Metadata**: Gather version and publisher information
4. **Process Icon**: Extract and save application icon
5. **Generate Configuration**: Create PackageConstructor.json

#### Directory Structure Created
```
BaseAppPath/
├── Publisher/
│   ├── ApplicationName/
│   │   ├── Version/
│   │   │   ├── _Sourcefiles/          # Application installation files
│   │   │   ├── Documents/             # Configuration and documentation
│   │   │   │   └── PackageConstructor.json
│   │   │   ├── Icon/                  # Application icon
│   │   │   │   └── app_icon.png
│   │   │   └── intunewin/             # Generated packages
```

### Step 4: Package for Intune

1. **Create .intunewin Package**: Use Microsoft Win32 Content Prep Tool
2. **Generate Detection Rules**: Create appropriate detection methods
3. **Set Requirements**: Configure system requirements
4. **Upload to Intune**: Publish to your Intune tenant
5. **Verify Deployment**: Confirm successful upload

## Application Types

### Supported Application Types

#### MSI Packages
- **Characteristics**: Windows Installer packages
- **Detection**: Uses MSI product code
- **Advantages**: Built-in uninstall, version detection
- **Example**: Microsoft Office, Adobe Reader

#### EXE Installers
- **Characteristics**: Executable installation files
- **Detection**: File or registry-based
- **Requirements**: Silent install parameters needed
- **Example**: Chrome, Firefox, custom applications

#### Script-Based Installations
- **Characteristics**: PowerShell or batch scripts
- **Detection**: Custom file or registry detection
- **Complexity**: May require custom detection rules
- **Example**: Custom deployment scripts

### Unsupported Application Types

- **App-V Packages**: Virtual applications (not supported)
- **UWP/MSIX**: Modern Windows apps (use different deployment method)
- **Mac Applications**: macOS-specific packages
- **Mobile Apps**: iOS/Android applications

## Detection Methods

### MSI Detection
Best for MSI packages with product codes:
```json
{
    "method": "msi",
    "productCode": "{12345678-1234-1234-1234-123456789012}"
}
```

### Registry Detection
For applications that create registry entries:
```json
{
    "method": "registry",
    "registryPath": "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{ProductCode}",
    "registryValue": "DisplayName"
}
```

### File Detection
For applications that install specific files:
```json
{
    "method": "file",
    "filePath": "%ProgramFiles%\\ApplicationName",
    "fileName": "application.exe",
    "detectionType": "exists"
}
```

## Working with Configuration

### PackageConstructor.json

This file contains all the metadata for your application:

```json
{
    "publisher": "Adobe",
    "applicationName": "Adobe Reader DC",
    "version": "2023.008.20470",
    "intuneDisplayName": "Adobe - Adobe Reader DC - 2023.008.20470",
    "installCommand": "msiexec /i \"AcroRdrDC2300820470_en_US.msi\" /quiet",
    "uninstallCommand": "msiexec /x \"{AC76BA86-7AD7-1033-7B44-AC0F074E4100}\" /quiet",
    "detection": {
        "method": "msi",
        "productCode": "{AC76BA86-7AD7-1033-7B44-AC0F074E4100}"
    },
    "requirements": {
        "architecture": "x64",
        "minimumOS": "W10_1903"
    }
}
```

### Customizing Detection Rules

You can manually edit the PackageConstructor.json to customize detection:

1. **Open the JSON file** in the Documents folder
2. **Modify detection section** as needed
3. **Save the file**
4. **Re-run packaging** to apply changes

## Command Line Usage

### Basic Commands

```powershell
# Run with default configuration
.\SCCM-to-Intune-Migrator.ps1

# Use custom configuration file
.\SCCM-to-Intune-Migrator.ps1 -ConfigPath "C:\Custom\config.json"

# Preview mode (no changes made)
.\SCCM-to-Intune-Migrator.ps1 -WhatIf

# Skip specific steps
.\SCCM-to-Intune-Migrator.ps1 -SkipSourceUpdate -SkipIntunePublish
```

### Advanced Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `-ConfigPath` | Custom config file location | `-ConfigPath ".\custom.json"` |
| `-WhatIf` | Preview mode only | `-WhatIf` |
| `-SkipSourceUpdate` | Skip source file processing | `-SkipSourceUpdate` |
| `-SkipIntunePublish` | Skip Intune upload | `-SkipIntunePublish` |
| `-Force` | Overwrite existing files | `-Force` |

## Best Practices

### Before You Start

1. **Test Environment**: Always test in a non-production environment first
2. **Backup**: Ensure you have backups of important applications
3. **Documentation**: Document your current SCCM deployments
4. **Permissions**: Verify you have necessary permissions in both systems

### During Migration

1. **Start Small**: Begin with simple, non-critical applications
2. **Verify Detection**: Test detection rules thoroughly
3. **Monitor Logs**: Watch for errors and warnings
4. **Validate Packages**: Test .intunewin packages before deployment

### After Migration

1. **Test Deployment**: Deploy to test groups first
2. **Monitor Success**: Check deployment reports in Intune
3. **Update Documentation**: Document changes and configurations
4. **Clean Up**: Remove or disable SCCM deployments as appropriate

## Troubleshooting Common Issues

### Application Not Found
- **Check spelling** of application name
- **Verify permissions** to SCCM
- **Use wildcards** for partial matches

### Source Files Not Accessible
- **Check network paths** and permissions
- **Verify UNC path** format
- **Test manual access** to source location

### Detection Rule Failures
- **Review application behavior** after installation
- **Check registry entries** created by installer
- **Verify file locations** and names

### Package Creation Errors
- **Ensure source files** are complete
- **Check file permissions** on source directory
- **Verify .NET Framework** version

### Intune Upload Failures
- **Check authentication** credentials
- **Verify API permissions** in Azure
- **Review network connectivity** to Intune

---

For additional support, check the [Troubleshooting Guide](troubleshooting.md) or visit our GitHub discussions.
