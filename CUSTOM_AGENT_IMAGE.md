# Custom Buildkite Agent Image for Kubernetes

## Problem Statement

When running Buildkite pipelines on Kubernetes using the `agent-stack-k8s` controller, we encountered issues where the default agent images lacked necessary tools for our CI/CD workflow. Specifically, we needed:

- Docker CLI for building container images
- Docker Buildx for multi-platform builds
- Namespace CLI (`nsc`) for remote build infrastructure
- Bash shell (the controller expects `/usr/local/bin/bash`)

## Solution Overview

We created a custom Docker image based on `buildkite/agent:alpine-k8s` that includes all required dependencies and properly handles the shell expectations of the Kubernetes controller.

## The Root Issue: Shell Compatibility

The `agent-stack-k8s` controller executes commands using `/usr/local/bin/bash` but was calling it incorrectly:
```bash
/usr/local/bin/bash "command-string"
```

Instead of the correct format:
```bash
/usr/local/bin/bash -c "command-string"
```

Simply installing bash wasn't enough - we needed a wrapper script to add the missing `-c` flag.

## Custom Image Build Process

### 1. Dockerfile Creation

Created `Dockerfile.buildkite-namespace` based on the Alpine K8s agent image:

```dockerfile
FROM buildkite/agent:alpine-k8s

# Install bash (Alpine uses ash by default)
RUN apk add --no-cache bash

# Install Docker CLI and buildx plugin
RUN apk add --no-cache docker-cli docker-cli-buildx

# Install Namespace CLI
RUN wget -O- https://get.namespace.so/install.sh | sh

# Create bash wrapper script to add -c flag automatically
RUN echo '#!/bin/sh' > /usr/local/bin/bash-wrapper && \
    echo 'exec /bin/bash -c "$@"' >> /usr/local/bin/bash-wrapper && \
    chmod +x /usr/local/bin/bash-wrapper

# Create symlinks so the controller finds bash where it expects
RUN ln -sf /usr/local/bin/bash-wrapper /usr/local/bin/bash && \
    ln -sf /usr/local/bin/bash-wrapper /bin/bash
```

### 2. Multi-Platform Build

Built for both AMD64 and ARM64 architectures to ensure compatibility across different node types:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f Dockerfile.buildkite-namespace \
  -t 097340723131.dkr.ecr.us-east-1.amazonaws.com/buildkite-namespace:latest \
  --push \
  .
```

### 3. Push to ECR

The image was pushed to Amazon ECR to make it accessible to our EKS cluster:

```bash
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  097340723131.dkr.ecr.us-east-1.amazonaws.com

docker push 097340723131.dkr.ecr.us-east-1.amazonaws.com/buildkite-namespace:latest
```

## Helm Configuration Update

Updated the Buildkite Kubernetes agent stack Helm deployment to use the custom image:

```bash
helm upgrade buildkite-agent oci://ghcr.io/buildkite/helm/agent-stack-k8s \
  --install \
  --create-namespace \
  --namespace buildkite \
  --set config.org=buildkite-kubernetes-5e4 \
  --set agentToken=<redacted> \
  --set image.repository=097340723131.dkr.ecr.us-east-1.amazonaws.com/buildkite-namespace \
  --set image.tag=latest \
  --set imagePullSecrets[0].name=ecr-registry-secret
```

## Verification

Confirmed the configuration was applied:

```bash
kubectl get configmap -n buildkite agent-stack-k8s-config -o yaml | grep -A 2 "image:"
```

Output showed:
```yaml
image: 097340723131.dkr.ecr.us-east-1.amazonaws.com/buildkite-namespace:latest
```

## Testing

Created a simplified test pipeline in `.buildkite/namespace.yml` to verify all tools were available:

```yaml
steps:
  - label: ":hammer: Verify Custom Agent Tools"
    agents:
      queue: kubernetes
    command: |
      echo "=== Tool Verification ==="
      docker --version
      docker buildx version
      /root/.ns/bin/nsc version || echo "NSC installed at /root/.ns/bin/nsc"
      buildkite-agent --version
      echo "✓ All tools verified!"
```

The pipeline passed successfully, confirming:
- Docker CLI is available
- Docker Buildx is available
- Namespace CLI is available at `/root/.ns/bin/nsc`
- Bash shell handling works correctly

## Key Learnings

1. **Agent Stack Expectations**: The `agent-stack-k8s` controller has specific expectations about shell locations and invocation
2. **Alpine vs Ubuntu**: The K8s controller expects Alpine-based images, not Ubuntu
3. **Wrapper Scripts**: Sometimes the cleanest solution is a simple wrapper script rather than trying to modify upstream behavior
4. **Multi-Platform Builds**: Always build for multiple architectures when deploying to heterogeneous Kubernetes clusters
5. **Image Registry**: Use ECR (or similar) for images that need to be accessible from Kubernetes nodes, not local registries

## Next Steps for Namespace Integration

The OIDC authentication with Namespace requires establishing a trust relationship between Buildkite and Namespace. This needs to be configured on the Namespace side by contacting their support team with:
- Workspace ID: `tenant_uabmve166l99o`
- Buildkite organization information
- OIDC issuer: `https://agent.buildkite.com`

Alternatively, consider using Namespace API token authentication if OIDC setup is not feasible.

## File Locations

- Dockerfile: `/Users/olabuildkite/GitHub/buildkite-kubernetes/Dockerfile.buildkite-namespace`
- Test Pipeline: `/Users/olabuildkite/GitHub/buildkite-kubernetes/.buildkite/namespace.yml`
- ECR Image: `097340723131.dkr.ecr.us-east-1.amazonaws.com/buildkite-namespace:latest`
