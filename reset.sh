#!/bin/bash

kubectl delete csv/openshift-gitops-operator.v1.1.1
kubectl delete csv/openshift-gitops-operator.v0.0.4 

kubectl delete subscription/gitops-operator -n openshift-operators
kubectl delete subscription/openshift-gitops-operator -n  openshift-operators 


kubectl patch argocd/openshift-gitops -n openshift-gitops -p '{"metadata":{"finalizers":[]}}' --type=merge
kubectl delete argocd/openshift-gitops -n openshift-gitops
kubectl delete ns openshift-gitops





