terraform {
  required_version = ">= 0.13.0"
  required_providers {
    vagrant = {
      source = "lippertmarkus/vagrant"
      version = "2.0.0"
    }
    rancher2 = {
      source = "rancher/rancher2"
      version = "1.10.1"
    }
  }
}

# Some variables for making connections with the VMs for installing Rancher and creating a new Kubernetes cluster
locals {
  # Vagrant-specific
  rancher_index = var.vagrant_enable ? index(vagrant_vm.vms[0].machine_names, "rancher") : 0
  linux_index   = var.vagrant_enable ? index(vagrant_vm.vms[0].machine_names, "linux") : 0
  windows_index = var.vagrant_enable ? index(vagrant_vm.vms[0].machine_names, "windows") : 0


  # Settings for accessing the three VMs created by Azure or Vagrant

  rancher_user         = var.vagrant_enable ? vagrant_vm.vms[0].ssh_config[local.rancher_index].user        : azurerm_linux_virtual_machine.linuxvms[0].admin_username
  rancher_private_key  = var.vagrant_enable ? vagrant_vm.vms[0].ssh_config[local.rancher_index].private_key : tls_private_key.pk[0].private_key_pem
  rancher_port         = var.vagrant_enable ? vagrant_vm.vms[0].ssh_config[local.rancher_index].port        : 22
  rancher_host         = var.vagrant_enable ? vagrant_vm.vms[0].ssh_config[local.rancher_index].host        : azurerm_linux_virtual_machine.linuxvms[0].public_ip_address

  linux_user         = var.vagrant_enable ? vagrant_vm.vms[0].ssh_config[local.linux_index].user        : azurerm_linux_virtual_machine.linuxvms[1].admin_username
  linux_private_key  = var.vagrant_enable ? vagrant_vm.vms[0].ssh_config[local.linux_index].private_key : tls_private_key.pk[0].private_key_pem
  linux_port         = var.vagrant_enable ? vagrant_vm.vms[0].ssh_config[local.linux_index].port        : 22
  linux_host         = var.vagrant_enable ? vagrant_vm.vms[0].ssh_config[local.linux_index].host        : azurerm_linux_virtual_machine.linuxvms[1].public_ip_address
  linux_private_host = var.vagrant_enable ? local.linux_host                                            : azurerm_linux_virtual_machine.linuxvms[1].private_ip_address

  windows_user         = var.vagrant_enable ? vagrant_vm.vms[0].ssh_config[local.windows_index].user : azurerm_windows_virtual_machine.windows[0].admin_username
  windows_password     = var.vagrant_enable ? "vagrant"                                              : azurerm_windows_virtual_machine.windows[0].admin_password
  windows_host         = var.vagrant_enable ? vagrant_vm.vms[0].ssh_config[local.windows_index].host : azurerm_windows_virtual_machine.windows[0].public_ip_address
  windows_private_host = var.vagrant_enable ? local.windows_host                                     : azurerm_windows_virtual_machine.windows[0].private_ip_address
}

# Resource for starting Rancher container
resource "null_resource" "rancher_node" {
  depends_on = [azurerm_virtual_machine_extension.docker[0], azurerm_network_security_group.nsg[0]]  # wait until docker is deployed and network available (only if azure is used)

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = local.rancher_user
      private_key = local.rancher_private_key
      port        = local.rancher_port
      host        = local.rancher_host
    }

    inline = ["sudo docker run -d --restart=unless-stopped -p 80:80 -p 443:443 rancher/rancher"]
  }
}

# Provider config for bootstrapping Rancher
provider "rancher2" {
  alias = "bootstrap"

  api_url   = "https://${local.rancher_host}"
  bootstrap = true
  insecure  = true
}

# generate admin password for Rancher
resource "random_password" "rancher" {
  length = 16
  special = true
}

# Bootstrap the new rancher installation
resource "rancher2_bootstrap" "bootstrap" {
  provider = rancher2.bootstrap

  password  = random_password.rancher.result
  telemetry = false

  depends_on = [null_resource.rancher_node]  # wait until rancher server container is started 
}

# Provider config for Rancher administration
provider "rancher2" {
  alias = "admin"

  api_url = rancher2_bootstrap.bootstrap.url
  token_key = rancher2_bootstrap.bootstrap.token
  insecure = true
}

# Create a Kubernetes cluster supporting Windows via Rancher
resource "rancher2_cluster" "test" {
  provider = rancher2.admin

  name = "test"
  windows_prefered_cluster = true

  rke_config {
    network {
      plugin = "flannel"

      options = {
        flannel_backend_port = 4789
        flannel_backend_type = "vxlan"
        flannel_backend_vni = 4096
      }
    }
  }
}

# Resource for provisioning Kubernetes Linux node
resource "null_resource" "lin_node" {
  depends_on = [azurerm_virtual_machine_extension.docker[1], azurerm_network_security_group.nsg[0]]  # wait until docker is deployed and network available (only if azure is used)

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = local.linux_user
      private_key = local.linux_private_key
      port        = local.linux_port
      host        = local.linux_host
    }

    inline = ["${rancher2_cluster.test.cluster_registration_token[0].node_command} --address ${local.linux_host} --internal-address ${local.linux_private_host} --etcd --controlplane --worker"]
  }
}

# Resource for provisioning Kubernetes Windows node
resource "null_resource" "win_node" {
  depends_on = [azurerm_virtual_machine_extension.winrm[0], azurerm_network_security_group.nsg[0]]  # wait until network available (only if azure is used)

  provisioner "remote-exec" {
    connection {
      type     = "winrm"
      user     = local.windows_user
      password = local.windows_password
      host     = local.windows_host
      insecure = true
      use_ntlm = var.vagrant_enable ? false : true
    }

    inline = [replace(rancher2_cluster.test.cluster_registration_token[0].windows_node_command, "| iex}", "--address ${local.windows_host} --internal-address ${local.windows_private_host} --worker | iex}")]
  }
}