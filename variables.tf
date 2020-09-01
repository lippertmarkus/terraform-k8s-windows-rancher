variable "vagrant_enable" {
  description = "Provision local VMs with Vagrant instead of using Azure"
  default     = false
}

variable "vagrant_vswitch" {
  description = "Name of the Hyper-V switch to use for Vagrant VMs (needs internet access)"
  default     = ""
}

variable "azure_resource_group" {
  type = string
  description = "Name of the resource group to create"
  default = "ranchertest"
}