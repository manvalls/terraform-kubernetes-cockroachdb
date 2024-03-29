# CA

resource "tls_private_key" "cockroachdb_ca" {
  algorithm = "RSA"
}

resource "tls_self_signed_cert" "cockroachdb_ca" {
  private_key_pem = tls_private_key.cockroachdb_ca.private_key_pem

  subject {
    organization = "Cockroach"
    common_name  = "Cockroach CA"
  }

  validity_period_hours = var.cert_validity_period_hours
  early_renewal_hours   = var.cert_early_renewal_hours
  is_ca_certificate     = true

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth",
    "cert_signing"
  ]
}

# Node

resource "tls_private_key" "cockroachdb_node" {
  algorithm = "RSA"
}

resource "tls_cert_request" "cockroachdb_node" {
  private_key_pem = tls_private_key.cockroachdb_node.private_key_pem
  ip_addresses    = ["127.0.0.1"]
  dns_names = [
    "localhost",
    "${var.name}-public",
    "${var.name}-public.${var.namespace}",
    "${var.name}-public.${var.namespace}.svc.cluster.local",
    "*.${var.name}",
    "*.${var.name}.${var.namespace}",
    "*.${var.name}.${var.namespace}.svc.cluster.local"
  ]

  subject {
    organization = "Cockroach"
  }
}

resource "tls_locally_signed_cert" "cockroachdb_node" {
  cert_request_pem   = tls_cert_request.cockroachdb_node.cert_request_pem
  ca_private_key_pem = tls_private_key.cockroachdb_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.cockroachdb_ca.cert_pem

  validity_period_hours = var.cert_validity_period_hours
  early_renewal_hours   = var.cert_early_renewal_hours

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth"
  ]
}

resource "kubernetes_secret" "cockroachdb_node_cert" {
  metadata {
    name      = "${var.name}.node"
    namespace = var.namespace
  }

  data = {
    "ca.crt"   = tls_self_signed_cert.cockroachdb_ca.cert_pem
    "node.crt" = tls_locally_signed_cert.cockroachdb_node.cert_pem
    "node.key" = tls_private_key.cockroachdb_node.private_key_pem
  }
}

# Clients

resource "tls_private_key" "cockroachdb_client" {
  for_each  = toset(var.client_cert_users)
  algorithm = "RSA"
}

resource "tls_cert_request" "cockroachdb_client" {
  for_each        = toset(var.client_cert_users)
  private_key_pem = tls_private_key.cockroachdb_client[each.key].private_key_pem
  dns_names       = [each.key]

  subject {
    common_name  = each.key
    organization = "Cockroach"
  }
}

resource "tls_locally_signed_cert" "cockroachdb_client" {
  for_each           = toset(var.client_cert_users)
  cert_request_pem   = tls_cert_request.cockroachdb_client[each.key].cert_request_pem
  ca_private_key_pem = tls_private_key.cockroachdb_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.cockroachdb_ca.cert_pem

  validity_period_hours = var.cert_validity_period_hours
  early_renewal_hours   = var.cert_early_renewal_hours

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "client_auth"
  ]
}

resource "kubernetes_secret" "cockroachdb_client_cert" {
  for_each = toset(var.client_cert_users)

  metadata {
    name      = "${var.name}.client.${each.key}"
    namespace = var.namespace
  }

  data = {
    "ca.crt"                 = tls_self_signed_cert.cockroachdb_ca.cert_pem
    "client.${each.key}.crt" = tls_locally_signed_cert.cockroachdb_client[each.key].cert_pem
    "client.${each.key}.key" = tls_private_key.cockroachdb_client[each.key].private_key_pem
  }
}
