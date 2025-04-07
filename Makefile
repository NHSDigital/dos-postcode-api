PROJECT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
include $(abspath $(PROJECT_DIR)/build/automation/init.mk)
include $(abspath $(PROJECT_DIR)/test/jmeter/jMeter.mk)

# ==============================================================================
# Development workflow targets

prepare: ## Prepare environment
	make \
		git-config \
		docker-config \
		git-secrets-scan-repo-files \
		pipeline-prepare

pipeline-prepare:
	sh $(PROJECT_DIR)scripts/assume_role.sh $(JENKINS_ENV) $(JENKINS_SERVICE_TEAM)

jenkins-agent-local-prepare:
	# the jenkins-agent-local build agents don't have the docker daemon immediately available, let us wait for it
	timeout 60 bash -c 'while ! docker info &>/dev/null; do sleep 1; done' || exit 1

compile:
	make docker-run-mvn \
		DIR="application" \
		CMD="compile"

fetch-project-variables:
	eval "$$(make aws-assume-role-export-variables)"
	export TEXAS_WAF_ACL_ID=$$(make -s aws-waf-get WAF_NAME=$(WAF_NAME))

build: project-config
	cp \
		$(PROJECT_DIR)/build/automation/etc/certificate/* \
		$(PROJECT_DIR)/application/src/main/resources/certificate
	if [ $(PROFILE) == 'local' ]
	then
		make docker-run-mvn \
		DIR="application" \
		CMD="-Dmaven.test.skip=true clean install"
	else
	make docker-run-mvn \
		DIR="application" \
		CMD="clean verify install \
		-Dsonar.verbose=true \
		-Dsonar.host.url='https://sonarcloud.io' \
		-Dsonar.organization='nhsdigital' \
		-Dsonar.projectKey='uec-dos-sf-api-pca' \
		-Dsonar.projectName='DoS Postcode API' \
		-Dsonar.token='$$(make secret-fetch NAME=service-finder-sonar-pass | jq .SONAR_HOST_TOKEN | tr -d '"' || exit 1)' \
		-Dsonar.sourceEncoding='UTF-8' \
		-Dsonar.coverage.jacoco.xmlReportPaths=target/site/jacoco \
		-Dsonar.exclusions='src/main/java/**/config/*.*,src/main/java/**/model/*.*,src/main/java/**/exception/*.*,src/main/java/**/constants/*.*,src/main/java/**/interceptor/*.*,src/test/**/*.*,src/main/java/**/filter/*.*,src/main/java/**/PostcodeMappingApplication.*' \
		sonar:sonar"
	fi

	mv \
		$(PROJECT_DIR)/application/target/dos-postcode-api-*.jar \
		$(PROJECT_DIR)/build/docker/dos-postcode-api/assets/application/dos-postcode-api.jar
	make docker-build NAME=dos-postcode-api

scan:
	if [ ! -d $(PROJECT_DIR)/reports ]; then
		mkdir $(PROJECT_DIR)/reports
	fi

	make docker-run-mvn \
		DIR="application" \
		CMD="dependency-check:check"

	mv \
		$(PROJECT_DIR)/application/target/dependency-check-report.html \
		$(PROJECT_DIR)/reports/postcode-dependency-report.html


start: project-start	# Start project

stop: project-stop # Stop project

restart: stop start # Restart project

debug:
	make project-start 2> /dev/null ||:
	docker rm --force dos-postcode-api 2> /dev/null ||:
	make docker-run-mvn-lib-mount \
		NAME=dos-postcode-api \
		DIR=application \
		CMD="spring-boot:run \
			-Dspring-boot.run.jvmArguments=' \
				-Xdebug \
				-Xrunjdwp:transport=dt_socket,server=y,suspend=n,address=*:9999 \
			' \
		" \
		ARGS=" \
		--env SPRING_PROFILES_ACTIVE='local, mock-auth' \
		--env DYNAMODB_POSTCODE_LOC_MAP_TABLE='$(DYNAMODB_POSTCODE_LOC_MAP_TABLE)' \
		--env CERTIFICATE_DOMAIN='$(CERTIFICATE_DOMAIN)' \
		--env POSTCODE_LOCATION_DYNAMO_URL='$(POSTCODE_LOCATION_DYNAMO_URL)' \
		--env SERVER_PORT='$(SERVER_PORT)' \
		--env VERSION='$(VERSION)' \
		--env AWS_ACCESS_KEY_ID='dummy' \
		--env AWS_SECRET_ACCESS_KEY='dummy' \
		\
		--publish 9999:9999 \
		--publish 443:443 \
		"
		make project-start

