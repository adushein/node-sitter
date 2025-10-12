# node-sitter
This helm chart covers following maintenance tasks in Yandex Cloud Managed Kubernetes cluster
  -  tidily drains pods on preemptible nodes
  -  sets proxy environment variables for container runtime (containerd or docker)
  -  adds custom certificate to the node's trusted certificate authority store
  -  adds custom command line arguments for the kubelet process

