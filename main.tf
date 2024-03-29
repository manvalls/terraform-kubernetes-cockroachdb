resource "kubernetes_service_account" "cockroachdb" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels = {
      app = var.name
    }
  }
}

resource "kubernetes_role" "cockroachdb" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels = {
      app = var.name
    }
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get"]
  }
}

resource "kubernetes_role_binding" "cockroachdb" {
  depends_on = [kubernetes_role.cockroachdb, kubernetes_service_account.cockroachdb]

  metadata {
    name = var.name
    labels = {
      app = var.name
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = var.name
  }

  subject {
    kind      = "ServiceAccount"
    name      = var.name
    namespace = var.namespace
  }
}

resource "kubernetes_service" "cockroachdb_public" {
  metadata {
    name      = "${var.name}-public"
    namespace = var.namespace
    labels = {
      app = var.name
    }
  }

  spec {
    port {
      port        = 26257
      target_port = 26257
      name        = "grpc"
    }

    port {
      port        = 8080
      target_port = 8080
      name        = "http"
    }

    selector = {
      app = var.name
    }
  }
}

resource "kubernetes_service" "cockroachdb" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels = {
      app = var.name
    }
  }

  spec {
    port {
      port        = 26257
      target_port = 26257
      name        = "grpc"
    }

    port {
      port        = 8080
      target_port = 8080
      name        = "http"
    }

    publish_not_ready_addresses = true
    cluster_ip                  = "None"

    selector = {
      app = var.name
    }
  }
}

resource "kubernetes_pod_disruption_budget" "cockroachdb" {
  metadata {
    name      = "${var.name}-budget"
    namespace = var.namespace
    labels = {
      app = var.name
    }
  }

  spec {
    selector {
      match_labels = {
        app = var.name
      }
    }

    max_unavailable = 1
  }
}

resource "kubernetes_stateful_set" "cockroachdb" {
  depends_on = [
    kubernetes_service_account.cockroachdb,
    kubernetes_service.cockroachdb,
    kubernetes_service.cockroachdb_public,
    kubernetes_pod_disruption_budget.cockroachdb
  ]

  metadata {
    name      = var.name
    namespace = var.namespace
  }

  spec {
    service_name = var.name
    replicas     = var.replicas
    selector {
      match_labels = {
        app = var.name
      }
    }

    template {
      metadata {
        labels = {
          app = var.name
        }
      }

      spec {
        node_selector        = var.nodeSelector
        service_account_name = var.name

        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_expressions {
                    key      = "app"
                    operator = "In"
                    values   = [var.name]
                  }
                }
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }

        container {
          name  = "cockroachdb"
          image = var.image

          resources {
            requests = {
              cpu    = var.container_cpu
              memory = var.container_memory
            }

            limits = {
              cpu    = var.container_cpu
              memory = var.container_memory
            }
          }

          port {
            container_port = 26257
            name           = "grpc"
          }

          port {
            container_port = 8080
            name           = "http"
          }

          readiness_probe {
            http_get {
              path   = "/health?ready=1"
              port   = "http"
              scheme = "HTTPS"
            }

            initial_delay_seconds = 10
            period_seconds        = 5
            failure_threshold     = 2
          }

          volume_mount {
            name       = "datadir"
            mount_path = "/cockroach/cockroach-data"
          }

          volume_mount {
            name       = "certs"
            mount_path = "/cockroach/cockroach-certs"
          }

          env {
            name  = "COCKROACH_CHANNEL"
            value = "kubernetes-secure"
          }

          dynamic "env" {
            for_each = var.container_cpu != null ? [1] : []
            content {
              name = "GOMAXPROCS"
              value_from {
                resource_field_ref {
                  resource = "limits.cpu"
                  divisor  = "1"
                }
              }
            }
          }

          dynamic "env" {
            for_each = var.container_memory != null ? [1] : []
            content {
              name = "MEMORY_LIMIT_MIB"
              value_from {
                resource_field_ref {
                  resource = "limits.memory"
                  divisor  = "1Mi"
                }
              }
            }
          }

          command = var.container_memory != null ? ["/bin/bash", "-ecx", "exec /cockroach/cockroach start --logtostderr --certs-dir /cockroach/cockroach-certs --advertise-host $(hostname -f) --http-addr 0.0.0.0 --join ${join(",", [for i in range(var.replicas) : format("%s-%d.%s", var.name, i, var.name)])} --cache $(expr $MEMORY_LIMIT_MIB / 4)MiB --max-sql-memory $(expr $MEMORY_LIMIT_MIB / 4)MiB"] : ["/bin/bash", "-ecx", "exec /cockroach/cockroach start --logtostderr --certs-dir /cockroach/cockroach-certs --advertise-host $(hostname -f) --http-addr 0.0.0.0 --join ${join(",", [for i in range(var.replicas) : format("%s-%d.%s", var.name, i, var.name)])}"]
        }

        termination_grace_period_seconds = 60

        volume {
          name = "datadir"
          persistent_volume_claim {
            claim_name = "datadir"
          }
        }

        volume {
          name = "certs"
          secret {
            secret_name  = "${var.name}.node"
            default_mode = 256
          }
        }
      }
    }

    pod_management_policy = "Parallel"
    update_strategy {
      type = "RollingUpdate"
    }

    volume_claim_template {
      metadata {
        name = "datadir"
      }

      spec {
        storage_class_name = var.storage_class
        access_modes       = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = var.storage_size
          }
        }
      }
    }
  }
}