log: project-log # Show project logs

unit-test:
	make docker-run-mvn \
		DIR="application" \
		CMD="test"

coverage-report:
	make unit-test
	make docker-run-mvn \
		DIR="application" \
		CMD="jacoco:report"

test: # Test project
	make start
	make stop

push: # Push project artefacts to the registry
	make docker-push NAME=dos-postcode-api

tag-release: # Create the release tag - mandatory DEV_TAG RELEASE_TAG
	make docker-login
	docker pull $(DOCKER_REGISTRY)/api:$(DEV_TAG)
	docker tag $(DOCKER_REGISTRY)/api:$(DEV_TAG) $(DOCKER_REGISTRY)/api:$(RELEASE_TAG)
	docker tag $(DOCKER_REGISTRY)/api:$(DEV_TAG) $(DOCKER_REGISTRY_LIVE)/api:$(RELEASE_TAG)
	docker push $(DOCKER_REGISTRY)/api:$(RELEASE_TAG)
	docker push $(DOCKER_REGISTRY_LIVE)/api:$(RELEASE_TAG)

deploy: # Deploy artefacts - mandatory: PROFILE=[name]
	eval "$$(make aws-assume-role-export-variables)"
	export AWS_WAF_ACL_ARN=$$(make -s aws-waf-get WAF_NAME=$(WAF_NAME))
	echo $$AWS_WAF_ACL_ARN
	make project-deploy STACK=application PROFILE=$(PROFILE)

plan-etl: # Plan environment - mandatory: PROFILE=[name]
	make terraform-plan STACK=$(INFRASTRUCTURE_STACKS) PROFILE=$(PROFILE)
	sleep $(SLEEP_AFTER_PLAN)

provision-etl: # Provision environment - mandatory: PROFILE=[name]
	make terraform-apply-auto-approve STACK=$(INFRASTRUCTURE_STACKS) PROFILE=$(PROFILE)

plan:
	make terraform-plan STACK=$(INFRASTRUCTURE_STACKS) PROFILE=$(PROFILE)
	sleep $(SLEEP_AFTER_PLAN)

provision: # Provision environment - mandatory: PROFILE=[name]
	make terraform-apply-auto-approve STACK=$(INFRASTRUCTURE_STACKS) PROFILE=$(PROFILE)

provision-sns-plan:
	make terraform-plan STACK=$(SNS_INFRASTRUCTURE_STACKS) PROFILE=$(PROFILE)

provision-sns: # Provision environment - mandatory: PROFILE=[name]
	make terraform-apply-auto-approve STACK=$(SNS_INFRASTRUCTURE_STACKS) PROFILE=$(PROFILE)

destroy:
	make delete-namespace PROFILE=$(PROFILE)
	make destroy-infrastructure PROFILE=$(PROFILE)

delete-namespace: # Delete namespace - mandatory: PROFILE=[name]
	make k8s-undeploy PROFILE=$(PROFILE)

destroy-infrastructure:  # Destroy environment - mandatory: PROFILE=[name]
	make terraform-destroy-auto-approve STACK=$(SNS_INFRASTRUCTURE_STACKS) PROFILE=$(PROFILE)
	make terraform-destroy-auto-approve STACK=$(INFRASTRUCTURE_STACKS) PROFILE=$(PROFILE)

clean: # Clean up project
	make stop
	docker network rm $(DOCKER_NETWORK) 2> /dev/null ||:

run-smoke-test:
	eval "$$(make aws-assume-role-export-variables)"
	make docker-login
	make run-smoke COGNITO_USER_PASS=$$(make aws-secret-get NAME=$(PROJECT_GROUP_SHORT)-sfsa-${PROFILE}-cognito-passwords | jq .POSTCODE_PASSWORD | tr -d '"')

run-contract-test:
	make run-contract

monitor-deployment:
	make k8s-check-deployment-of-replica-sets

# ==============================================================================
# Supporting targets
trust-certificate: ssl-trust-certificate-project ## Trust the SSL development certificate

docker-run-mvn-lib-mount: ### Build Docker image mounting library volume - mandatory: DIR, CMD
	make docker-run-mvn LIB_VOLUME_MOUNT=true \
		DIR="$(DIR)" \
		CMD="$(CMD)"

