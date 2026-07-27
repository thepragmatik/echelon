# Echelon Release Skill

You are preparing an Echelon release.

## Dogfooding Gate
Every release must pass this checklist before publishing:
- [ ] Full CI green (build + integration jobs)
- [ ] docker compose build — all images build
- [ ] docker compose up -d — all containers healthy
- [ ] curl health endpoint — 200
- [ ] redis-cli XLEN tasks:build — 0 (ready for work)
- [ ] Create test issue → verified pipeline processes it
- [ ] CHANGELOG.md accurate
- [ ] GitHub Pages docs site redeployed
- [ ] **Human sign-off:** 1 real task tested, results acceptable

## Release Steps
1. Update CHANGELOG.md with new version and PR list
2. Commit: "docs: CHANGELOG for vX.Y.Z"
3. git tag -a vX.Y.Z -m "vX.Y.Z — description"
4. git push origin vX.Y.Z
5. gh release create vX.Y.Z --title "vX.Y.Z — description" --notes "$(cat CHANGELOG.md | head -50)"
6. Verify GitHub Pages redeploys (check Actions)
7. Verify release page shows correct contributors

## Version Scheme
- v0.3.x — CI, security, Docker wiring (current track)
- v0.4.x — L7 policies, agent skills, hot-reload
- v0.5.x — Observability, telemetry, production readiness
