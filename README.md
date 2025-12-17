This repository contains the infrastructure configuration for deploying Nginx web server on Kubernetes using Buildkite CI/CD pipeline.

## Features

- Nginx web server deployment on Kubernetes
- Automated deployment pipeline using Buildkite
- Configurable index.html content via ConfigMap
- Kubernetes service for external access
- Resource limits and requests configuration

## Deployment

The project uses a Buildkite pipeline to automate the deployment process. The pipeline:
1. Applies the ConfigMap containing the web content
2. Deploys the Nginx deployment with proper volume mounts
3. Creates the Kubernetes service for external access
4. Monitors the deployment rollout status

## Requirements

- Kubernetes cluster
- kubectl CLI
- Buildkite access
- Kubernetes service account with appropriate permissions (used by the Buildkite Kubernetes agent to deploy resources to the cluster)



## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a new Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.
# Test plugin sharing with custom agent
# Testing plugin cache feature
# Testing bash availability
