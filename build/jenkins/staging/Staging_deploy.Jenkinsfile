pipeline {
  /*
    Description: Deployment pipeline
   */
  agent { label 'jenkins-agent-local' }

  options {
    buildDiscarder(logRotator(daysToKeepStr: '7', numToKeepStr: '13'))
    disableConcurrentBuilds()
    parallelsAlwaysFailFast()
    timeout(time: 120, unit: 'MINUTES')
  }

  environment {
    PROFILE = 'stg'
  }
  parameters {
        string(
            description: 'Enter image tag to deploy, e.g. 202103111417-e362c87',
            name: 'IMAGE_TAG',
            defaultValue: ''
        )
  }
  stages {
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
    stage('Plan Infrastructure') {
      steps {
        script {
          sh "make provision-plan PROFILE=${env.PROFILE}"
        }
      }
    }
    stage('Plan ETL Infrastructure') {
      steps {
        script {
          sh "make plan-etl PROFILE=${env.PROFILE}"
        }
      }
    }

    stage('Plan SNS Infrastructure') {
      steps {
        script {
          sh "make provision-sns-plan PROFILE=${env.PROFILE}"
        }
      }
    }
    stage('Destroy env API') {
      steps {
        script {
          sh "make destroy PROFILE=${env.PROFILE}"
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
    always { script {
        sh 'make clean'
    }
  }
}
}
