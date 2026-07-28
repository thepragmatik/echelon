# Contributing to Echelon

Thank you for your interest in Echelon! We welcome contributions from everyone.

## Quick Start

1. **Clone the repo**
   ```bash
   git clone https://github.com/thepragmatik/echelon.git
   cd echelon
   ```

2. **Build and test**
   ```bash
   mvn clean test
   ```

3. **Run the full test suite**
   ```bash
   mvn test -q
   bash tests/shell/test_*.sh
   ```

## How to Contribute

### Reporting Bugs

Open a [GitHub Issue](https://github.com/thepragmatik/echelon/issues) with:
- A clear title and description
- Steps to reproduce
- Expected vs actual behavior
- Environment details (OS, JDK version, Docker version)

### Suggesting Features

Open a [GitHub Issue](https://github.com/thepragmatik/echelon/issues) with:
- A clear title and description
- Use case and motivation
- Possible implementation approach (optional)

### Submitting Pull Requests

1. Fork the repository
2. Create a feature branch: `git checkout -b feat/my-feature`
3. Make your changes
4. Run tests: `mvn test -q && bash tests/shell/test_*.sh`
5. Commit with a descriptive message following [Conventional Commits](https://www.conventionalcommits.org/)
6. Push and open a Pull Request

### Pull Request Guidelines

- Keep PRs focused on a single concern
- Include tests for new functionality
- Update documentation if needed
- Ensure CI passes (CodeQL, Spotless, integration tests)
- All review findings must be addressed before merge

## Project Structure

```
echelon/
├── echelon-governance/     # Policy engine, budget, cost tracking, skills
├── echelon-orchestrator/   # BuildManager, ReviewManager, services
├── echelon-workers/        # Worker shell scripts (implement, review)
├── echelon-docker/         # Docker Compose, Dockerfiles
├── docs/                   # MkDocs website source
└── tests/shell/            # Shell script tests
```

## Code Style

- Java: Google Java Format (enforced by Spotless)
- Shell: `set -euo pipefail`, shellcheck-clean
- Commits: [Conventional Commits](https://www.conventionalcommits.org/)
