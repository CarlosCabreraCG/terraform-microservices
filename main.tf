
# Sufijo aleatorio para evitar conflictos de nombres
resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

# 1. Grupo de recursos
resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.project_name}"
  location = var.location
}

# 2. Workspace para almacenar logs
resource "azurerm_log_analytics_workspace" "logs" {
  name                = "law-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# 3. Entorno de Azure Container Apps
resource "azurerm_container_app_environment" "environment" {
  name                       = "cae-${var.project_name}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id
}

# 4. Aplicación que ejecutará nuestro contenedor
resource "azurerm_container_app" "app" {
  name                         = "ca-${var.project_name}-${random_string.suffix.result}"
  container_app_environment_id = azurerm_container_app_environment.environment.id
  resource_group_name           = azurerm_resource_group.rg.name
  revision_mode                 = "Single"

  template {
    min_replicas = 0
    max_replicas = 3

    http_scale_rule {
      name                = "http-scaling"
      concurrent_requests = "10"
    }

    container {
      name   = "microservicio"
      image  = var.docker_image
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "NOMBRE"
        value = var.nombre
      }

      env {
        name  = "MI_VARIABLE"
        value = var.mi_variable
      }

      env {
        name  = "PORT"
        value = "3000"
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 3000
    transport        = "auto"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}
