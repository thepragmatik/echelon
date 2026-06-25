# Echelon Deployment
## Environments
- Development: docker compose up
- Staging: docker compose --profile staging up
- Production: docker compose up (with Sentinel HA)

## Images
Published to ghcr.io/${{github.repository}}/ on merge to main.
