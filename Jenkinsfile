// Module Tag Trigger — runs when a tag matching <module>/v<semver> is pushed
// to https://github.com/beravelli/autotfrefresh
//
// 1. Parses the tag to extract MODULE_NAME and MODULE_VERSION automatically
// 2. Validates the module source under modules/<MODULE_NAME>/
// 3. Triggers the downstream refresh pipeline

pipeline {
  agent { label 'tofu' }

  options {
    timeout(time: 20, unit: 'MINUTES')
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '30'))
  }

  environment {
    MODULE_REPO_URL = 'https://github.com/beravelli/autotfrefresh.git'
    LIVE_INFRA_JOB  = 'gitops/refresh-pipeline'
  }

  stages {
    stage('Parse tag') {
      steps {
        script {
          // TAG_NAME is set by Jenkins Multibranch when building from a tag
          def tag = env.TAG_NAME ?: sh(
            script: 'git describe --exact-match --tags HEAD 2>/dev/null || echo ""',
            returnStdout: true
          ).trim()

          if (!tag) {
            error "No tag found — this pipeline must be triggered by a git tag."
          }

          // Expected format: <module>/v<semver>  e.g.  vpc/v1.2.3
          def matcher = tag =~ /^([a-z0-9_\-]+)\/v(\d+\.\d+\.\d+.*)$/
          if (!matcher) {
            error "Tag '${tag}' does not match '<module>/v<semver>'. Nothing to do."
          }

          env.MODULE_NAME    = matcher[0][1]
          env.MODULE_VERSION = "v${matcher[0][2]}"
          env.MODULE_TAG     = tag

          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo " Module  : ${env.MODULE_NAME}"
          echo " Version : ${env.MODULE_VERSION}"
          echo " Tag     : ${env.MODULE_TAG}"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        }
      }
    }

    stage('Validate module') {
      steps {
        script {
          def moduleDir = "modules/${env.MODULE_NAME}"
          if (!fileExists(moduleDir)) {
            error "Module directory '${moduleDir}' not found in repo."
          }
          dir(moduleDir) {
            sh '''
              tofu init -backend=false -input=false
              tofu validate
              tofu fmt -check -recursive || echo "WARNING: fmt issues found (non-fatal)"
            '''
          }
        }
      }
    }

    stage('Trigger refresh') {
      steps {
        script {
          echo "Triggering refresh pipeline for ${env.MODULE_NAME}@${env.MODULE_VERSION}..."
          build job: env.LIVE_INFRA_JOB,
            parameters: [
              string(name: 'MODULE_NAME',     value: env.MODULE_NAME),
              string(name: 'MODULE_VERSION',  value: env.MODULE_VERSION),
              string(name: 'MODULE_REPO_URL', value: env.MODULE_REPO_URL),
              string(name: 'TRIGGERED_BY',    value: "tag ${env.MODULE_TAG} by ${env.GIT_AUTHOR_NAME ?: 'unknown'}"),
              booleanParam(name: 'DRY_RUN',   value: true),
            ],
            wait: false,
            propagate: false
        }
      }
    }
  }

  post {
    success {
      echo "✓ Module ${env.MODULE_NAME}@${env.MODULE_VERSION} validated. Refresh pipeline triggered."
    }
    failure {
      echo "✗ Validation failed for tag ${env.MODULE_TAG}. Refresh pipeline was NOT triggered."
    }
  }
}
