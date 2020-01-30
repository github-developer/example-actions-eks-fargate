#!/bin/bash

CLUSTER_NAME=<your desired EKS cluster name>
AWS_REGION=<your region that supports EKS/Fargate, e.g. eu-west-1>
#assumes your AWS creds are in ~/.aws/credentials
AWS_ACCESS_KEY_ID=$(awk '-F=' '/aws_access_key_id/ { print $2 }' ~/.aws/credentials)
AWS_SECRET_ACCESS_KEY=$(awk '-F=' '/aws_secret_access_key/ { print $2 }' ~/.aws/credentials)

#check for needed commands
command -v eksctl >/dev/null 2>&1 || { echo >&2 "I require eksctl but it's not installed.  Aborting."; exit 1; }
command -v aws >/dev/null 2>&1 || { echo >&2 "I require the aws cli but it's not installed.  Aborting."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "I require jq but it's not installed.  Aborting."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo >&2 "I require kubectl but it's not installed.  Aborting."; exit 1; }

#https://docs.aws.amazon.com/eks/latest/userguide/pod-execution-role.html
cat << EOF > ./trust-relationship.json
{ 
  "Version": "2012-10-17",
  "Statement": [
    { 
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "eks-fargate-pods.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
aws iam create-role --role-name AmazonEKSFargatePodExecutionRole --assume-role-policy-document file://trust-relationship.json
aws iam attach-role-policy --role-name AmazonEKSFargatePodExecutionRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy

#create the EKS Fargate cluster
eksctl create cluster --name $CLUSTER_NAME --version 1.14 --fargate

#https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html
eksctl utils associate-iam-oidc-provider \
               --name $CLUSTER_NAME \
               --approve

curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.4/docs/examples/iam-policy.json

POLICY_EXISTING=$(aws iam list-policies | jq -r '.[][] | select(.PolicyName=="ALBIngressControllerIAMPolicy") | .Arn')

if [ $POLICY_EXISTING ]
then
POLICY_ARN=$POLICY_EXISTING;
else
POLICY_ARN=$(aws iam create-policy --policy-name ALBIngressControllerIAMPolicy --policy-document file://iam-policy.json | jq -r '.Policy.Arn')
fi
echo "POLICY ARN: $POLICY_ARN"

ROLE_NAME=$(kubectl -n kube-system describe configmap aws-auth | grep rolearn | cut -d'/' -f2)
echo "ROLE NAME: $ROLE_NAME"

aws iam attach-role-policy \
--policy-arn $POLICY_ARN \
--role-name $ROLE_NAME 

kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.4/docs/examples/rbac-role.yaml

kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.4/docs/examples/alb-ingress-controller.yaml

kubectl get deployment.apps/alb-ingress-controller -n kube-system -o json | jq '.spec.template.spec.containers[0].args += ["--cluster-name='$CLUSTER_NAME'", "--aws-region='$AWS_REGION'"]' | kubectl apply -f -

kubectl get deployment.apps/alb-ingress-controller -n kube-system -o json | jq '.spec.template.spec.containers[0].env += [ { "name": "AWS_ACCESS_KEY_ID", "value": "'$AWS_ACCESS_KEY_ID'" }, { "name": "AWS_SECRET_ACCESS_KEY", "value": "'$AWS_SECRET_ACCESS_KEY'" } ]' | kubectl apply -f -