k8s-get-replica-sets-not-yet-updated:
	echo -e
	kubectl get deployments -n $(K8S_APP_NAMESPACE) \
	-o=jsonpath='{range .items[?(@.spec.replicas!=@.status.updatedReplicas)]}{.metadata.name}{"("}{.status.updatedReplicas}{"/"}{.spec.replicas}{")"}{" "}{end}'

k8s-get-pod-status:
	echo -e
	kubectl get pods -n $(K8S_APP_NAMESPACE)

# ==============================================================================
# Pipeline targets

file-generator-etl:
	eval "$$(make aws-assume-role-export-variables)"
	process=$$($(AWSCLI) lambda invoke --function-name $(PROJECT_ID)-$(PROFILE)-ccg-file-generator out.json --log-type Tail)
	cat out.json
	rm -r out.json

postcode-extract-etl:
	eval "$$(make aws-assume-role-export-variables)"
	http_result=$$(aws lambda invoke --function-name $(PROJECT_ID)-$(PROFILE)-postcode-extract out.json --log-type Tail | jq .StatusCode)
	if [[ ! $$http_result -eq 200 ]]; then
		cat out.json
		rm -r out.json
		exit 1
	fi
	echo $$http_result
	cat out.json
	rm -r out.json

postcode-insert-etl:
	eval "$$(make aws-assume-role-export-variables)"
	process=$$($(AWSCLI) lambda invoke --function-name $(PROJECT_ID)-$(PROFILE)-postcode-insert out.json --log-type Tail)
	cat out.json
	rm -r out.json

postcode-email-update-etl:
	eval "$$(make aws-assume-role-export-variables)"
	process=$$($(AWSCLI) lambda invoke --invocation-type Event --function-name $(PROJECT_ID)-$(PROFILE)-email-update  out.json --log-type Tail)
	cat out.json
	rm -r out.json

step-function-etl: #Executes lambda update functions with step machine
	eval "$$(make aws-assume-role-export-variables)"
	process=$$($(AWSCLI) stepfunctions start-execution --state-machine-arn arn:aws:states:$(AWS_DEFAULT_REGION):$(AWS_ACCOUNT_ID):stateMachine:$(SERVICE_PREFIX)-region-email-update-state-machine)
	echo $$process

create-lambda-deploy-dir:
	if [ ! -d $(PROJECT_DIR)infrastructure/stacks/postcode_etl/functions/uec-sf-postcode-extract/deploy ]
	then
		mkdir $(PROJECT_DIR)infrastructure/stacks/postcode_etl/functions/uec-sf-postcode-extract/deploy
		touch $(PROJECT_DIR)infrastructure/stacks/postcode_etl/functions/uec-sf-postcode-extract/deploy/test.txt
	fi

	if [ ! -d $(PROJECT_DIR)infrastructure/stacks/postcode_etl/functions/uec-sf-postcode-insert/deploy ]
	then
		mkdir $(PROJECT_DIR)infrastructure/stacks/postcode_etl/functions/uec-sf-postcode-insert/deploy
		touch $(PROJECT_DIR)infrastructure/stacks/postcode_etl/functions/uec-sf-postcode-insert/deploy/test.txt
	fi

build-artefact:
	echo TODO: $(@)

publish-artefact:
	echo TODO: $(@)

backup-data:
	echo TODO: $(@)

provision-infractructure:
	echo TODO: $(@)

deploy-artefact:
	echo TODO: $(@)

apply-data-changes:
	echo TODO: $(@)S

# --------------------------------------

run-static-analisys:
	echo TODO: $(@)

run-unit-test:
	echo TODO: $(@)

monitor-r53-connection:
	attempt_counter=1
	max_attempts=20
	sleep 30
	http_status_code=0
	until [[ $$http_status_code -eq 200 ]]; do
		sleep 20
		if [[ $$attempt_counter -eq $$max_attempts ]]; then
			echo "Maximum attempts reached unable to connect to deployed instance"
			exit 0
		fi
		echo "Pinging deployed instance count - " $$attempt_counter
		http_status_code=$$(curl -s -k -o /dev/null -w "%{http_code}" --max-time 30 $(POSTCODE_ENDPOINT)/api/home || true)
		attempt_counter=$$(($$attempt_counter+1))
		echo Status code is: $$http_status_code
	done

