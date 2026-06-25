# Developer Guide
## Setup
- Java 21+, Maven, Docker Desktop
- gh auth login with GitHub token
- git clone git@github.com:thepragmatik/echelon.git
- mvn clean compile

## Workflow
1. Branch from main: feature/ECH-{n}-{slug}
2. Implement code per issue spec
3. mvn compile (checkpoint commit)
4. mvn test (ensure passing)
5. Push branch and create PR
6. Wait for CI + 2 reviewer approvals
7. Squash merge to main
