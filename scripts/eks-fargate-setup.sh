#!/bin/bash

CLUSTER_NAME=jpadams-eks-fargate-feb5
AWS_REGION=eu-west-1

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
               --cluster $CLUSTER_NAME \
               --approve
               
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.4/docs/examples/rbac-role.yaml

curl -sO https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.4/docs/examples/iam-policy.json

POLICY_EXISTING=$(aws iam list-policies | jq -r '.[][] | select(.PolicyName=="ALBIngressControllerIAMPolicy") | .Arn')
if [ $POLICY_EXISTING ]
then
POLICY_ARN=$POLICY_EXISTING;
else
POLICY_ARN=$(aws iam create-policy --policy-name ALBIngressControllerIAMPolicy --policy-document file://iam-policy.json | jq -r '.Policy.Arn')
fi

eksctl create iamserviceaccount \
       --cluster=$CLUSTER_NAME \
       --namespace=kube-system \
       --name=alb-ingress-controller \
       --attach-policy-arn=$POLICY_ARN \
       --override-existing-serviceaccounts \
       --approve

AWS_VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME | jq -r '.cluster.resourcesVpcConfig.vpcId')

curl -sS "https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.4/docs/examples/alb-ingress-controller.yaml" \
     | sed "s/# - --cluster-name=devCluster/- --cluster-name=$CLUSTER_NAME/g" \
     | sed "s/# - --aws-region=us-west-1/- --aws-region=$AWS_REGION/g" \
     | sed "s/# - --aws-vpc-id=vpc-xxxxxx/- --aws-vpc-id=$AWS_VPC_ID/g" \
     | kubectl apply -f -
