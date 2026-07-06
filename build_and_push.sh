#!/bin/bash
# ECR registry URI
REGISTRY=255945442255.dkr.ecr.ap-southeast-1.amazonaws.com/mightycapstonevoting

# Authenticate Docker to ECR
aws ecr get-login-password --region ap-southeast-1 \
  | docker login --username AWS --password-stdin 255945442255.dkr.ecr.ap-southeast-1.amazonaws.com

# Build & push Vote service
docker build -t $REGISTRY:vote-v1 ./vote
docker build -t $REGISTRY:vote-v2 ./vote
docker push $REGISTRY:vote-v1
docker push $REGISTRY:vote-v2

# Build & push Result service
docker build -t $REGISTRY:result-v1 ./result
docker build -t $REGISTRY:result-v2 ./result
docker push $REGISTRY:result-v1
docker push $REGISTRY:result-v2

# Build & push Worker service
docker build -t $REGISTRY:worker-v1 ./worker
docker build -t $REGISTRY:worker-v2 ./worker
docker push $REGISTRY:worker-v1
docker push $REGISTRY:worker-v2

echo "✅ All images built and pushed to ECR"
