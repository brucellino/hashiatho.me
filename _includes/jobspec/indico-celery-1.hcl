// Handles events and persists data, high reliability and elasticity
task "celery" {
  constraint {
    attribute = "${attr.cpu.arch}"
    value = "amd64"
  }
  resources {
    cpu = 2
    memory = 4096
  }
  driver = "docker"
  # Reuse the same indico image as before, since it has celery
  # configured on it
  config {
    image = "ghcr.io/hashi-at-home/indico"
    entrypoint = ["/local/start_celery.sh"]
    auth {
      username = "${secret.github.gh_username}"
      password = "${secret.github.ghcr_token}"
    }
  }
  template {
    data = <<EOT
#!/bin/bash
# yes this should probably be in an init 1 process
mise exec -- indico celery worker -B
    EOT
    destination = "/local/start_celery.sh"
    perms = "0777"

  }
  template {
    # Template the celery-specific configuration for indico
    data = <<EOT
# Celery settings
{% raw %}
# Lookup the secret and store it in a variable $secretData
{{ with secret "hashiatho.me-v2/payloads/indico" }}
{{ $secretData := Data.data }}
# Lookup the db service.
{{ range service "indico-backend-db" }}
SQLALCHEMY_DATABASE_URI = 'postgresql://${secretData.posgtgres_user}:${secretData.postgres_pass}@{{ .Address }}:{{ .Port }}/indico'
{{ end }} {{/* end service lookup */}}

SECRET_KEY = '${secretData.indico_secret}'
BASE_URL = 'http://0.0.0.0'

{{ range service "indico-frontend-redis" }}
CELERY_BROKER = 'redis://{{ .Address }}:{{ .Port }}/0'
REDIS_CACHE_URL = 'redis://{{ .Address }}:{{ .Port }}/1'
{{ end }} {{/* end service lookup */}}

{{ end }} {{/* end secret lookup context */}}
{% endraw %}
  EOT
    destination = "local/indico.conf"
    change_mode = "restart"
  }
  env {
    # Tell Indico where to find it's config
    INDICO_CONFIG = "/local/indico.conf"
  }
}
