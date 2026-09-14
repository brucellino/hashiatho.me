task "db" {
  driver = "docker"
  # Get a vault token for this job so that we can look up secrets.
  vault {}

  service {
    # Register the db service in Consul so that others can look it up
    # Port db is declared in the group network above
    port = "db"
  }
  resources {
    cpu = 1
    memory = 1024
  }
  config {
    image = "postgres:18-alpine"
    # expose the mapped db port to other services
    ports = ["db"]
    volumes = [
      "local/init-user-db.sh:/docker-entrypoint-initdb.d/init-user-db.sh"
    ]
  }
  template {
    # We can provision custom user scripts using the initdb.d pattern
    # Described by the packagers
    data =<<EOT
#!/usr/bin/env bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
GRANT ALL PRIVILEGES ON DATABASE indico TO postgres;
CREATE EXTENSION unaccent;
CREATE EXTENSION pg_trgm;
EOSQL
    EOT
    destination = "local/init-user-db.sh"

  }
  template {
    # Lookup the credentials in Vault and inject them into the environment
    data = <<EOT
{% raw %}
{{ with secret "hashiatho.m2-v2/payloads/indico" }}
POSTGRES_PASSWORD="{{ .Data.data.db_password }}"
POSTGRES_USER="{{ .Data.data.db_username }}"
POSTGRES_DB="indico"
{{ end }}
{% endraw %}
    EOT
    destination = "secrets/db.env"
    env = true
  }
}
