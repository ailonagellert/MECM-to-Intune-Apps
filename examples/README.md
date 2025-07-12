# Examples and Sample Scripts

This directory contains example scripts and usage patterns for the SCCM to Intune Migration Tool.

## Quick Start Examples

### Basic Migration
```powershell
# Simple application migration with GUI
.\Scripts\SCCM-to-Intune-Migrator.ps1
```

### Command Line Migration
```powershell
# Preview what would happen
.\Scripts\SCCM-to-Intune-Migrator.ps1 -WhatIf

# Use custom configuration
.\Scripts\SCCM-to-Intune-Migrator.ps1 -ConfigPath ".\custom-config.json"

# Skip certain steps
.\Scripts\SCCM-to-Intune-Migrator.ps1 -SkipIntunePublish
```

## Batch Processing Examples

### Process Multiple Applications
See `Batch-Migration-Example.ps1` for processing multiple applications in sequence.

### Generate Reports
See `Generate-Migration-Report.ps1` for creating migration assessment reports.

### Cleanup Utilities
See `Cleanup-Example.ps1` for post-migration cleanup operations.

## Configuration Examples

### Enterprise Configuration
See `enterprise-config.json` for large organization settings.

### Development Configuration  
See `dev-config.json` for development/testing environments.

### Multi-Tenant Configuration
See `multi-tenant-example.ps1` for managing multiple Intune tenants.

## Integration Examples

### Azure DevOps Pipeline
See `azure-pipelines-example.yml` for CI/CD integration.

### PowerShell DSC
See `DSC-Configuration-Example.ps1` for configuration management.

### Scheduled Tasks
See `Scheduled-Migration-Example.ps1` for automated migrations.

## Custom Scripts

### Advanced Detection Rules
Examples of custom detection rule implementations.

### Icon Processing
Custom icon extraction and processing examples.

### Reporting and Analytics
Scripts for generating migration reports and analytics.

---

Each example includes detailed comments and explanations. Start with the basic examples and progress to more advanced scenarios as needed.
