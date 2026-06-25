# Privacy Router
Mediates all outbound LLM API calls. Strips agent credentials, injects backend keys.
Routes to GLM-5.2 (Wafer) primary, DeepSeek V4 Pro fallback.
Configuration: echelon-docker/haproxy.cfg
Test: bash privacy-router-test.sh
