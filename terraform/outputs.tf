output "nginx_url" {
  description = "URL to check on the Docker host."
  value       = "http://localhost:8080"
}

output "network_name" {
  description = "Dedicated bridge network of the Terraform-managed Nginx."
  value       = docker_network.nginx.name
}

output "volume_name" {
  description = "Named volume attached to the Terraform-managed Nginx."
  value       = docker_volume.nginx_html.name
}
