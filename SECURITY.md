# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Echelon, please report it privately by **opening a GitHub Issue** with the **`security`** label. Do not disclose the vulnerability publicly until it has been addressed.

We will acknowledge receipt within **48 hours** and work with you to understand and resolve the issue promptly.

## Scope

The following components are covered by this security policy:

- **echelon-core**: The core Java library (deontic token governance, policy engine, budget management)
- **echelon-workers**: Shell scripts and agent pipeline orchestration
- **echelon-docker**: Docker Compose configurations, seccomp profiles, filesystem allowlists
- **echelon-governance**: Governance and policy evaluation modules

## Out of Scope

Vulnerabilities in third-party dependencies should be reported to the respective project maintainers:

- Spring Boot (https://spring.io/security)
- Redis (https://redis.io/security)
- Docker (https://www.docker.com/support/security/)
- Apache Maven and plugins

## Supported Versions

We currently provide security updates for the latest stable release. Always ensure you are running the most recent version.
