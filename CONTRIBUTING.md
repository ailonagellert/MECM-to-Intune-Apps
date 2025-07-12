# Contributing to SCCM to Intune Migration Tool

We love your input! We want to make contributing to this project as easy and transparent as possible, whether it's:

- Reporting a bug
- Discussing the current state of the code
- Submitting a fix
- Proposing new features
- Becoming a maintainer

## 🚀 Development Process

We use GitHub to host code, to track issues and feature requests, as well as accept pull requests.

## 📝 Pull Requests

Pull requests are the best way to propose changes to the codebase. We actively welcome your pull requests:

1. **Fork the repo** and create your branch from `main`.
2. **Add tests** if you've added code that should be tested.
3. **Update documentation** if you've changed APIs or functionality.
4. **Ensure the test suite passes**.
5. **Make sure your code follows the style guidelines**.
6. **Issue a pull request**!

## 🐛 Report Bugs Using GitHub Issues

We use GitHub issues to track public bugs. Report a bug by [opening a new issue](https://github.com/yourusername/MECM-to-Intune-Apps/issues/new).

**Great Bug Reports** tend to have:

- A quick summary and/or background
- Steps to reproduce
  - Be specific!
  - Give sample code if you can
- What you expected would happen
- What actually happens
- Notes (possibly including why you think this might be happening, or stuff you tried that didn't work)

## 💡 Feature Requests

We track feature requests as GitHub issues. When creating a feature request:

- Use a clear and descriptive title
- Provide a detailed description of the suggested feature
- Explain why this feature would be useful
- Include examples of how the feature would be used

## 🎯 Development Guidelines

### PowerShell Style Guide

- **Functions**: Use approved PowerShell verbs (Get-, Set-, New-, etc.)
- **Parameters**: Use proper parameter validation attributes
- **Variables**: Use descriptive names with appropriate casing
- **Comments**: Include comment-based help for all functions
- **Error Handling**: Use try/catch blocks and proper error messages

### Code Structure

```powershell
function Verb-Noun {
    <#
    .SYNOPSIS
        Brief description of what the function does
    
    .DESCRIPTION
        Detailed description of the function
    
    .PARAMETER ParameterName
        Description of the parameter
    
    .EXAMPLE
        Verb-Noun -ParameterName "Value"
        Description of what this example does
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ParameterName
    )
    
    try {
        # Function logic here
        Write-Verbose "Descriptive message about what's happening"
        
        # Return appropriate value
        return $result
    }
    catch {
        Write-Error "Error message: $($_.Exception.Message)"
        throw
    }
}
```

### Logging Standards

- Use the `Write-Log` function for all logging
- Include appropriate log levels (INFO, WARNING, ERROR, SUCCESS)
- Provide meaningful, actionable log messages
- Log both successful operations and errors

### GUI Development

- Follow Windows Forms best practices
- Ensure accessibility compliance
- Implement proper error handling in event handlers
- Use consistent styling and layout

## 🧪 Testing

### Manual Testing Checklist

Before submitting a pull request, please test:

- [ ] SCCM connection and application discovery
- [ ] Application migration analysis
- [ ] Source file processing
- [ ] Intune package creation
- [ ] GUI functionality across different scenarios
- [ ] Error handling with invalid inputs
- [ ] Configuration file loading and validation

### Test Environment

- Test with different SCCM versions (2012 R2, 1902, 2103, etc.)
- Test with various application types (MSI, EXE, Script)
- Test with different Windows versions
- Test with both PowerShell 5.1 and PowerShell 7+

## 📚 Documentation

### Code Documentation

- Include comment-based help for all functions
- Document complex logic with inline comments
- Update README.md for new features
- Include examples in documentation

### User Documentation

- Update user guides for new features
- Include screenshots for GUI changes
- Provide troubleshooting information
- Document configuration changes

## 🚦 Development Workflow

### Branching Strategy

- `main`: Production-ready code
- `develop`: Integration branch for features
- `feature/feature-name`: Individual feature development
- `hotfix/issue-description`: Critical bug fixes

### Commit Messages

Use clear and meaningful commit messages:

```
feat: add support for App-V package detection
fix: resolve icon extraction for PNG format
docs: update installation instructions
style: improve PowerShell code formatting
refactor: optimize SCCM query performance
test: add unit tests for detection methods
```

### Version Management

We use [Semantic Versioning](https://semver.org/):

- **MAJOR**: Incompatible API changes
- **MINOR**: New functionality (backward compatible)
- **PATCH**: Bug fixes (backward compatible)

## 🛡️ Security

### Security Considerations

- Never commit credentials or secrets
- Use secure connection methods
- Implement proper input validation
- Follow PowerShell security best practices

### Reporting Security Issues

Please report security vulnerabilities privately to the maintainers before public disclosure.

## 📋 Issue Labels

We use the following labels to categorize issues:

- `bug`: Something isn't working
- `enhancement`: New feature or request
- `documentation`: Improvements or additions to documentation
- `good first issue`: Good for newcomers
- `help wanted`: Extra attention is needed
- `question`: Further information is requested
- `wontfix`: This will not be worked on

## 🏆 Recognition

Contributors will be recognized in:

- README.md acknowledgments section
- Release notes for their contributions
- Special contributor badge (for significant contributions)

## 📞 Getting Help

If you need help with contributing:

1. Check existing issues and documentation
2. Ask in [GitHub Discussions](https://github.com/yourusername/MECM-to-Intune-Apps/discussions)
3. Reach out to maintainers

## 📜 License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to make this tool better for everyone! 🎉
