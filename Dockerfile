# Multi-tool container combining dtzar/helm-kubectl + AWS CLI
FROM dtzar/helm-kubectl:latest

# Install AWS CLI using Alpine package manager (clean and simple)
RUN apk add --no-cache aws-cli

# Verify all tools are available
RUN aws --version && \
    kubectl version --client && \
    helm version

# Set working directory
WORKDIR /workdir

# Default command
CMD ["/bin/bash"]
