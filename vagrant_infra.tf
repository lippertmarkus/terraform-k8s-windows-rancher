resource "vagrant_vm" "vms" {
  count = var.vagrant_enable ? 1 : 0

  vagrantfile_dir = "vagrant"
  env = {
    HYPERV_SWITCH = var.vagrant_vswitch
  }
}