pipeline {
  /*
    Description: Deployment pipeline for the Demo environment
   */

  agent {
    label 'jenkins-agent-local'
  }

  options {
    buildDiscarder(logRotator(daysToKeepStr: '7', numToKeepStr: '13'))
    disableConcurrentBuilds()
    parallelsAlwaysFailFast()
    timeout(time: 30, unit: 'MINUTES')
  }

  environment {
    PROFILE = 'dmo'
  }

  parameters {
    string(
      description: 'Enter image tag to deploy, e.g. 202103111417-e362c87',
      name: 'IMAGE_TAG',
      defaultValue: ''
    )
  }
  stages {
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
    stage('Prepare for jenkins-agent-local run') {
      steps {
        script {
          sh "make jenkins-agent-local-prepare"
        }
      }
    }
    stage('Pipeline Prepare') {
      steps {
        script {
          sh 'make pipeline-prepare'
        }
      }
    }
    stage('Show Variables') {
      steps {
        script {
          sh 'make devops-print-variables'
        }
      }
    }
    stage('Check Py Lib Folder') {
      steps {
        script {
          sh 'make create-lambda-deploy-dir'
        }
      }
    }
    stage('Import Infrastructure') {
      steps {
        script {
          sh "make terraform-import-stack PROFILE=${env.PROFILE}"
        }
      }
    }
    stage('Plan Infrastructure') {
      steps {
        script {
          sh "make plan PROFILE=${env.PROFILE}"
        }
      }
    }
    stage('Provision Infrastructure') {
      steps {
        script {
          sh "make provision PROFILE=${env.PROFILE}"
        }
      }
    }
    stage('Deploy API') {
      steps {
        script {
          sh "make deploy PROFILE=${env.PROFILE} IMAGE_TAG=${IMAGE_TAG}"
        }
      }
    }
    stage('Monitor Deployment') {
      steps {
        script {
          sh 'make k8s-check-deployment-of-replica-sets'
        }
      }
    }
    stage('Monitor Route53 Connection') {
      steps {
        script {
          sh 'make monitor-r53-connection'
        }
      }
    }
    stage('Perform Extract Lambda function') {
      steps {
        script {
          sh "make postcode-extract-etl PROFILE=${env.PROFILE}"
        }
      }
    }
    stage('Perform Insert Lambda function') {
      steps {
        script {
          sh "make postcode-insert-etl PROFILE=${env.PROFILE}"
        }
      }
    }
    stage('Smoke Tests') {
      steps {
        script {
          sh 'make run-smoke-test'
        }
      }
    }
  }
  post {
    failure {
      script {
        sh 'make terraform-remove-state-lock'
      }
    }
    always {
      script {
        sh 'make clean'
      }
    }
  }
}
