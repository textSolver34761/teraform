data "azurerm_client_config" "current" {}

data "azuread_group" "ad" {
  display_name     = "group_studient"
  security_enabled = true
}

data "azurerm_resource_group" "p" {
  name = "rg-raphd"
}

