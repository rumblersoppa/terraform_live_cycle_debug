terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.10.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.project_region
  zone    = var.project_zone
}

provider "random" {}

# random string
resource "random_string" "storage_random_name" {
  length  = 6
  special = false
  upper   = false
}

# storage bucket resource
resource "google_storage_bucket" "storage_website" {
  name                        = "mystorage-${random_string.storage_random_name.result}"
  storage_class               = "REGIONAL"
  location                    = var.project_region
  force_destroy               = true
  uniform_bucket_level_access = true
  cors {
    origin          = ["mydomain.com"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["Content-Type"]
    max_age_seconds = 3600
  }
  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
}

# service account
resource "google_service_account" "private_access_gcs" {
  account_id   = "private-access"
  display_name = "Service account used to read cloud storage objects"
}

# service account binding to storage bucket
resource "google_storage_bucket_iam_binding" "private_access_gcs_binding" {
  bucket = google_storage_bucket.storage_website.name
  role   = "roles/storage.objectViewer"

  members = [
    "serviceAccount:${google_service_account.private_access_gcs.email}"
  ]
}

# create hmac key
resource "google_storage_hmac_key" "private_access_gcs_hmac_key" {
  service_account_email = google_service_account.private_access_gcs.email
}

# create NEG for backend services
resource "google_compute_global_network_endpoint_group" "global_neg_mytest" {
  name                  = "global-neg-mytest"
  default_port          = "443"
  network_endpoint_type = "INTERNET_FQDN_PORT"
}

resource "google_compute_global_network_endpoint" "global_neg_mytest_endpoint" {
  global_network_endpoint_group = google_compute_global_network_endpoint_group.global_neg_mytest.name
  fqdn                          = "c.storage.googleapis.com"
  port                          = 443
}

# create backend service
resource "google_compute_backend_service" "backend_service_mytest" {
  name                  = google_storage_bucket.storage_website.name
  project               = var.project_id
  description           = "Global Backend Service for Assinatura Website"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTPS"
  session_affinity      = "NONE"
  timeout_sec           = 60
  enable_cdn            = false

  backend {
    group           = google_compute_global_network_endpoint_group.global_neg_mytest.self_link
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }

  custom_request_headers = [
    "host:${google_storage_bucket.storage_website.name}",
    "cookie:",
  ]

  custom_response_headers = ["X-Frame-Options:SAMEORIGIN", "X-XSS-Protection:1; mode=block"]

  lifecycle {
    ignore_changes = [
      security_settings,
    ]
  }

  log_config {
    enable = false
  }
}

# create null_resource for gcloud command update backend service
# and add securety Settings
resource "null_resource" "update_backend_service_assinatura_website" {
  depends_on = [google_compute_backend_service.backend_service_mytest]
  provisioner "local-exec" {
    command = <<-EOT
      curl -X PATCH \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $(gcloud auth print-access-token)" \
      -d '{
        "securitySettings": {
          "awsV4Authentication": {
            "accessKeyId": "${google_storage_hmac_key.private_access_gcs_hmac_key.access_id}",
            "accessKey": "${google_storage_hmac_key.private_access_gcs_hmac_key.secret}",
            "originRegion": "${var.project_region}"
          }
        }
      }' \
      "https://compute.googleapis.com/compute/v1/projects/${var.project_id}/global/backendServices/${google_compute_backend_service.backend_service_mytest.name}"
    EOT
  }
}
