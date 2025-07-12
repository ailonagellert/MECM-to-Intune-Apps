<#
.SYNOPSIS
    Batch migration example for processing multiple SCCM applications to Intune
    
.DESCRIPTION
    This example script demonstrates how to process multiple applications 
    from SCCM to Intune in a batch operation. It includes error handling,
    progress tracking, and detailed reporting.
    
.PARAMETER ConfigPath
    Path to the configuration file
    
.PARAMETER ApplicationList
    Path to file containing list of applications to migrate
    
.PARAMETER ReportPath
    Path to save the migration report
    
.EXAMPLE
    .\Batch-Migration-Example.ps1 -ApplicationList ".\apps-to-migrate.txt"
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "..\Scripts\config.json",
    [string]$ApplicationList = ".\sample-app-list.txt",
    [string]$ReportPath = ".\Migration-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

# Import the main migration script functions
. "..\Scripts\SCCM-to-Intune-Migrator.ps1"

function Start-BatchMigration {
    param(
        [string[]]$ApplicationNames,
        [string]$ConfigPath,
        [string]$ReportPath
    )
    
    Write-Host "Starting batch migration of $($ApplicationNames.Count) applications..." -ForegroundColor Green
    
    # Initialize results tracking
    $results = @()
    $successCount = 0
    $failureCount = 0
    
    # Process each application
    for ($i = 0; $i -lt $ApplicationNames.Count; $i++) {
        $appName = $ApplicationNames[$i].Trim()
        $progress = [math]::Round(($i / $ApplicationNames.Count) * 100, 1)
        
        Write-Progress -Activity "Migrating Applications" -Status "Processing: $appName" -PercentComplete $progress
        Write-Host "`n[$($i+1)/$($ApplicationNames.Count)] Processing: $appName" -ForegroundColor Cyan
        
        try {
            # Process single application
            $result = Start-SingleAppMigration -ApplicationName $appName -ConfigPath $ConfigPath
            
            if ($result.Success) {
                $successCount++
                Write-Host "  ✓ Successfully migrated: $appName" -ForegroundColor Green
            } else {
                $failureCount++
                Write-Host "  ✗ Failed to migrate: $appName - $($result.Error)" -ForegroundColor Red
            }
            
            $results += $result
            
        } catch {
            $failureCount++
            $errorResult = @{
                ApplicationName = $appName
                Success = $false
                Error = $_.Exception.Message
                StartTime = Get-Date
                EndTime = Get-Date
                Duration = 0
            }
            $results += $errorResult
            Write-Host "  ✗ Exception processing $appName : $($_.Exception.Message)" -ForegroundColor Red
        }
        
        # Add delay between applications to avoid overwhelming systems
        Start-Sleep -Seconds 2
    }
    
    Write-Progress -Activity "Migrating Applications" -Completed
    
    # Generate report
    Write-Host "`nGenerating migration report..." -ForegroundColor Yellow
    $results | Export-Csv -Path $ReportPath -NoTypeInformation
    
    # Summary
    Write-Host "`n" + "="*60 -ForegroundColor Yellow
    Write-Host "BATCH MIGRATION SUMMARY" -ForegroundColor Yellow
    Write-Host "="*60 -ForegroundColor Yellow
    Write-Host "Total Applications: $($ApplicationNames.Count)" -ForegroundColor White
    Write-Host "Successful: $successCount" -ForegroundColor Green
    Write-Host "Failed: $failureCount" -ForegroundColor Red
    Write-Host "Success Rate: $([math]::Round(($successCount / $ApplicationNames.Count) * 100, 1))%" -ForegroundColor White
    Write-Host "Report saved to: $ReportPath" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Yellow
    
    return $results
}

