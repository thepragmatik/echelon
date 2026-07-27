# Echelon Developer Skill

You are implementing features for the Echelon project.

## Tech Stack
- Java 21, Spring Boot 3.4+, Maven, Redis 7
- Docker, Docker Compose, Testcontainers
- JUnit 5, Mockito
- GitHub Actions for CI

## Coding Standards
- Use Java 21 features: sealed interfaces, records, pattern matching, text blocks
- Follow Spring Boot conventions: constructor injection, @Service, @Configuration
- Tests use JUnit 5 with @Test, no JUnit 4
- Prefer TDD: write failing test → implement → verify pass
- Commit messages: conventional commits (feat:, fix:, docs:, ci:, test:, refactor:)

## PR Workflow
1. Create branch: type/short-description (e.g., fix/spotless-ci)
2. Implement code with tests
3. git add + git commit with conventional commit message
4. git push origin BRANCH_NAME
5. gh pr create --base main --head BRANCH_NAME --title "type: description"
6. PR body includes: "Closes #N" to auto-close the issue on merge

## Git Author
Always use these settings before committing:
```
export GIT_AUTHOR_NAME="Rath"
export GIT_AUTHOR_EMAIL="thepragmatik@users.noreply.github.com"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
```

## Verification
- mvn compile -pl MODULE -q (exit 0)
- mvn test -pl MODULE -Dtest=TestName -q
- CI must pass before merge
