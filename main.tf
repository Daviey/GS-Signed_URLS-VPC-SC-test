terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.42.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "google" {
  project     = var.project_id
  region      = var.region
  credentials = file(var.credentials_file)
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "organization_id" {
  type = string
}

variable "credentials_file" {
  type = string
}

variable "bucket_location" {
  type = string
}

variable "vpc_network_name" {
  type = string
}

variable "vpc_subnet_name" {
  type = string
}

variable "vpc_subnet_cidr" {
  type = string
}

variable "enable_vpc_sc" {
  type = bool
}

variable "disable_vpc_sc" {
  type    = bool
  default = false
}

data "google_project" "project" {}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "google_compute_network" "vpc_network" {
  name                    = var.vpc_network_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "vpc_subnet" {
  name          = var.vpc_subnet_name
  ip_cidr_range = var.vpc_subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc_network.id
}

resource "google_storage_bucket" "sample_bucket" {
  name                        = "sample-bucket-${random_id.bucket_suffix.hex}"
  location                    = var.bucket_location
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_object" "sample_file" {
  name         = "sample.txt"
  bucket       = google_storage_bucket.sample_bucket.name
  content      = "This is a sample file for testing VPC Service Controls."
  content_type = "text/plain"
}

resource "google_service_account" "signed_url_sa" {
  account_id   = "signed-url-sa"
  display_name = "Signed URL Service Account"
}

resource "google_storage_bucket_iam_member" "signed_url_creator" {
  bucket = google_storage_bucket.sample_bucket.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.signed_url_sa.email}"
}

resource "google_service_account_key" "signed_url_sa_key" {
  service_account_id = google_service_account.signed_url_sa.name
}

data "google_storage_object_signed_url" "pre_vpc_sc_signed_url" {
  bucket      = google_storage_bucket.sample_bucket.name
  path        = google_storage_bucket_object.sample_file.name
  credentials = base64decode(google_service_account_key.signed_url_sa_key.private_key)
}

data "google_storage_object_signed_url" "additional_pre_vpc_sc_signed_url" {
  bucket      = google_storage_bucket.sample_bucket.name
  path        = google_storage_bucket_object.sample_file.name
  credentials = base64decode(google_service_account_key.signed_url_sa_key.private_key)
  extension_headers = {
    "x-goog-custom-header" = "custom_value"
  }
}

resource "google_access_context_manager_access_policy" "access_policy" {
  count  = var.disable_vpc_sc ? 0 : (var.enable_vpc_sc ? 1 : 0)
  parent = "organizations/${var.organization_id}"
  title  = "VPC SC Policy"
}

resource "google_access_context_manager_service_perimeter" "service_perimeter" {
  count          = var.disable_vpc_sc ? 0 : (var.enable_vpc_sc ? 1 : 0)
  parent         = "accessPolicies/${google_access_context_manager_access_policy.access_policy[0].name}"
  name           = "accessPolicies/${google_access_context_manager_access_policy.access_policy[0].name}/servicePerimeters/restrict_storage"
  title          = "restrict_storage"
  perimeter_type = "PERIMETER_TYPE_REGULAR"

  status {
    restricted_services = ["storage.googleapis.com"]
    resources           = ["projects/${data.google_project.project.number}"]

    vpc_accessible_services {
      enable_restriction = true
      allowed_services   = ["storage.googleapis.com"]
    }

    ingress_policies {
      ingress_from {
        identities = ["serviceAccount:${google_service_account.signed_url_sa.email}"]
        sources {
          resource = "projects/${data.google_project.project.number}"
        }
      }
      ingress_to {
        resources = ["projects/${data.google_project.project.number}"]
        operations {
          service_name = "storage.googleapis.com"
          method_selectors {
            method = "google.storage.objects.get"
          }
        }
      }
    }
  }
}

data "google_storage_object_signed_url" "post_vpc_sc_signed_url" {
  bucket      = google_storage_bucket.sample_bucket.name
  path        = google_storage_bucket_object.sample_file.name
  credentials = base64decode(google_service_account_key.signed_url_sa_key.private_key)
  extension_headers = {
    "x-goog-custom-header" = "custom_value"
  }

  depends_on = [google_access_context_manager_service_perimeter.service_perimeter]
}

output "bucket_name" {
  value = google_storage_bucket.sample_bucket.name
}

output "pre_vpc_sc_signed_url" {
  value     = data.google_storage_object_signed_url.pre_vpc_sc_signed_url.signed_url
  sensitive = true
}

output "additional_pre_vpc_sc_signed_url" {
  value     = data.google_storage_object_signed_url.additional_pre_vpc_sc_signed_url.signed_url
  sensitive = true
}

output "post_vpc_sc_signed_url" {
  value     = var.enable_vpc_sc ? data.google_storage_object_signed_url.post_vpc_sc_signed_url.signed_url : "VPC-SC not enabled"
  sensitive = true
}

output "vpc_sc_status" {
  value = var.enable_vpc_sc ? "Enabled" : "Disabled"
}

output "test_pre_vpc_sc_signed_url_command" {
  value = "curl -s '${data.google_storage_object_signed_url.pre_vpc_sc_signed_url.signed_url}'"
}

output "test_additional_pre_vpc_sc_signed_url_command" {
  value = "curl -s -H 'x-goog-custom-header: custom_value' '${data.google_storage_object_signed_url.additional_pre_vpc_sc_signed_url.signed_url}'"
}

output "test_post_vpc_sc_signed_url_command" {
  value = var.enable_vpc_sc ? "curl -s -H 'x-goog-custom-header: custom_value' '${data.google_storage_object_signed_url.post_vpc_sc_signed_url.signed_url}'" : "VPC-SC not enabled"
}

output "test_direct_access_command" {
  value = "gsutil cat gs://${google_storage_bucket.sample_bucket.name}/${google_storage_bucket_object.sample_file.name}"
}
