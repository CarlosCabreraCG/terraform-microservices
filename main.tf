
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

# 3.5 Identidad administrada antes que la APP

resource "azurerm_user_assigned_identity" "app_identity" {
  name                = "id-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# 4. Aplicación que ejecutará nuestro contenedor
resource "azurerm_container_app" "app" {
  name                         = "ca-${var.project_name}-${random_string.suffix.result}"
  container_app_environment_id = azurerm_container_app_environment.environment.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  # Asignamos la identidad creada arriba
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app_identity.id]
  }

  # Aseguramos que los permisos existan ANTES de encender el contenedor
  depends_on = [
    azurerm_role_assignment.kv_access,
    azurerm_role_assignment.storage_access
  ]

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

      env {
        name  = "AZURE_KEY_VAULT_URL"
        value = azurerm_key_vault.kv.vault_uri
      }

      env {
        name  = "AZURE_SECRET_NAME"
        value = "mensaje-secreto"
      }

      env {
        name  = "AZURE_STORAGE_ACCOUNT_NAME"
        value = azurerm_storage_account.storage.name
      }

      env {
        name  = "AZURE_STORAGE_CONTAINER_NAME"
        value = azurerm_storage_container.images.name
      }

      env {
        name  = "AZURE_STORAGE_BLOB_NAME"
        value = "imagen.jpg"
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.app_identity.client_id
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

# 5. KEY VAULT

# Obtener información del tenant actual
data "azurerm_client_config" "current" {}

# Crear Key Vault
resource "azurerm_key_vault" "kv" {
  name                = "kv${var.project_name}${random_string.suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled = true

  soft_delete_retention_days = 7
  purge_protection_enabled   = false
}

# Permitir que NestJS lea secretos
resource "azurerm_role_assignment" "kv_access" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app_identity.principal_id
}


# 6. Storage Account

# Crear Storage Account
resource "azurerm_storage_account" "storage" {
  name                     = "st${var.project_name}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
}

# Crear contenedor privado para imágenes
resource "azurerm_storage_container" "images" {
  name                  = "imagenes"
  storage_account_id    = azurerm_storage_account.storage.id
  container_access_type = "private"
}

# Permitir que NestJS lea imágenes
resource "azurerm_role_assignment" "storage_access" {
  scope                = azurerm_storage_account.storage.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.app_identity.principal_id
}

# Permitir al usuario actual administrar secretos
resource "azurerm_role_assignment" "user_kv_access" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Permitir al usuario actual subir imágenes
resource "azurerm_role_assignment" "user_storage_access" {
  scope                = azurerm_storage_account.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}