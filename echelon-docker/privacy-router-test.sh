#!/bin/bash
echo "Testing Privacy Router..."
echo "GLM-5.2: $(curl -s -o /dev/null -w "%{http_code}" http://privacy-router:8080/v1/chat/completions -H "X-Provider: glm" 2>/dev/null || echo "unreachable")"
echo "DeepSeek: $(curl -s -o /dev/null -w "%{http_code}" http://privacy-router:8080/v1/chat/completions -H "X-Provider: deepseek" 2>/dev/null || echo "unreachable")"
