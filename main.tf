terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.70.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = var.true
    }
  }
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.name}"
  location = var.location
}

resource "azurerm_storage_account" "rg" {
  name                     = var.name
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = var.account_tier
  account_replication_type = var.account_replication_type
}


resource "azurerm_storage_container" "container" {
  name                  = var.name
  storage_account_name  = azurerm_storage_account.rg.name
  container_access_type = var.private
}

resource "azurerm_key_vault" "keyvault" {
  name                        = "${var.name}1kv"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  enabled_for_disk_encryption = var.true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = var.soft_delete_retention_days
  purge_protection_enabled    = var.false
  sku_name                    = var.standard

  access_policy {
    tenant_id           = data.azurerm_client_config.current.tenant_id
    object_id           = data.azuread_group.ad.object_id
    key_permissions     = var.key_permissions
    secret_permissions  = var.secret_permissions
    storage_permissions = var.storage_permissions
  }

  network_acls {
    bypass                     = var.bypass
    default_action             = var.default_action
    ip_rules                   = var.ip_rules
    virtual_network_subnet_ids = azurerm_subnet.subnet[*].id
  }
}

resource "azurerm_mssql_server" "srv" {
  name                         = "mssqlserver${var.name}"
  resource_group_name          = azurerm_resource_group.rg.name     #était data.azurerm_resource_group.p.name
  location                     = azurerm_resource_group.rg.location #était data.azurerm_resource_group.p.name
  version                      = var.versionMSServer
  administrator_login          = var.AdminLoginMSServer
  administrator_login_password = random_password.password.result
  minimum_tls_version          = var.MiniTtlVersion
}


resource "random_password" "password" {
  length           = 16
  special          = var.true
  number           = var.true
  upper            = var.true
  min_numeric      = 1
  min_upper        = 1
  min_special      = 1
  override_special = var.override_special
}

resource "azurerm_key_vault_secret" "secret-valt" {
  name         = "admin-password"
  value        = random_password.password.result
  key_vault_id = azurerm_key_vault.keyvault.id
}


resource "azurerm_log_analytics_workspace" "analitics" {
  #count               = var.log
  #name                = "benprd${count.index}"
  name                = var.name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_monitor_diagnostic_setting" "rule" {
  name                       = "send${var.name}"
  target_resource_id         = azurerm_key_vault.keyvault.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.analitics.id

  log {
    category = "AuditEvent"
    enabled  = var.true

    retention_policy {
      enabled = var.false
    }
  }
}


resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.name}"
  address_space       = var.address_space
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  count                                          = 3
  name                                           = "${var.name}-${count.index}"
  resource_group_name                            = azurerm_resource_group.rg.name
  virtual_network_name                           = azurerm_virtual_network.vnet.name
  address_prefixes                               = ["10.0.${count.index}.0/24"]
  enforce_private_link_endpoint_network_policies = var.true
  service_endpoints                              = var.service_endpoints
}
#Utilise Un Private Endpoint et une Private Service Connection pour connecter notre keyvault à notre sunbet 0.

resource "azurerm_private_endpoint" "p-endpoint" {
  name                = "endpoint-${var.name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.subnet[0].id

  private_service_connection {
    name                           = "privateServiceConnection-${var.name}"
    private_connection_resource_id = azurerm_key_vault.keyvault.id
    is_manual_connection           = var.false
    subresource_names              = var.subresource_names
  }
}
# DEPLOYER UN PRIVATE ENDPOINT ET UNE PRIVATE SERVICE CONNECTION SUR VOTRE SQL SERVEUR
# SUR UN DE VOS SUBNETS
resource "azurerm_private_endpoint" "p-endpoint-sql" {
  name                = "endpoint-${var.name}-sql"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.subnet[0].id

  private_service_connection {
    name                           = "privateServiceConnection-${var.name}-sql"
    private_connection_resource_id = azurerm_mssql_server.srv.id
    is_manual_connection           = var.false
    subresource_names              = var.subresource_names_sql
  }
}

#DEPLOYER UNE VM WINDOWS SERVER, AVEC LA SIZE LA MOINS CHER Standard_B1ls.
#NO SCALE.
#NO REDUNDANCY. HDD DISK .
#NO PUBLIC IP
#DEPLOYER 1 DISK SUPPLEMENTAIRE A ATTACHER A VOTRE VM
#A FAIRE SI VOUS VOULEZ : BOOT DIAGNOSTIC


resource "azurerm_network_interface" "interface" {
  name                = "netinterface-${var.name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = var.ip_configuration_name
    subnet_id                     = azurerm_subnet.subnet[0].id
    private_ip_address_allocation = var.ip_configuration_private_ip_address_allocation
  }
}

