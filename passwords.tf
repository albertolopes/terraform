resource "random_password" "keycloak_admin" {
  length           = 16
  special          = true
  override_special = "!#%&"
}

resource "random_password" "postgres" {
  length           = 16
  special          = true
  override_special = "!#%&"
}
