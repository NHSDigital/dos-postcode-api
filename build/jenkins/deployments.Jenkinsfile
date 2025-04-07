def envProfile = ''

pipeline {
    /*
        Description: Unified pipeline to deploy to various environments
    */
    agent any

    options {
        buildDiscarder(logRotator(daysToKeepStr: '7', numToKeepStr: '13'))
        disableConcurrentBuilds()
        parallelsAlwaysFailFast()
        timeout(time: 30, unit: 'MINUTES')
    }

    parameters {
        string(
            description: 'Enter image tag to deploy, e.g. 202103111417-e362c87',
            name: 'IMAGE_TAG',
            defaultValue: ''
        )
        choice(
            name: 'PROFILE',
            choices: ['NonProd', 'Demo', 'Production'],
            description: 'Select environment profile'
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
                    sh 'make jenkins-agent-local-prepare'
                }
            }
        }
        stage('Select Environment') {
            steps {
                script {
                    def options = [
                        'NonProd': 'dev',
                        'Demo': 'dmo',
                        'Production': 'pd'
                    ]
                    envProfile = options[params.PROFILE]
                    echo "Selected environment profile: ${params.PROFILE} - ${envProfile}"
                }
            }
        }
        stage('Pipeline Prepare') {
            steps {
                script {
                    env.PROFILE = envProfile
                    sh 'make pipeline-prepare'
                }
            }
        }
        stage('Show Variables') {
            steps {
                script {
                    env.PROFILE = envProfile
                    sh 'make devops-print-variables'
                }
            }
        }
        stage('Check Py Lib Folder') {
            steps {
                script {
                    env.PROFILE = envProfile
                    sh 'make create-lambda-deploy-dir'
                }
            }
        }
        stage('Plan Infrastructure') {
            steps {
                script {
                    env.PROFILE = envProfile
                    sh "make plan PROFILE=${envProfile}"
                }
            }
        }
        stage('Infrastructure Approval') {
            steps {
                script {
                    env.PROFILE = envProfile
                    input 'Approve to continue with provisioning'
                }
            }
        }
        stage('Provision Infrastructure') {
            steps {
                script {
                    env.PROFILE = envProfile
                    sh "make provision PROFILE=${envProfile}"
                }
            }
        }
        stage('Deploy API') {
            steps {
                script {
                    env.PROFILE = envProfile
                    sh "make deploy PROFILE=${envProfile} IMAGE_TAG=${params.IMAGE_TAG}"
                }
            }
        }
        stage('Monitor Deployment') {
            steps {
                script {
                    env.PROFILE = envProfile
                    sh 'make k8s-check-deployment-of-replica-sets'
                }
            }
        }
        stage('Monitor Route53 Connection') {
            steps {
                script {
                    env.PROFILE = envProfile
                    sh 'make monitor-r53-connection'
                }
            }
        }
        stage('Perform Extract Lambda function') {
            steps {
                script {
                    env.PROFILE = envProfile
                    sh "make postcode-extract-etl PROFILE=${envProfile}"
                }
            }
        }
        stage('Perform Insert Lambda function') {
            when {
                expression {
                    params.PROFILE != 'dev'
                }
            }
            steps {
                script {
                    env.PROFILE = envProfile
                    sh "make postcode-insert-etl PROFILE=${envProfile}"
                }
            }
        }
        stage('Smoke Tests') {
            steps {
                script {
                    env.PROFILE = envProfile
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
                env.PROFILE = envProfile
                sh 'make clean'
            }
        }
    }
}
