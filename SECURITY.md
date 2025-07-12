# Security Policy

## Supported Versions

We provide security updates for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in the SCCM to Intune Migration Tool, please report it responsibly:

### How to Report

1. **Do NOT** create a public GitHub issue for security vulnerabilities
2. Send an email to the maintainers with details about the vulnerability
3. Include as much information as possible:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if available)

### What to Expect

- **Acknowledgment**: We'll acknowledge receipt within 48 hours
- **Initial Assessment**: We'll provide an initial assessment within 5 business days
- **Regular Updates**: We'll keep you informed of our progress
- **Resolution**: We aim to resolve critical vulnerabilities within 30 days
- **Credit**: We'll credit you in the security advisory (unless you prefer to remain anonymous)

### Security Considerations

#### Credential Security

- **Never commit** credentials, secrets, or sensitive configuration data to the repository
- Use Azure Key Vault or secure credential managers in production
- Rotate credentials regularly
- Use least-privilege principles for service accounts

#### Network Security

- Ensure all connections to SCCM and Intune use encrypted protocols
- Validate SSL/TLS certificates
- Implement proper firewall rules
- Use VPN connections for remote access

#### Code Security

- Input validation on all user inputs
- Proper error handling to prevent information disclosure
- Secure file operations with appropriate permissions
- Regular security audits of dependencies

#### Deployment Security

- Run with least-privilege user accounts
- Secure storage of configuration files
- Regular updates of PowerShell modules
- Monitoring and logging of all operations

### Security Best Practices for Users

1. **Environment Isolation**
   - Test in isolated environments before production use
   - Use separate service accounts for testing and production
   - Implement proper network segmentation

2. **Access Control**
   - Limit who can run the migration tool
   - Use role-based access control (RBAC)
   - Regular access reviews and cleanup

3. **Monitoring**
   - Monitor tool usage and outputs
   - Set up alerts for unusual activities
   - Regular log reviews

4. **Updates**
   - Keep the tool updated to the latest version
   - Subscribe to security advisories
   - Test updates in non-production environments first

### Security Features

#### Built-in Security Measures

- **Input Validation**: All user inputs are validated and sanitized
- **Secure Communications**: HTTPS/TLS for all API communications
- **Error Handling**: Proper error handling prevents information disclosure
- **Logging**: Comprehensive audit trails for security monitoring
- **Configuration Validation**: Secure configuration file validation

#### PowerShell Security

- **Execution Policy**: Requires appropriate PowerShell execution policy
- **Module Validation**: Validates required modules before execution
- **Script Signing**: Supports PowerShell script signing (recommended)
- **Constrained Language Mode**: Compatible with PowerShell security constraints

### Scope

This security policy covers:

- The main PowerShell script (`SCCM-to-Intune-Migrator.ps1`)
- Configuration files and templates
- Documentation and examples
- Related utilities and helper scripts

### Out of Scope

This policy does not cover:

- Third-party PowerShell modules (IntuneWin32App, ConfigurationManager)
- Microsoft SCCM or Intune services
- Operating system or infrastructure security
- Network infrastructure security

### Contact Information

For security-related questions or concerns, please contact the project maintainers through the appropriate channels as outlined in this policy.

---

Thank you for helping keep the SCCM to Intune Migration Tool secure!
