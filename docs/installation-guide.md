# Installation Guide

This guide will walk you through the complete installation and initial setup of the SCCM to Intune Migration Tool.

## Prerequisites

### System Requirements

- **Operating System**: Windows 10 (1903+) or Windows Server 2016+
- **PowerShell**: Version 5.1 or PowerShell 7+
- **.NET Framework**: 4.7.2 or higher
- **Memory**: Minimum 4GB RAM, 8GB recommended
- **Storage**: 2GB free space for temporary files and packages

### Required Software

1. **Microsoft Configuration Manager Console**
   - Download from Microsoft System Center or Software Center
   - Install on the machine where you'll run the migration tool
   - Ensure you can connect to your SCCM environment

2. **Azure PowerShell Modules** (auto-installed by script)
   - IntuneWin32App module
   - Microsoft.Graph modules (dependencies)

### Network Requirements

- **SCCM Connectivity**: Access to SCCM site server and database
- **Internet Access**: Required for Intune API calls and module downloads
- **File Share Access**: Read access to SCCM source file locations
- **Firewall**: Ensure PowerShell can connect to required endpoints

## Step-by-Step Installation

### 1. Download the Tool

**Option A: Clone from GitHub**
```powershell
git clone https://github.com/yourusername/MECM-to-Intune-Apps.git
cd MECM-to-Intune-Apps
```

**Option B: Download ZIP**
1. Go to the GitHub repository
2. Click "Code" → "Download ZIP"
3. Extract to your desired location

### 2. Verify PowerShell Execution Policy

Check your current execution policy:
```powershell
Get-ExecutionPolicy
```

If restricted, set it to allow script execution:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 3. Create Azure App Registration

1. **Sign in to Azure Portal**
   - Go to [Azure Portal](https://portal.azure.com)
   - Navigate to "Azure Active Directory"

2. **Create App Registration**
   - Click "App registrations" → "New registration"
   - Name: "SCCM-Intune-Migration-Tool"
   - Account types: "Accounts in this organizational directory only"
   - Redirect URI: Leave blank
   - Click "Register"

3. **Configure API Permissions**
   - Go to "API permissions"
   - Click "Add a permission" → "Microsoft Graph" → "Application permissions"
   - Add these permissions:
     - `DeviceManagementApps.ReadWrite.All`
     - `DeviceManagementConfiguration.ReadWrite.All`
   - Click "Grant admin consent"

4. **Create Client Secret**
   - Go to "Certificates & secrets"
   - Click "New client secret"
   - Description: "Migration Tool Secret"
   - Expires: Choose appropriate duration
   - Copy the secret value (you won't see it again!)

5. **Note Required Information**
   - Application (client) ID
   - Directory (tenant) ID
   - Client secret value

### 4. Configure the Application

1. **Copy Configuration Template**
   ```powershell
   cd Scripts
   Copy-Item config.example.json config.json
   ```

2. **Edit Configuration**
   
   Open `config.json` in your favorite editor and update:

   ```json
   {
       "SCCMSiteServer": "your-sccm-server.contoso.com",
       "SCCMSiteCode": "ABC",
       "BaseAppPath": "C:\\IntuneApps",
       "BaseSourcePath": "\\\\sccm-server\\sources$",
       "TenantId": "your-tenant-id-from-azure",
       "ClientId": "your-client-id-from-azure",
       "ClientSecret": "your-client-secret-from-azure"
   }
   ```

   **Configuration Details:**
   - `SCCMSiteServer`: Your SCCM primary site server FQDN
   - `SCCMSiteCode`: Your SCCM site code (typically 3 characters)
   - `BaseAppPath`: Local or network path for Intune package output
   - `BaseSourcePath`: Network path to SCCM source files
   - `TenantId`: From Azure AD → Properties → Tenant ID
   - `ClientId`: From your app registration → Overview → Application ID
   - `ClientSecret`: The secret value you copied earlier

### 5. Test the Installation

Run a basic connectivity test:
```powershell
.\SCCM-to-Intune-Migrator.ps1 -WhatIf
```

This will:
- Load required modules
- Test SCCM connectivity
- Validate Intune authentication
- Show what would happen without making changes

## Troubleshooting Installation Issues

### PowerShell Module Issues

**Error**: "Module 'ConfigurationManager' not found"
```powershell
# Solution: Install SCCM Admin Console or update import path
# Check if module exists:
Get-Module -ListAvailable -Name ConfigurationManager
```

**Error**: "Module 'IntuneWin32App' not found"
```powershell
# Solution: Manual installation
Install-Module -Name IntuneWin32App -Force -AllowClobber -Scope CurrentUser
```

### SCCM Connectivity Issues

**Error**: "Cannot connect to SCCM site server"
- Verify SCCM server name and site code
- Ensure SCCM Admin Console is installed
- Check network connectivity
- Verify user permissions

### Intune Authentication Issues

**Error**: "Authentication failed"
- Verify Azure App Registration configuration
- Check API permissions are granted
- Ensure client secret hasn't expired
- Verify tenant ID is correct

### File Access Issues

**Error**: "Access denied to source files"
- Check BaseSourcePath configuration
- Verify network share permissions
- Ensure user has read access to source locations
- Test manual access to the share

## Advanced Configuration

### Custom Module Paths

If SCCM modules are in non-standard locations, you can specify paths:
```powershell
$env:PSModulePath += ";C:\CustomPath\ConfigMgr"
```

### Proxy Configuration

For environments with proxy servers:
```powershell
# Set proxy for PowerShell session
$proxy = New-Object System.Net.WebProxy("http://proxy.company.com:8080")
[System.Net.WebRequest]::DefaultWebProxy = $proxy
```

### Logging Configuration

Adjust logging levels by modifying the Write-Log function calls in the script.

## Validation Checklist

Before proceeding with migrations, verify:

- [ ] PowerShell execution policy allows script execution
- [ ] SCCM Admin Console is installed and functional
- [ ] Network connectivity to SCCM server
- [ ] Azure App Registration has required permissions
- [ ] Intune authentication succeeds
- [ ] Access to SCCM source file locations
- [ ] Write permissions to output directory
- [ ] Test migration with a simple application

## Next Steps

Once installation is complete:

1. **Read the User Guide**: `docs/user-guide.md`
2. **Review Best Practices**: `docs/best-practices.md`
3. **Test with Non-Critical Application**: Start with a test app
4. **Join the Community**: Check GitHub discussions for tips and support

---

Need help? Check the [Troubleshooting Guide](troubleshooting.md) or create an issue on GitHub.
