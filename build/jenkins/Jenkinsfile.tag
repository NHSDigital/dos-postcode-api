pipeline {
  /*
    Tags the release image
   */

  agent { label "jenkins-agent-local" }

  parameters {
        string(
            description: 'Enter image tag for release candidate, e.g. 202103111417-e362c87',
            name: 'IMAGE_TAG',
            defaultValue: ''
        )
    string(
            description: 'Enter release tag, e.g. release-20210401',
            name: 'RELEASE_TAG',
            defaultValue: ''
        )
  }

  options {
    buildDiscarder(logRotator(numToKeepStr: '5'))
    disableConcurrentBuilds()
  }

  stages {
    stage('Prepare for jenkins-agent-local run') {
      steps {
        script {
          sh "make jenkins-agent-local-prepare"
        }
      }
    }
    stage('Check IMAGE_TAG parameter') {
      steps {
        script {
          def pattern = /^[0-9]{12}-[a-f0-9]{7}$/

          if (!params.IMAGE_TAG.matches(pattern)) {
            error "Provided IMAGE_TAG '${params.IMAGE_TAG}' does not match the expected pattern. Aborting build."
          }
        }
      }
    }
    stage("Show Variables") {
      steps {
        script {
          sh 'make devops-print-variables'
        }
      }
    }
    stage("Create Release Image") {
      steps {
        script {
          sh "make tag-release DEV_TAG=${IMAGE_TAG} NEW_TAG=${RELEASE_TAG}"
        }
      }
    }
  }
}
