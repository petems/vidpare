terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }

  required_version = ">= 1.0"
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

data "cloudflare_zone" "vidpare" {
  account_id = var.cloudflare_account_id
  name       = "vidpare.app"
}

resource "cloudflare_pages_project" "vidpare" {
  account_id        = var.cloudflare_account_id
  name              = "vidpare"
  production_branch = "master"

  build_config {
    build_command   = "npm ci && npm run build"
    destination_dir = "dist"
    root_dir        = "site"
    build_caching   = true
  }

  source {
    type = "github"
    config {
      owner                         = "petems"
      repo_name                     = "vidpare"
      production_branch             = "master"
      pr_comments_enabled           = true
      preview_deployment_setting    = "all"
      production_deployment_enabled = true
    }
  }

  deployment_configs {
    production {
      compatibility_date = "2026-01-01"
      fail_open          = true
      usage_model        = "standard"
    }
    preview {
      compatibility_date = "2026-01-01"
      fail_open          = true
      usage_model        = "standard"
    }
  }
}

resource "cloudflare_pages_domain" "apex" {
  account_id   = var.cloudflare_account_id
  project_name = cloudflare_pages_project.vidpare.name
  domain       = "vidpare.app"
}

resource "cloudflare_pages_domain" "www" {
  account_id   = var.cloudflare_account_id
  project_name = cloudflare_pages_project.vidpare.name
  domain       = "www.vidpare.app"
}

resource "cloudflare_record" "apex" {
  zone_id = data.cloudflare_zone.vidpare.id
  name    = "vidpare.app"
  type    = "CNAME"
  content = cloudflare_pages_project.vidpare.subdomain
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "www" {
  zone_id = data.cloudflare_zone.vidpare.id
  name    = "www"
  type    = "CNAME"
  content = cloudflare_pages_project.vidpare.subdomain
  proxied = true
  ttl     = 1
}
