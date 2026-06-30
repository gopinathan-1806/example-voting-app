provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "example" {
  name     = "rupesh-devops-rg"
  location = "East US"
}

resource "azurerm_container_registry" "example" {
  name                = "rupeshdevopsacr"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  sku                 = "Basic"
  admin_enabled       = true
}

resource "azurerm_kubernetes_cluster" "example" {
  name                = "rupesh-aks-cluster"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  dns_prefix          = "rupeshaks"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_DS2_v2"
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "example" {
  name                  = "internal"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.example.id
  vm_size               = "Standard_DS2_v2"
  node_count            = 1
  auto_scaling_enabled  = true
  min_count             = 1
  max_count             = 3
}

# Lets AKS pull images from your ACR without manual docker login
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                    = azurerm_kubernetes_cluster.example.kubelet_identity[0].object_id
  role_definition_name            = "AcrPull"
  scope                           = azurerm_container_registry.example.id
  skip_service_principal_aad_check = true
}