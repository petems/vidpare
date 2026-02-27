variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string

  validation {
    condition     = trimspace(var.cloudflare_account_id) != ""
    error_message = "cloudflare_account_id must be a non-empty string."
  }
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Pages permissions"
  type        = string
  sensitive   = true

  validation {
    condition     = trimspace(var.cloudflare_api_token) != ""
    error_message = "cloudflare_api_token must be a non-empty string."
  }
}
