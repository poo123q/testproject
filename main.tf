resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "_"
}

resource "azurerm_network_security_group" "sonar" {
  name                = "${var.platform_output.system_name}-sonar"
  location            = var.initialization_output.region
  resource_group_name = var.initialization_output.resource_group_name

  security_rule {
    name                         = "sonar"
    priority                     = 200
    direction                    = "Inbound"
    access                       = "Allow"
    protocol                     = "Tcp"
    source_port_range            = 9000
    destination_port_range       = 9000
    source_address_prefixes      = var.source_address_prefixes
    destination_address_prefixes = var.destination_address_prefixes
  }

  security_rule {
    name                       = "Inbound_TCP_80"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Inbound_TCP_443"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Outbound_TCP_80"
    priority                   = 1003
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Outbound_TCP_443"
    priority                   = 1004
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Outbound_TCP_13"
    priority                   = 4094
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "DenyOutboundTraffic"
    priority                   = 4096
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = merge({
    "Name" = "${var.platform_output.system_name}-sonar"
    },
    local.common_tags
  )
}

resource "azurerm_network_interface" "sonar" {
  name                = "${var.platform_output.system_name}-sonar"
  location            = var.initialization_output.region
  resource_group_name = var.initialization_output.resource_group_name

  ip_configuration {
    name                          = "${var.platform_output.system_name}-sonar"
    subnet_id                     = element(var.initialization_output.private_subnets, 0)
    private_ip_address_allocation = "dynamic"
  }
  tags = merge({
    "Name" = "${var.platform_output.system_name}-sonar"
    },
    local.common_tags
  )
}

resource "azurerm_network_interface_security_group_association" "sonar" {
  network_interface_id      = azurerm_network_interface.sonar.id
  network_security_group_id = azurerm_network_security_group.sonar.id
}

# Create Sonar VM with web server
resource "azurerm_linux_virtual_machine" "sonar" {
  depends_on = [azurerm_network_security_group.sonar, azurerm_network_interface.sonar]

  name                  = "${var.platform_output.system_name}-sonar"
  location              = var.initialization_output.region
  resource_group_name   = var.initialization_output.resource_group_name
  admin_username        = "centos"
  size                  = local.vm_size
  network_interface_ids = [azurerm_network_interface.sonar.id]
  custom_data           = base64encode(data.template_file.sonar.rendered)

  source_image_reference {
    publisher = "OpenLogic"
    offer     = "CentOS"
    sku       = "7.7"
    version   = "latest"
  }

  os_disk {
    name                 = "${var.platform_output.system_name}-sonar"
    disk_size_gb         = 30
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  admin_ssh_key {
    public_key = data.azurerm_key_vault_secret.opensshkey.value
    username   = "centos"
  }

  tags = merge({
    "Name" = "${var.platform_output.system_name}-sonar"
    },
    local.common_tags
  )
}

resource "azurerm_lb" "sonar" {
  name                = "${var.platform_output.system_name}-sonar"
  sku                 = local.lb_sku
  location            = var.initialization_output.region
  resource_group_name = var.initialization_output.resource_group_name

  frontend_ip_configuration {
    name                          = "${var.platform_output.system_name}-sonar"
    subnet_id                     = element(var.initialization_output.private_subnets, 0)
    private_ip_address_allocation = "Dynamic"
  }
  tags = merge({
    "Name" = "${var.platform_output.system_name}-sonar"
    },
    local.common_tags
  )
}

resource "azurerm_lb_backend_address_pool" "sonar" {
  resource_group_name = var.initialization_output.resource_group_name
  loadbalancer_id     = azurerm_lb.sonar.id
  name                = "${var.platform_output.system_name}-sonar"
}

resource "azurerm_lb_probe" "sonar" {
  resource_group_name = var.initialization_output.resource_group_name
  loadbalancer_id     = azurerm_lb.sonar.id
  name                = "${var.platform_output.system_name}-sonar"
  protocol            = "TCP"
  port                = 9000
}

resource "azurerm_network_interface_backend_address_pool_association" "sonar" {
  network_interface_id    = azurerm_network_interface.sonar.id
  ip_configuration_name   = "${var.platform_output.system_name}-sonar"
  backend_address_pool_id = azurerm_lb_backend_address_pool.sonar.id
}

resource "azurerm_lb_rule" "sonar" {
  resource_group_name            = var.initialization_output.resource_group_name
  loadbalancer_id                = azurerm_lb.sonar.id
  name                           = "${var.platform_output.system_name}-sonar"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 9000
  frontend_ip_configuration_name = "${var.platform_output.system_name}-sonar"
  probe_id                       = azurerm_lb_probe.sonar.id
  backend_address_pool_id        = azurerm_lb_backend_address_pool.sonar.id
}

resource "azurerm_storage_account" "sonar" {
  name                     = "${var.platform_output.system_name}sonar"
  resource_group_name      = var.initialization_output.resource_group_name
  location                 = var.initialization_output.region
  account_tier             = var.account_tier
  account_replication_type = var.account_replication_type
  min_tls_version          = "TLS1_2"

  tags = merge({
    "Name" = "${var.platform_output.system_name}-sonar"
    },
    local.common_tags
  )
}

resource "random_id" "this" {
  byte_length = 4
}

resource "azurerm_key_vault_secret" "password" {
  name            = "${var.platform_output.system_name}-sonarqube-${random_id.this.hex}-${var.platform_output.environment_type}"
  value           = local.sonarqube_password
  key_vault_id    = var.initialization_output.key_vault_id[0]
  expiration_date = timeadd(timestamp(), "219000h")
  content_type    = "Password"
  tags            = local.common_tags
}

resource "time_sleep" "wait_15min" {
  depends_on      = [azurerm_linux_virtual_machine.sonar]
  create_duration = "900s"
}

resource "null_resource" "configure_sonar" {
  depends_on = [time_sleep.wait_15min]

  provisioner "remote-exec" {

    inline = [
      "cd /home/centos && sudo yum install -y wget && sudo chmod 755 -R /opt/sonarqube",
      "wget https://downloads.apache.org/logging/log4j/2.17.1/apache-log4j-2.17.1-bin.zip && unzip apache-log4j-2.17.1-bin.zip",
      "sudo cp /home/centos/apache-log4j-2.17.1-bin/log4j-api-2.17.1.jar /opt/sonarqube/elasticsearch/lib/",
      "sudo cp /home/centos/apache-log4j-2.17.1-bin/log4j-core-2.17.1.jar /opt/sonarqube/elasticsearch/lib/",
      "sudo rm -rf /opt/sonarqube/elasticsearch/lib/log4j-core-2.11.1.jar",
      "sudo rm -rf /opt/sonarqube/elasticsearch/lib/log4j-api-2.11.1.jar",
      "sudo chown -R centos:sonar /opt/sonarqube && sudo chmod 755 -R /opt/sonarqube",
      "sudo su -c '/opt/sonarqube/bin/linux-x86-64/sonar.sh restart' - centos"
    ]

    connection {
      host        = azurerm_linux_virtual_machine.sonar.private_ip_address
      user        = "centos"
      type        = "ssh"
      port        = 22
      private_key = local.ssh_connect_key
    }
  }
}

resource "null_resource" "update_password" {
  depends_on = [null_resource.configure_sonar]

  provisioner "remote-exec" {

    inline = [
      "sleep 60",
      "curl -X POST -v -u admin:admin 'http://localhost:9000/api/users/change_password?login=admin&previousPassword=admin&password=${local.sonarqube_password}'",
      "sleep 10",
      "curl -X POST -v -u admin:${local.sonarqube_password} 'http://localhost:9000/api/users/search'"
    ]

    connection {
      host        = azurerm_linux_virtual_machine.sonar.private_ip_address
      user        = "centos"
      type        = "ssh"
      port        = 22
      private_key = local.ssh_connect_key
    }
  }
}

resource "azurerm_private_dns_a_record" "sonar" {
  name                = "${var.platform_output.system_name}-sonarqube-${var.platform_output.environment_type}"
  zone_name           = data.azurerm_private_dns_zone.private.name
  resource_group_name = data.azurerm_private_dns_zone.private.resource_group_name
  ttl                 = 60
  records             = [azurerm_lb.sonar.private_ip_address]
  tags = merge({
    "Name" = "${var.platform_output.system_name}-sonar"
    },
    local.common_tags
  )
}