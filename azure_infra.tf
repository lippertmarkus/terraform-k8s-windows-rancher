provider "azurerm" {
    version = "~>2.0"
    features {}
}

# Create a resource group if it doesn't exist
resource "azurerm_resource_group" "rg" {
    count = var.vagrant_enable ? 0 : 1

    name     =  var.azure_resource_group
    location = "westeurope"
}

# Create virtual network
resource "azurerm_virtual_network" "vnet" {
    count = var.vagrant_enable ? 0 : 1

    name                = "myVnet"
    address_space       = ["10.0.0.0/16"]
    location            = "westeurope"
    resource_group_name = azurerm_resource_group.rg[0].name
}

# Create subnet
resource "azurerm_subnet" "subnet" {
    count = var.vagrant_enable ? 0 : 1

    name                 = "mySubnet"
    resource_group_name  = azurerm_resource_group.rg[0].name
    virtual_network_name = azurerm_virtual_network.vnet[0].name
    address_prefixes       = ["10.0.1.0/24"]
}

# Create public IPs for all three VMs
resource "azurerm_public_ip" "pip" {
    count = var.vagrant_enable ? 0 : 3

    name                         = "pip${count.index}"
    location                     = "westeurope"
    resource_group_name          = azurerm_resource_group.rg[0].name
    allocation_method            = "Dynamic"
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "nsg" {
    count = var.vagrant_enable ? 0 : 1

    name                = "nsg"
    location            = "westeurope"
    resource_group_name = azurerm_resource_group.rg[0].name
    
    security_rule {
        name                       = "multi"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_ranges    = ["22","80","443","5985"]
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
}

# Create network interfaces for all three VMs
resource "azurerm_network_interface" "nic" {
    count = var.vagrant_enable ? 0 : 3

    name                      = "nic${count.index}"
    location                  = "westeurope"
    resource_group_name       = azurerm_resource_group.rg[0].name

    ip_configuration {
        name                          = "myNicConfiguration"
        subnet_id                     = azurerm_subnet.subnet[0].id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.pip[count.index].id
    }
}

# Connect the security group to the network interfaces
resource "azurerm_network_interface_security_group_association" "nicassoc" {
    count = var.vagrant_enable ? 0 : 3

    network_interface_id      = azurerm_network_interface.nic[count.index].id
    network_security_group_id = azurerm_network_security_group.nsg[0].id
}

# Create SSH key
resource "tls_private_key" "pk" {
  count = var.vagrant_enable ? 0 : 1

  algorithm = "RSA"
  rsa_bits = 4096
}

# Create VMs for Rancher Server and Kubernetes Linux Node
resource "azurerm_linux_virtual_machine" "linuxvms" {
    count = var.vagrant_enable ? 0 : 2

    name                  = count.index == 0 ? "rancher" : "linux"
    location              = "westeurope"
    resource_group_name   = azurerm_resource_group.rg[0].name
    network_interface_ids = [azurerm_network_interface.nic[count.index].id]
    size                  = "Standard_DS2_v2"

    os_disk {
        caching           = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }

    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "18.04-LTS"
        version   = "latest"
    }

    admin_username = "azadmin"
    disable_password_authentication = true
        
    admin_ssh_key {
        username       = "azadmin"
        public_key     = tls_private_key.pk[0].public_key_openssh
    }
}

# Install Docker on Rancher and Linux VM
resource "azurerm_virtual_machine_extension" "docker" {
  count = var.vagrant_enable ? 0 : 2

  name                 = "docker-provision"
  virtual_machine_id   = azurerm_linux_virtual_machine.linuxvms[count.index].id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"

  settings = <<SETTINGS
    {
        "commandToExecute": "sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common ; curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - ; sudo add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" ; sudo apt-get update ; sudo apt-get install -y docker-ce docker-ce-cli containerd.io"
    }
SETTINGS
}

# generate admin password for Windows VM
resource "random_password" "windows" {
  count = var.vagrant_enable ? 0 : 1

  length = 16
  special = true
}

# Create VM for Kubernetes Windows Node
resource "azurerm_windows_virtual_machine" "windows" {
    count = var.vagrant_enable ? 0 : 1

    name                  = "windows"
    location              = "westeurope"
    resource_group_name   = azurerm_resource_group.rg[0].name
    network_interface_ids = [azurerm_network_interface.nic[2].id]
    size                  = "Standard_DS2_v2"

    os_disk {
        caching           = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }

    source_image_reference {
        publisher = "MicrosoftWindowsServer"
        offer     = "WindowsServer"
        sku       = "2019-Datacenter-Core-with-Containers"
        version   = "latest"
    }

    admin_username = "azadmin"
    admin_password = random_password.windows[0].result

    winrm_listener {
        protocol = "Http"
    }
}

# Setup WinRM on Windows VM (insecure)
resource "azurerm_virtual_machine_extension" "winrm" {
  count = var.vagrant_enable ? 0 : 1
     
  name                 = "winrm-provision"
  virtual_machine_id   = azurerm_windows_virtual_machine.windows[0].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"

  settings = <<SETTINGS
    {
        "commandToExecute": "winrm set winrm/config/service @{AllowUnencrypted = \"true\"}"
    }
SETTINGS
}