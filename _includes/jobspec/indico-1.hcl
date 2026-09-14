// Indico job definition modelled as 3-tier workload
// Each tier gets a group
job "indico" {
  group "frontend" {
    count = 1
    // serves user requests, exposed to internet. Low resources
    task "nginx" {
       driver = "docker"
       config {
         image = "nginx:stable-alpine"
       }
    }
    task "redis" {
      driver = "docker"
      config {
        image = "redis:8-alpine"
      }
    }
  }

  group "application" {
    count = 1
    // Runs the actual application. High resources, disposable
    task "indico" {
      driver = "docker"
      config {
        image = "ghcr.io/hashi-at-home/indico" # We need to build this
      }
    }
  }

  group "backend" {
    // Handles events and persists data, high reliability and elasticity
    task "celery" {
      count = 1 // let's scale this guy eventually
      driver = "docker"
      # Reuse the same indico image as before, since it has celery
      # configured on it
      config {
        image = "ghcr.io/hashi-at-home/indico"
      }
    }

    task "db" {
      count = 1
      # This one is debatable - deploying the database together with the app
      # May be a recipe for disaster if things die.
      # Better to have an external database in prod
      driver = "docker"
      config {
        image = "postgres:18-alpine"
      }
    }
  }
}
