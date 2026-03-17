#!/bin/bash
set -x
set -eo pipefail

NODE_NAME=${NODE_NAME:-$(/usr/bin/hostname -s)}
KUBECONFIG=${KUBECONFIG:-/etc/kubernetes/kubelet-kubeconfig.conf}
KUBECTL=${KUBECTL:-"/home/kubernetes/bin/kubectl"}
export KUBECONFIG
CORDONED_FILE="/var/lib/node-sitter/cordoned-by-node-drainer"

### expects the list of pids of running processes and waits for them to finish
waitall() {
    local pids alive_pids timeout finish_time
    pids="$1"
    timeout=${2:-15}
    finish_time=$(( EPOCHSECONDS + timeout ))
    while [[ $EPOCHSECONDS -le $finish_time ]]; do
        alive_pids=""
        for pid in $pids; do
            if /usr/bin/kill -0 "$pid" 2>/dev/null; then
                alive_pids="$alive_pids $pid"
            elif wait "$pid"; then
                :
            else
                echo "Process $pid failed" >&2
            fi
        done
        if [[ -z "$alive_pids" ]]; then
            break
        fi
        pids="$alive_pids"
        sleep 0.1
    done
}

### debuffs the previously set cordon status
public_uncordon() {
    local finish_time
    if [[ -f "$CORDONED_FILE" ]]; then
        echo "The cordon lock file found, proceeding node uncordon" >&2
    else
        return 0
    fi
    finish_time=$(( EPOCHSECONDS + 300 ))
    while [[ $EPOCHSECONDS -le $finish_time ]]; do
        if $KUBECTL uncordon "$NODE_NAME"; then
            rm -f "$CORDONED_FILE"
            return 0
        fi
        echo "Node uncordon failed, next attempt after 10s" >&2
        sleep 10
    done
    echo "Give up with node uncordon" >&2
    return 1
}

### sets cordon status to the node and removes node hosted pods except DaemonSets
public_drain() {
    local pod ns current_ns pod_list pids
    $KUBECTL cordon "$NODE_NAME" || echo "Failed to cordon node, continue anyway" >&2
    touch "$CORDONED_FILE"
    while read ns pod; do
        if [[ "$ns" != "$current_ns" ]]; then
            if [[ -n "$pod_list" ]]; then
                $KUBECTL -n "$current_ns" delete pods --force --grace-period=0 $pod_list &
                pids="$pids $!"
                /usr/bin/sleep 0.1
            fi
            current_ns="$ns"
            pod_list="$pod"
        else
            pod_list="$pod_list $pod"
        fi
    done < <($KUBECTL get pods -A --field-selector spec.nodeName="$NODE_NAME" \
        -o jsonpath='{range .items[?(@.metadata.ownerReferences[0].kind!="DaemonSet")]}{@.metadata.namespace}{" "}{@.metadata.name}{"\n"}{end}' \
        | /usr/bin/sort)
    if [[ -n "$current_ns" ]]; then
        $KUBECTL -n "$current_ns" delete pods --force --grace-period=0 $pod_list &
        pids="$pids $!"
    fi
    waitall "$pids"
}

for cmd in $@; do "public_$cmd"; done
