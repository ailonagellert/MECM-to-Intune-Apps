# Project Structure

This document provides an overview of the complete project structure for the SCCM to Intune Migration Tool.

```
MECM-to-Intune-Apps/
├── .github/                          # GitHub configuration
│   ├── ISSUE_TEMPLATE/               # Issue templates
│   │   ├── bug_report.md
│   │   ├── bug_report.yml
│   │   ├── feature_request.md
│   │   └── support_question.md
│   ├── workflows/                    # GitHub Actions
│   │   └── ci-cd.yml
│   └── pull_request_template.md      # PR template
│
├── Scripts/                          # Main application scripts
│   ├── SCCM-to-Intune-Migrator.ps1  # Main migration script
│   ├── config.json                  # Configuration file (gitignored)
│   └── config.example.json          # Configuration template
│
├── docs/                            # Documentation
│   ├── installation-guide.md        # Setup and installation
│   ├── user-guide.md               # User documentation
│   └── api-reference.md             # API and function reference
│
├── examples/                        # Example scripts and usage
│   ├── README.md                    # Examples overview
│   ├── Batch-Migration-Example.ps1  # Batch processing example
│   └── sample-app-list.txt          # Sample application list
│
├── tests/                           # Test suite
│   ├── README.md                    # Testing documentation
│   └── test-config.example.json     # Test configuration template
│
├── README.md                        # Main project README
├── CONTRIBUTING.md                  # Contribution guidelines
├── LICENSE                          # MIT License
├── CHANGELOG.md                     # Version history
├── SECURITY.md                      # Security policy
├── .gitignore                       # Git ignore rules
└── PROJECT-STRUCTURE.md             # This file
```

## Core Components

### Main Script (`Scripts/SCCM-to-Intune-Migrator.ps1`)
The primary PowerShell script containing:
- GUI interface implementation
- SCCM integration functions
- Intune publishing capabilities
- File processing and packaging
- Comprehensive logging system

### Configuration System
- `config.example.json`: Template configuration file
- `config.json`: User's actual configuration (gitignored)
- Environment-specific settings for SCCM and Intune

### Documentation (`docs/`)
Comprehensive documentation including:
- **Installation Guide**: Step-by-step setup instructions
- **User Guide**: Complete usage documentation
- **API Reference**: Function and parameter documentation

### Examples (`examples/`)
Practical examples demonstrating:
- Basic usage patterns
- Batch processing scenarios
- Integration with other systems
- Custom configuration examples

### Testing Framework (`tests/`)
- Test configuration templates
- Unit and integration test structure
- Validation scripts

## Key Features

### 🎯 Core Functionality
- **SCCM Application Discovery**: Search and analyze applications
- **Migration Compatibility Analysis**: Validate migratability
- **Source File Processing**: Extract and organize installation files
- **Icon Extraction**: Preserve application icons
- **Intune Package Creation**: Generate .intunewin packages
- **Direct Intune Publishing**: Upload to Microsoft Intune

### 🖥️ User Interface
- **Windows Forms GUI**: User-friendly graphical interface
- **Command Line Interface**: Automation-friendly CLI
- **Real-time Logging**: Live feedback during operations
- **Progress Tracking**: Visual progress indicators

### 🔧 Configuration Management
- **JSON Configuration**: Flexible configuration system
- **Environment Templates**: Pre-configured settings
- **Validation**: Configuration validation and error checking

### 📊 Reporting and Logging
- **Comprehensive Logging**: Multi-level logging system
- **Migration Reports**: Detailed operation reports
- **Error Tracking**: Detailed error reporting and recovery

### 🛡️ Security and Quality
- **Input Validation**: Secure input handling
- **Error Handling**: Robust error management
- **Code Quality**: PSScriptAnalyzer compliance
- **Security Scanning**: Automated security checks

## Development Workflow

### Version Control
- **Main Branch**: Production-ready code
- **Feature Branches**: Individual feature development
- **Pull Requests**: Code review process
- **Automated Testing**: CI/CD pipeline

### Quality Assurance
- **Code Analysis**: PowerShell Script Analyzer
- **Security Scanning**: Automated security checks
- **Documentation Validation**: Link checking and completeness
- **Compatibility Testing**: Multiple PowerShell versions

### Release Process
- **Semantic Versioning**: Clear version numbering
- **Automated Builds**: GitHub Actions packaging
- **Release Notes**: Detailed change documentation
- **Distribution**: ZIP packages for easy deployment

## Extension Points

### Custom Functions
The modular design allows for:
- Custom detection methods
- Additional file processors
- Extended reporting capabilities
- Integration with other systems

### Configuration Extensions
- Custom validation rules
- Additional configuration parameters
- Environment-specific overrides
- Integration settings

### GUI Customization
- Additional interface elements
- Custom dialogs and forms
- Branding and styling options
- Accessibility enhancements

## Dependencies

### Required Software
- Windows PowerShell 5.1+ or PowerShell 7+
- Microsoft Configuration Manager Console
- .NET Framework 4.7.2+

### PowerShell Modules
- `ConfigurationManager` (SCCM module)
- `IntuneWin32App` (auto-installed)
- Standard Windows modules

### Azure Requirements
- Azure AD App Registration
- Microsoft Graph API permissions
- Intune administrator access

## Deployment Scenarios

### Single Administrator
- Individual workstation installation
- Personal configuration file
- Manual operation through GUI

### Team Environment
- Shared configuration templates
- Standardized procedures
- Batch processing capabilities

### Enterprise Deployment
- Centralized configuration management
- Automated migration workflows
- Integration with existing tools

### CI/CD Integration
- Pipeline automation
- Scheduled migrations
- Reporting integration

---

For specific implementation details, see the individual documentation files in the `docs/` directory.