k8s-check-deployment-of-replica-sets:
	eval "$$(make aws-assume-role-export-variables)"
	make k8s-kubeconfig-get
	eval "$$(make k8s-kubeconfig-export-variables)"
	sleep 10
	elaspedtime=10
	until [ $$elaspedtime -gt $(CHECK_DEPLOYMENT_TIME_LIMIT) ]; do
		replicasNotYetUpdated=$$(make -s k8s-get-replica-sets-not-yet-updated)
		if [ -z "$$replicasNotYetUpdated" ]
		then
			echo "Success - all replica sets in the deployment have been updated."
			exit 0
		else
			echo "Waiting for all replicas to be updated: " $$replicasNotYetUpdated

			echo "----------------------"
			echo "Pod status: "
			make k8s-get-pod-status
			podStatus=$$(make -s k8s-get-pod-status)
			echo "-------"

			#Check failure conditions
			if [[ $$podStatus = *"ErrImagePull"*
					|| $$podStatus = *"ImagePullBackOff"* ]]; then
				echo "Failure: Error pulling Image"
				exit 1
			elif [[ $$podStatus = *"Error"*
								|| $$podStatus = *"error"*
								|| $$podStatus = *"ERROR"* ]]; then
				echo "Failure: Error with deployment"
				exit 1
			fi

		fi
		sleep 10
		((elaspedtime=elaspedtime+$(CHECK_DEPLOYMENT_POLL_INTERVAL)))
		echo "Elapsed time: " $$elaspedtime
	done

	echo "Conditional Success: The deployment has not completed within the timescales, but carrying on anyway"
	exit 0

local-dynamodb-scripts:
	cd $(PROJECT_DIR)/data/dynamo/test
	chmod +x *.sh
	./00-postcode-location-mapping-table.sh > /dev/null
	./01-postcode-location-mapping-table.sh

run-contract:
	make stop
	make start PROFILE=local
	sleep 20
	make docker-compose-log DO_NOT_FOLLOW=true
	echo "list docker processes"
	docker ps -a
	make docker-run-postman \
		DIR="$(APPLICATION_TEST_DIR)/contract" \
		CMD=" \
			run collections/PostcodeAPIContractTests.postman_collection.json -e \
			environment/postcode_contract.postman_environment.json --verbose --insecure \
			-r htmlextra,cli --reporter-htmlextra-export ./reports/PostcodeAPIContractTests.html
		"
	make project-stop

# REMOVE PASSWORD LOGS BEFORE GO LIVE
run-smoke:
	make restart
	sleep 20
	sed -i -e 's|HOST_TO_REPLACE|$(POSTCODE_ENDPOINT)|g' $(APPLICATION_TEST_DIR)/contract/environment/postcode_smoke.postman_environment.json

	echo "Profile: $(PROFILE). Executing real token test"
	TOKEN=$$(curl -X POST -H "Content-Type: application/json" $(AUTHENTICATION_ENDPOINT) -d "{\"emailAddress\":\"$(POSTCODE_USER)\", \"password\":\"$(COGNITO_USER_PASS)\"}" | jq .accessToken | tr -d '"')
	echo $$TOKEN
	sed -i -e "s/MOCK_POSTCODE_API_ACCESS_TOKEN/$$TOKEN/g" $(APPLICATION_TEST_DIR)/contract/environment/postcode_smoke.postman_environment.json

	make docker-run-postman \
		DIR="$(APPLICATION_TEST_DIR)/contract" \
		CMD=" \
			run collections/PostcodeAPISmokeTests.postman_collection.json -e environment/postcode_smoke.postman_environment.json --verbose \
			-r htmlextra,cli --reporter-htmlextra-export ./reports/PostcodeAPISmokeTests.html
		"

	make project-stop

run-integration-test:
	echo TODO: $(@)

run-functional-test:
	[ $$(make project-branch-func-test) != true ] && exit 0
	echo TODO: $(@)

run-performance-test:
	[ $$(make project-branch-perf-test) != true ] && exit 0
	echo TODO: $(@)

run-security-test:
	[ $$(make project-branch-sec-test) != true ] && exit 0
	echo TODO: $(@)

# --------------------------------------
start-rds-instance:
	eval "$$(make aws-assume-role-export-variables)"
	make aws-rds-start-instance DB_INSTANCE=$(RDS_DB_INSTANCE)

stop-rds-instance:
	eval "$$(make aws-assume-role-export-variables)"
	make aws-rds-stop-instance DB_INSTANCE=$(RDS_DB_INSTANCE)