function Start-SingleAppMigration {
    param(
        [string]$ApplicationName,
        [string]$ConfigPath
    )
    
    $startTime = Get-Date
    $result = @{
        ApplicationName = $ApplicationName
        Success = $false
        Error = ""
        StartTime = $startTime
        EndTime = $null
        Duration = 0
        MigrationType = ""
        SourceFilesFound = $false
        IntunePackageCreated = $false
        IntunePublished = $false
    }
    
    try {
        # Step 1: Find SCCM Application
        $sccmApp = Get-SCCMApplicationByName -ApplicationName $ApplicationName
        if (-not $sccmApp) {
            throw "Application not found in SCCM: $ApplicationName"
        }
        
        # Step 2: Analyze Migration Compatibility
        $migrationInfo = Test-SCCMAppMigratability -SCCMApp $sccmApp
        if (-not $migrationInfo.IsMigratable) {
            throw "Application not suitable for migration: $($migrationInfo.Reason)"
        }
        
        $result.MigrationType = $migrationInfo.MigrationType
        
        # Step 3: Find Source Files
        $sourceFileInfo = Find-SourceFile -SCCMApp $sccmApp -MigrationInfo $migrationInfo
        if (-not $sourceFileInfo) {
            throw "Source files not found or inaccessible"
        }
        
        $result.SourceFilesFound = $true
        
        # Step 4: Create Directory Structure and Package
        # (Implementation would call the actual migration functions)
        Write-Host "    Creating package structure..." -ForegroundColor Gray
        
        # For this example, we'll simulate the packaging process
        Start-Sleep -Seconds 1
        $result.IntunePackageCreated = $true
        
        # Step 5: Publish to Intune (simulated)
        Write-Host "    Publishing to Intune..." -ForegroundColor Gray
        Start-Sleep -Seconds 2
        $result.IntunePublished = $true
        
        $result.Success = $true
        
    } catch {
        $result.Error = $_.Exception.Message
    } finally {
        $result.EndTime = Get-Date
        $result.Duration = ($result.EndTime - $result.StartTime).TotalSeconds
    }
    
    return $result
}

# Main execution
if ($MyInvocation.InvocationName -ne '.') {
    try {
        # Load configuration
        if (-not (Test-Path $ConfigPath)) {
            Write-Error "Configuration file not found: $ConfigPath"
            exit 1
        }
        
        # Load application list
        if (-not (Test-Path $ApplicationList)) {
            Write-Host "Application list file not found. Creating sample list..." -ForegroundColor Yellow
            
            # Create sample application list
            $sampleApps = @(
                "Adobe Reader DC",
                "Google Chrome",
                "Mozilla Firefox",
                "7-Zip",
                "Notepad++"
            )
            $sampleApps | Out-File -FilePath $ApplicationList -Encoding UTF8
            Write-Host "Sample application list created: $ApplicationList" -ForegroundColor Green
            Write-Host "Please edit this file with your actual application names and run again." -ForegroundColor Yellow
            exit 0
        }
        
        # Read application names
        $appNames = Get-Content -Path $ApplicationList | Where-Object { $_.Trim() -ne "" -and -not $_.StartsWith("#") }
        
        if ($appNames.Count -eq 0) {
            Write-Error "No applications found in list file: $ApplicationList"
            exit 1
        }
        
        Write-Host "Found $($appNames.Count) applications to process:" -ForegroundColor Green
        $appNames | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
        
        # Confirm before proceeding
        $confirmation = Read-Host "`nProceed with batch migration? (y/N)"
        if ($confirmation -notmatch '^[Yy]') {
            Write-Host "Migration cancelled by user." -ForegroundColor Yellow
            exit 0
        }
        
        # Start batch migration
        $results = Start-BatchMigration -ApplicationNames $appNames -ConfigPath $ConfigPath -ReportPath $ReportPath
        
        # Show failed applications for review
        $failedApps = $results | Where-Object { -not $_.Success }
        if ($failedApps.Count -gt 0) {
            Write-Host "`nFailed Applications:" -ForegroundColor Red
            $failedApps | ForEach-Object {
                Write-Host "  - $($_.ApplicationName): $($_.Error)" -ForegroundColor Red
            }
        }
        
    } catch {
        Write-Error "Batch migration failed: $($_.Exception.Message)"
        exit 1
    }
}
