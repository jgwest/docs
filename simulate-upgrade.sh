#!/bin/bash

kubectl delete csv/openshift-gitops-operator.v1.1.1

kubectl delete subscription/gitops-operator -n openshift-operators
kubectl delete subscription/openshift-gitops-operator -n  openshift-operators 

kubectl apply -f jgw-subscription.yaml




