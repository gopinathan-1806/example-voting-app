# Voting App -- AWS EKS Deployment Spec

## Overview
Deploy the dockersamples/example-voting-app on AWS EKS using DevOps best practices. The app consists of 5 services: vote (Python), result (Node.js), worker (.NET), redis, and postgres.

## Architecture
```
Internet
   |
   |---> ALB ---> vote Service (port 80)     -- "Vote: Cats vs Dogs"
   '---> ALB ---> result Service (port 80)   -- "Live Results"
                     |
              +------+-------+
              v              v
            Redis         Postgres
              |              |
              '---- Worker --+
```

## AWS Resources
- **EKS Cluster**: `voting-app-cluster` -- t3.medium x2 nodes, ap-southeast-2
- **ECR**: 3 private repos -- vote, result, worker (redis/postgres use public images)
- **CodeBuild**: builds images, pushes to ECR, deploys to EKS
- **ALB**: via AWS Load Balancer Controller -- exposes vote and result
- **IAM**: least-privilege roles for CodeBuild and EKS nodes
- **SNS**: deployment notifications to fahadkhalid695@gmail.com
- **CloudWatch**: Container Insights enabled on EKS cluster

## Requirements

### Requirement 1 -- ECR Repositories
- [ ] Create ECR repos: `voting-app/vote`, `voting-app/result`, `voting-app/worker`
- [ ] Enable image scanning on push
- [ ] Lifecycle policy: keep last 10 images

### Requirement 2 -- EKS Cluster
- [ ] Create EKS cluster `voting-app-cluster` in ap-southeast-2
- [ ] Managed node group: t3.medium, min=2 max=4, desired=2
- [ ] Enable CloudWatch Container Insights
- [ ] Install AWS Load Balancer Controller via Helm
- [ ] Configure OIDC provider for IRSA

### Requirement 3 -- IAM Roles
- [ ] CodeBuild role: ECR push, EKS describe/update, SNS publish
- [ ] EKS node role: ECR pull, CloudWatch, SSM
- [ ] ALB Controller role (IRSA): elasticloadbalancing:*, ec2:Describe*

### Requirement 4 -- CodeBuild Pipeline
- [ ] Source: GitHub repo (dockersamples/example-voting-app)
- [ ] Build: docker build vote, result, worker -- push to ECR
- [ ] Deploy: kubectl apply k8s manifests with ECR image URIs
- [ ] Notify: SNS on success/failure

### Requirement 5 -- Kubernetes Manifests
- [ ] Namespace: `voting`
- [ ] Deployments: vote, result, worker, redis, db (postgres)
- [ ] Services: ClusterIP for redis/db/worker, LoadBalancer for vote/result
- [ ] ConfigMap for postgres credentials
- [ ] Resource limits on all containers
- [ ] Liveness and readiness probes

### Requirement 6 -- Verification
- [ ] Vote app accessible via ALB URL on port 80
- [ ] Result app accessible via ALB URL on port 80
- [ ] Cast a vote -- appears in result within 5 seconds
- [ ] SNS deployment notification received
