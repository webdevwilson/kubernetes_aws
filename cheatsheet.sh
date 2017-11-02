#!/bin/bash -e

STATE_BUCKET=$1
DNS_NAME=$2

if [ -z "${DNS_NAME}" ]; then
    printf "Usage: %s <state_bucket> <dns_name>\n" $0
    exit 1
fi

printf "Creating state bucket '%s'\n" ${STATE_BUCKET}
aws s3api create-bucket --bucket kubernetes-aws-io

printf "Enabling bucket versioning\n"
aws s3api put-bucket-versioning --bucket ${STATE_BUCKET} --versioning-configuration Status=Enabled

printf "export KOPS_STATE_STORE=s3://%s\n" ${STATE_BUCKET} >> ~/.profile 

printf "[INFO] Creating hosted zone %s\n" ${DNS_NAME}
ID=$(uuidgen) && \
aws route53 create-hosted-zone \
    --name ${DNS_NAME} \
    --caller-reference $ID \
| jq .DelegationSet.NameServers

# create kubernetes cluster
kops create cluster --name kubes.kwilson.reluslabs.com --zones us-east-1a --state s3://kwilson-kops-state --yes

# validate the cluster
kops validate cluster --state s3://kwilson-kops-state

# create kubernetes ui
kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml

# get password
kubectl config view -o jsonpath='{.users[?(@.name == "kubes.kwilson.reluslabs.com")].user.password}'

# navigate to dashboard
open https://kubes.kwilson.reluslabs.com/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/

# create ecr repository
aws ecr create-repository --repository-name=hello-ecr --query "repository.repositoryUri"

# build docker image
docker build -t 193247949635.dkr.ecr.us-east-1.amazonaws.com/hello-ecr:latest .

# tag docker image
`aws ecr get-login --no-include-email --region us-east-1`
docker push 193247949635.dkr.ecr.us-east-1.amazonaws.com/hello-ecr:latest

# run the image in kubernetes
kubectl run hello-ecr --image=193247949635.dkr.ecr.us-east-1.amazonaws.com/hello-ecr:latest --replicas=2 --port=80

# expose the service
kubectl expose deployment hello-ecr --port=80 --type=LoadBalancer