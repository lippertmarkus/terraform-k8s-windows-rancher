# terraform-k8s-windows-rancher

Terraform definition for provisioning VMs in Azure or locally via Vagrant to create a Kubernetes cluster with Windows support via Rancher for testing purposes.

You can find a detailed explanation in [the blog post](https://lippertmarkus.com/2020/09/01/k8s-windows-rancher/).

# Deployment

You need to install [Terraform](https://www.terraform.io/) before deploying on Azure or locally via Vagrant.

## Deployment on Azure

Install [the Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-windows?view=azure-cli-latest&tabs=azure-cli) and execute the following in the directory of the cloned repository:

```bash
az login  # log in to your Azure account
terraform init  # initialize terraform
terraform apply -auto-approve  # provision infrastructure
```

## Deployment on local machine via Vagrant and Hyper-V

Install [Vagrant](https://www.vagrantup.com/downloads) as well as [Hyper-V](https://docs.microsoft.com/de-de/virtualization/hyper-v-on-windows/quick-start/enable-hyper-v) and use the following commands instead:

```bash
terraform init  # initialize terraform
terraform apply -auto-approve -var 'vagrant_enable=true' -var 'vagrant_vswitch=myswitch'  # provision infrastructure
```

The parameter `vagrant_vswitch` must be set to the name of a virtual switch with external connectivity. It can be found via the *Manager for virtual switches* inside the *Hyper-V Manager*.