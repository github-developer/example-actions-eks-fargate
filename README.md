# Example GitHub Actions workflow to deploy to Amazon EKS on Fargate

An example workflow that uses [GitHub Actions](https://help.github.com/en/categories/automating-your-workflow-with-github-actions) to build [a static website](app/site/) into a container image tagged with the git sha, push that image to Amazon Elastic Container Registry, and deploy to Amazon EKS on using a simple Kubernetes Deployment and Service yaml with the image tag injected by Kustomize. An Ingress will create the needed ALB.

## Prerequisites

1. Create an EKS cluster, e.g. using [eks-fargate-setup.sh script](https://github.com/github-developer/example-actions-eks/blob/master/scripts/eks-fargate-setup.sh).
1. Create an ECR repo called `example-eks`

## Secrets

The following secrets are required to be set on the repository:

1. `AWS_ACCESS_KEY_ID`: An AWS access key ID for an account having the [EKS IAM role](https://docs.aws.amazon.com/eks/latest/userguide/service_IAM_role.html)
1. `AWS_SECRET_ACCESS_KEY`: An AWS secret sccess key for an account having the [EKS IAM role](https://docs.aws.amazon.com/eks/latest/userguide/service_IAM_role.html)

## Env vars

The following environment variables need to be set in the workflow:

1. AWS_REGION: (e.g. eu-west-1)
1. EKS_CLUSTER_NAME: (e.g. fantastic-party-9999999999)

You can optionally change the name of the ECR repo mentioned above in prereqs.

```
   - name: Build, tag, and push image to Amazon ECR
      id: build-image
      env:
        ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
        ECR_REPOSITORY: example-eks
        IMAGE_TAG: ${{ github.sha }}
```

## Contributions

We welcome contributions! See [how to contribute](CONTRIBUTING.md).

## License

[MIT](LICENSE)
