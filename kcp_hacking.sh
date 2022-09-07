#!/usr/bin/env bash

set -e 

function wait_for() {
    timeout=$1
    shift 1
    until [ $timeout -le 0 ] || ("$@" &> /dev/null); do
        echo waiting for "$@"
        sleep 1
        timeout=$(( timeout - 1 ))
    done
    if [ $timeout -le 0 ]; then
        return 1
    fi
}

function kill_kcp() {
    ps uax |egrep "cmd/kcp|kcp start" |grep -v grep |awk '{print $2}' |xargs kill -9
}

function delete_kind_cluster() {
    kind delete cluster --name kind
}

function nuke() {
    kill_kcp
    delete_kind_cluster
    rm -rf .kcp
}


function start_kcp() { 
	  # specify kubeconfig otherwise ~/.kube/config will be used
    export KUBECONFIG=.kcp/admin.kubeconfig

    # use the latest release. there are issues with main
    git checkout tags/v0.7.9

    # build and run kcp
    go run ./cmd/kcp start > /dev/null 2>&1 &


    # check for api status
    wait_for 30 kubectl api-resources

    # create syncer

    # create kind cluster
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/kubernetes-sigs/kind/main/site/static/examples/kind-with-registry.sh)"

    # verify the cluster was created
    kubectl cluster-info --context kind-kind

    kubectl config use-context kind-kind

    # install tekton
    kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

    kubectl config use-context root

    # install ko
    go install github.com/google/ko@latest

    SYNCER_IMAGE=$(KO_DOCKER_REPO=localhost:5001 ko publish ./cmd/syncer -t kcp-syncer)

    kubectl kcp workspace create my-org --enter

    kubectl kcp workload sync kind-kind --resources configmaps,deployment.apps,secrets,serviceaccounts,tasks,taskruns --syncer-image $SYNCER_IMAGE -o syncer.yaml

    kubectl config use-context kind-kind

    kubectl apply -f syncer.yaml 
}