resource "azurerm_windows_virtual_machine" "vmachine" {
  name                = "vm-${var.name}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.vmachine_size
  admin_username      = var.vmachine_admin
  admin_password      = random_password.password.result

  network_interface_ids = [
    azurerm_network_interface.interface.id,
  ]

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.rg.primary_blob_endpoint
  }

  os_disk {
    caching              = var.vmachine_on_disk_caching
    storage_account_type = var.vmachine_on_disk_storage_account_type
  }

  source_image_reference {
    publisher = var.vmachine_source_image_reference_publisher
    offer     = var.vmachine_source_image_reference_offer
    sku       = var.vmachine_source_image_reference_sku
    version   = var.vmachine_source_image_reference_version
  }
}

resource "azurerm_managed_disk" "managed" {
  name                 = "${var.name}-disk1"
  location             = azurerm_resource_group.rg.location
  resource_group_name  = azurerm_resource_group.rg.name
  storage_account_type = var.vmachine_on_disk_storage_account_type
  create_option        = "Empty"
  disk_size_gb         = 10
}

resource "azurerm_virtual_machine_data_disk_attachment" "add" {
  managed_disk_id    = azurerm_managed_disk.managed.id
  virtual_machine_id = azurerm_windows_virtual_machine.vmachine.id
  lun                = "10"
  caching            = var.vmachine_on_disk_caching
}

resource "azurerm_key_vault_secret" "secret-vm" {
  name         = "admin-password-vm"
  value        = random_password.password.result
  key_vault_id = azurerm_key_vault.keyvault.id
}

# FOREACH DEPLOYER 2 RESOURCE GROUP, 1 EN WEST EUROPE, 1 EN WEST US.
# VARIABLES NECESSAIRES POUR CET EXO

resource "azurerm_resource_group" "forE" {
  for_each = var.test
  name     = each.value.name
  location = each.value.location
}
/*
resource "azurerm_resource_group" "reg" {
  for_each = {
    "${var.name}-eu" = "West Europe"
    "${var.name}-us" = "West US"
  }
  name     = each.key
  location = each.value
}
*/

#AJOUTER 3 DISKS EN FOREACH ET LES ATTACHER SUR NOTRE VM.
#1 = 10
#2 = 5
#3 = 20

#AJOUTER DES TAGS DIFFERENTS
#1 = tag = disk = 1
#2 = tag = disk = 2
#3 = tag = disk = 3

resource "azurerm_managed_disk" "managedNew" {
  for_each             = var.disk
  name                 = each.value.name
  location             = azurerm_resource_group.rg.location
  resource_group_name  = azurerm_resource_group.rg.name
  storage_account_type = var.vmachine_on_disk_storage_account_type
  create_option        = "Empty"
  disk_size_gb         = each.value.disk_size_gb
}

resource "azurerm_virtual_machine_data_disk_attachment" "addAll" {
  for_each           = var.disk
  managed_disk_id    = azurerm_managed_disk.managedNew[each.key].id
  virtual_machine_id = azurerm_windows_virtual_machine.vmachine.id
  lun                = each.value.lun
  caching            = var.vmachine_on_disk_caching
}
/*
module "sql_database" {
  source         = "./modules/db"
  name           = "database-${var.name}"
  server_id      = azurerm_mssql_server.srv.id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  license_type   = "LicenseIncluded"
  max_size_gb    = 4
  read_scale     = true
  sku_name       = "BC_Gen5_2"
  zone_redundant = true
}
*/
resource "azurerm_storage_account_network_rules" "test" {
  storage_account_name       = azurerm_storage_account.rg.name
  default_action             = var.default_action
  ip_rules                   = var.ip_rules
  virtual_network_subnet_ids = [azurerm_subnet.subnet[0].id]
  resource_group_name        = azurerm_resource_group.rg.name
}

#CREER UN USER AAD / GROUP AAD
#LUI ASSIGNER LES DROITS "CONTRIBUTOR" sur ma souscription
resource "azuread_user" "user" {
  user_principal_name = "ben@deletoilleprooutlook.onmicrosoft.com"
  display_name        = "benjaminpradon"
  mail_nickname       = "bpradon"
  password            = "Bonjour123!"
}

data "azurerm_subscription" "primary" {
}

data "azurerm_client_config" "example" {
}

resource "azurerm_role_assignment" "example" {
  scope                = data.azurerm_subscription.primary.id
  role_definition_name = "Contributor"
  principal_id         = azuread_user.user.id
}


data "azurerm_storage_account_sas" "example" {
  connection_string = azurerm_storage_account.rg.primary_connection_string
  https_only        = true

  resource_types {
    service   = true
    container = false
    object    = false
  }

  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  start  = "2021-04-30T00:00:00Z"
  expiry = "2023-04-30T00:00:00Z"

  permissions {
    read    = true
    write   = true
    delete  = true
    list    = true # au minimun
    add     = true
    create  = true
    update  = true
    process = true
  }
}

output "sa" {
  value = data.azurerm_storage_account_sas.example.expiry
}

output "sas" {
  value = nonsensitive("https://${azurerm_storage_account.rg.name}.blob.core.windows.net/${data.azurerm_storage_account_sas.example.sas}") 
  sensitive = true
}