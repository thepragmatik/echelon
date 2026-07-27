# Contributing to Echelon

Thank you for your interest in contributing to Echelon! We welcome contributions from the community.

## Issues

- **Bug reports**: Open an issue with the `bug` label, describing the problem, steps to reproduce, and your environment.
- **Feature requests**: Open an issue with the `enhancement` label, describing the problem and your proposed solution.
- **Questions**: Open an issue with the `question` label.

## Branch Naming

Use `type/short-description` format:

```
docs/community-files
feat/deontic-token-validation
fix/redis-reconnect-timeout
ci/parallel-test-execution
```

## PR Workflow

1. **Create an issue** describing the problem or feature.
2. **Create a branch** from `main` with the naming convention above.
3. **Implement your changes** following the code style guidelines below.
4. **Commit** using [conventional commits](https://www.conventionalcommits.org/) (see below).
5. **Open a Pull Request** with `Closes #N` in the description referencing the related issue.
6. **Two reviewers must approve**: one for quality/review, one for adversarial/security review.
7. **Squash merge** to `main` once all approvals and CI checks pass.

## Commit Message Format

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <short description>

[optional body]
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `ci`, `perf`.

Examples:
```
feat: add deontic token validation pipeline
fix: handle Redis connection timeout during budget check
docs: add ADR for Redis budget streams
ci: run tests in parallel across modules
```

## Code Style

- **Java 21** with Spring Boot patterns
- **JUnit 5** for testing — **TDD is preferred**: write the test first, then the implementation
- Follow standard Java naming conventions (camelCase, PascalCase, UPPER_SNAKE_CASE)
- Keep methods focused and small; prefer composition over inheritance
- Use the existing [Developer Guide](https://thepragmatik.github.io/echelon/) for workflow reference

## Developer Guide

For full setup, workflow, and branching strategy details, see the [Developer Guide](https://thepragmatik.github.io/echelon/).
