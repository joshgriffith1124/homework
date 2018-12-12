# Homework
## Create the EKS cluster via terraform.
* Clone the repo.
* Hop into the repo root.
* cd /terraform/eks
* terraform init
* terraform plan -var-file=./eks-mytime/eks-mytime.tfvars -state=./eks-mytime/terraform.tfstate -out=./eks-mytime/tf.plan
* terraform apply -state-out=./eks-mytime/terraform.tfstate ./eks-mytime/tf.plan
* __Once terraform completes you will have a functioning EKS backplane but no joined workers or access to the cluster.__

## Configure client/cluster

### Install dependencies.
* [Kubectl setup docs](https://kubernetes.io/docs/tasks/tools/install-kubectl/) - Install kubectl
* [Install IAM authenticator for EKS](https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html) - Basically download the binary and put it somwhere in $PATH

#### AWS CLI
* aws eks update-kubeconfig --name eks-mytime

#### EKS worker config - Allows workers to join cluster.
* kubectl apply -f ./kubernetes/aws_auth.yml

## Helm
### Installation

* [Helm install docs](https://docs.helm.sh/using_helm/#installing-helm) (Install tiller in cluster)

### Sentry Chart
* helm install --name mytime -f ./kubernetes/sentry/values.yml stable/sentry
* __Sentry will now be running in the cluster and you can proxy the endpoint to your local machine.__

## Notes
* ___This is not a production ready example.  I skipped quite a few things in the interest of keeping the time investment reasonable.___
 * The terraform is raw, I would wrap it up in a module given more time.
 * There is no ingress controller installed within the cluster.  This would set up an ELB/ngnix to give external https access the Sentry endpoint.
 * External-dns is not installed so you can't handle DNS for the ingress.

