# Test Suite for SCCM to Intune Migration Tool

This directory contains test scripts and validation tools for the SCCM to Intune Migration Tool.

## Test Categories

### Unit Tests
- **Function Tests**: Test individual PowerShell functions
- **Configuration Tests**: Validate configuration file parsing
- **Data Structure Tests**: Test object creation and manipulation

### Integration Tests
- **SCCM Connectivity**: Test connection to SCCM infrastructure
- **Intune Authentication**: Validate Intune API authentication
- **File Operations**: Test source file processing

### End-to-End Tests
- **Complete Migration Workflow**: Test full application migration process
- **GUI Tests**: Test user interface functionality
- **Error Handling**: Validate error scenarios and recovery

## Running Tests

### Prerequisites
- PowerShell 5.1 or higher
- Pester module (for unit tests)
- Access to test SCCM environment
- Test Intune tenant

### Installation
```powershell
# Install Pester testing framework
Install-Module -Name Pester -Force -Scope CurrentUser

# Install required test dependencies
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
```

### Execute All Tests
```powershell
# Run all tests
.\Run-AllTests.ps1

# Run specific test category
.\Run-AllTests.ps1 -Category "Unit"
.\Run-AllTests.ps1 -Category "Integration"
.\Run-AllTests.ps1 -Category "EndToEnd"
```

### Execute Individual Tests
```powershell
# Run unit tests
Invoke-Pester .\Unit\*.Tests.ps1

# Run integration tests (requires environment)
Invoke-Pester .\Integration\*.Tests.ps1

# Run code analysis
Invoke-ScriptAnalyzer ..\Scripts\SCCM-to-Intune-Migrator.ps1
```

## Test Configuration

Create a `test-config.json` file for your test environment:

```json
{
    "TestSCCMServer": "test-sccm.domain.local",
    "TestSCCMSiteCode": "TST",
    "TestTenantId": "test-tenant-id",
    "TestClientId": "test-client-id",
    "TestClientSecret": "test-client-secret",
    "TestApplicationName": "Test Application",
    "TestSourcePath": "\\\\test-server\\test-sources"
}
```

## Test Data

### Sample Applications
Test data includes various application types:
- MSI packages
- EXE installers
- Script-based deployments
- Applications with different detection methods

### Mock Data
For unit tests that don't require live systems:
- Mock SCCM application objects
- Sample SDM Package XML
- Test configuration files

## Continuous Integration

The test suite is designed to work with GitHub Actions:
- Automated testing on pull requests
- Code quality checks
- Security scanning
- Documentation validation

## Contributing Tests

When adding new features:
1. Add corresponding unit tests
2. Update integration tests if needed
3. Include test data and documentation
4. Ensure all tests pass before submitting PR

## Test Results

Test results are output in multiple formats:
- Console output for local development
- JUnit XML for CI/CD integration
- HTML reports for detailed analysis
- Coverage reports for code quality

---

For more information on testing practices, see the [Contributing Guide](../CONTRIBUTING.md).
