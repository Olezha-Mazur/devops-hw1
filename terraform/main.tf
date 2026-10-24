resource "docker_network" "nginx" {
  name   = "terraform-nginx-net"
  driver = "bridge"
}

resource "docker_volume" "nginx_html" {
  name = "terraform-nginx-html"
}

resource "docker_image" "nginx" {
  name         = "nginx:1.27-alpine"
  keep_locally = true
}

resource "docker_container" "nginx" {
  name    = "terraform-nginx"
  image   = docker_image.nginx.image_id
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.nginx.name
  }

  mounts {
    type   = "volume"
    source = docker_volume.nginx_html.name
    target = "/usr/share/nginx/html"
  }

  ports {
    internal = 80
    external = 8080
    ip       = "0.0.0.0"
  }
}