# ----------------------------------------
remove-unused-environments:
	echo TODO: $(@)

remove-old-artefacts:
	echo TODO: $(@)

remove-old-backups:
	echo TODO: $(@)

# --------------------------------------

pipeline-finalise: ## Finalise pipeline execution - mandatory: PIPELINE_NAME,BUILD_STATUS
	# Check if BUILD_STATUS is SUCCESS or FAILURE
	make pipeline-send-notification

pipeline-send-notification: ## Send Slack notification with the pipeline status - mandatory: PIPELINE_NAME,BUILD_STATUS
	eval "$$(make aws-assume-role-export-variables)"
	eval "$$(make secret-fetch-and-export-variables NAME=$(PROJECT_GROUP_SHORT)-$(PROJECT_NAME_SHORT)-$(PROFILE)/deployment)"
	make slack-it

# --------------------------------------

pipeline-check-resources: ## Check all the pipeline deployment supporting resources - optional: PROFILE=[name]
	profiles="$$(make project-list-profiles)"
	# for each profile
	#export PROFILE=$$profile
	# TODO:
	# table: $(PROJECT_GROUP_SHORT)-$(PROJECT_NAME_SHORT)-deployment
	# secret: $(PROJECT_GROUP_SHORT)-$(PROJECT_NAME_SHORT)-$(PROFILE)/deployment
	# bucket: $(PROJECT_GROUP_SHORT)-$(PROJECT_NAME_SHORT)-$(PROFILE)-deployment
	# certificate: SSL_DOMAINS_PROD
	# repos: DOCKER_REPOSITORIES

pipeline-create-resources: ## Create all the pipeline deployment supporting resources - optional: PROFILE=[name]
	profiles="$$(make project-list-profiles)"
	# for each profile
	#export PROFILE=$$profile
	# TODO:
	# Per AWS accoount, i.e. `nonprod` and `prod`
	eval "$$(make aws-assume-role-export-variables)"
	#make aws-dynamodb-create NAME=$(PROJECT_GROUP_SHORT)-$(PROJECT_NAME_SHORT)-deployment ATTRIBUTE_DEFINITIONS= KEY_SCHEMA=
	#make secret-create NAME=$(PROJECT_GROUP_SHORT)-$(PROJECT_NAME_SHORT)-$(PROFILE)/deployment VARS=DB_PASSWORD,SMTP_PASSWORD,SLACK_WEBHOOK_URL
	#make aws-s3-create NAME=$(PROJECT_GROUP_SHORT)-$(PROJECT_NAME_SHORT)-$(PROFILE)-deployment
	#make ssl-request-certificate-prod SSL_DOMAINS_PROD
	# Centralised, i.e. `mgmt`
	eval "$$(make aws-assume-role-export-variables AWS_ACCOUNT_ID=$(AWS_ACCOUNT_ID_MGMT))"
	#make docker-create-repository NAME=NAME_TEMPLATE_TO_REPLACE
	#make aws-codeartifact-setup REPOSITORY_NAME=$(PROJECT_GROUP_SHORT)

pipeline-secret-scan:
	make -s git-secrets-load
	result=$$(make -s git-secrets-scan-repo-files)
	if [ -z result ]; then
		echo "Secrets found: $$result"
		exit 1
	fi

# ==============================================================================

derive-build-tag:
	dir=$$(make _docker-get-dir NAME=dos-postcode-api)
	echo $$(cat $$dir/VERSION) | \
				sed "s/YYYY/$$(date --date=$(BUILD_DATE) -u +"%Y")/g" | \
				sed "s/mm/$$(date --date=$(BUILD_DATE) -u +"%m")/g" | \
				sed "s/dd/$$(date --date=$(BUILD_DATE) -u +"%d")/g" | \
				sed "s/HH/$$(date --date=$(BUILD_DATE) -u +"%H")/g" | \
				sed "s/MM/$$(date --date=$(BUILD_DATE) -u +"%M")/g" | \
				sed "s/ss/$$(date --date=$(BUILD_DATE) -u +"%S")/g" | \
				sed "s/SS/$$(date --date=$(BUILD_DATE) -u +"%S")/g" | \
				sed "s/hash/$$(git rev-parse --short HEAD)/g"

# ==============================================================================

pipeline-on-success:
	echo TODO: $(@)

pipeline-on-failure:
	echo TODO: $(@)

.SILENT: \
	derive-build-tag \
	pipeline-secret-scan
