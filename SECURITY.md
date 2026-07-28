# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Echelon, please report it privately.

**Do not** open a public GitHub Issue. Instead, email the project maintainer or open a [GitHub Security Advisory](https://github.com/thepragmatik/echelon/security/advisories).

### What to include

- Description of the vulnerability
- Steps to reproduce
- Affected versions
- Any potential mitigations you've identified

### Response timeline

- **48 hours**: Acknowledgment of your report
- **7 days**: Initial assessment and remediation plan
- **30 days**: Fix released or timeline communicated

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest  | ✅ |
| Older   | ❌ |

## Security Practices

- **Static analysis**: CodeQL runs on every PR
- **Dependency scanning**: Dependabot alerts for vulnerable dependencies
- **Supply chain**: All dependencies pinned with upper bounds
- **Zero-trust**: All agent operations go through DeonticToken policy enforcement
