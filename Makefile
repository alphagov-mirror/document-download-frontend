SHELL := /bin/bash

GIT_COMMIT ?= $(shell git rev-parse HEAD)

CF_API ?= api.cloud.service.gov.uk
NOTIFY_CREDENTIALS ?= ~/.notify-credentials

CF_APP = document-download-frontend

.PHONY: help
help:
	@cat $(MAKEFILE_LIST) | grep -E '^[a-zA-Z_-]+:.*?## .*$$' | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: venv
venv: venv/bin/activate ## Create virtualenv if it does not exist

venv/bin/activate:
	test -d venv || virtualenv venv -p python3
	. venv/bin/activate

.PHONY: run
run:
	FLASK_APP=application.py FLASK_ENV=development flask run -p 7001

.PHONY: test
test: venv
	find . -name \*.pyc -delete
	npm install
	npm run build
	./scripts/run_tests.sh
	if [[ ! -z $$COVERALLS_REPO_TOKEN ]]; then coveralls; fi

.PHONY: build
build:
	find . -name \*.pyc -delete
	npm set progress=false
	npm install
	npm rebuild node-sass --force
	npm run build

.PHONY: freeze-requirements
freeze-requirements:
	rm -rf venv-freeze
	virtualenv -p python3 venv-freeze
	$$(pwd)/venv-freeze/bin/pip install -r requirements-app.txt
	echo '# This file is autogenerated. Do not edit it manually.' > requirements.txt
	cat requirements-app.txt >> requirements.txt
	echo '' >> requirements.txt
	$$(pwd)/venv-freeze/bin/pip freeze -r <(sed '/^--/d' requirements-app.txt) | sed -n '/The following requirements were added by pip freeze/,$$p' >> requirements.txt
	rm -rf venv-freeze

.PHONY: test-requirements
test-requirements:
	@diff requirements-app.txt requirements.txt | grep '<' \
	    && { echo "requirements.txt doesn't match requirements-app.txt."; \
	         echo "Run 'make freeze-requirements' to update."; exit 1; } \
|| { echo "requirements.txt is up to date"; exit 0; }

.PHONY: preview
preview:
	$(eval export CF_SPACE=preview)
	$(eval export DNS_NAME=documents.notify.works)
	cf target -s ${CF_SPACE}

.PHONY: staging
staging:
	$(eval export CF_SPACE=staging)
	$(eval export DNS_NAME=documents.staging-notify.works)
	cf target -s ${CF_SPACE}

.PHONY: production
production:
	$(eval export CF_SPACE=production)
	$(eval export DNS_NAME=documents.service.gov.uk)
	cf target -s ${CF_SPACE}

.PHONY: generate-manifest
generate-manifest:
	$(if ${CF_SPACE},,$(error Must specify CF_SPACE))

	$(if $(shell which gpg2), $(eval export GPG=gpg2), $(eval export GPG=gpg))
	$(if ${GPG_PASSPHRASE_TXT}, $(eval export DECRYPT_CMD=echo -n $$$${GPG_PASSPHRASE_TXT} | ${GPG} --quiet --batch --passphrase-fd 0 --pinentry-mode loopback -d), $(eval export DECRYPT_CMD=${GPG} --quiet --batch -d))

	@jinja2 --strict manifest.yml.j2 \
	    -D environment=${CF_SPACE} --format=yaml \
	    <(${DECRYPT_CMD} ${NOTIFY_CREDENTIALS}/credentials/${CF_SPACE}/document-download/paas-environment.gpg) 2>&1

.PHONY: cf-push
cf-push:
	$(if ${CF_SPACE},,$(error Must specify CF_SPACE))
	cf push ${CF_APP} -f <(make -s generate-manifest)

.PHONY: cf-deploy
cf-deploy: ## Deploys the app to Cloud Foundry
	$(if ${CF_SPACE},,$(error Must specify CF_SPACE))
	@cf app --guid ${CF_APP} || exit 1

	# cancel any existing deploys to ensure we can apply manifest (if a deploy is in progress you'll see ScaleDisabledDuringDeployment)
	cf v3-cancel-zdt-push ${CF_APP} || true

	cf v3-apply-manifest ${CF_APP} -f <(make -s generate-manifest)
	cf v3-zdt-push ${CF_APP} --wait-for-deploy-complete  # fails after 5 mins if deploy doesn't work

.PHONY: cf-rollback
cf-rollback: ## Rollbacks the app to the previous release
	cf v3-cancel-zdt-push ${CF_APP}

.PHONY: cf-create-cdn-route
cf-create-cdn-route:
	$(if ${CF_SPACE},,$(error Must specify CF_SPACE))
	$(if ${DNS_NAME},,$(error Must specify DNS_NAME))
	cf create-service cdn-route cdn-route document-download-cdn-route -c '{"domain": "${DNS_NAME}"}'

.PHONY: cf-login
cf-login: ## Log in to Cloud Foundry
	$(if ${CF_USERNAME},,$(error Must specify CF_USERNAME))
	$(if ${CF_PASSWORD},,$(error Must specify CF_PASSWORD))
	$(if ${CF_SPACE},,$(error Must specify CF_SPACE))
	@echo "Logging in to Cloud Foundry on ${CF_API}"
	@cf login -a "${CF_API}" -u ${CF_USERNAME} -p "${CF_PASSWORD}" -o "${CF_ORG}" -s "${CF_SPACE}"

.PHONY: docker-build
docker-build:
	docker build --pull \
		--build-arg HTTP_PROXY="${HTTP_PROXY}" \
		--build-arg HTTPS_PROXY="${HTTP_PROXY}" \
		--build-arg NO_PROXY="${NO_PROXY}" \
		-t govuk/${CF_APP}:${GIT_COMMIT} \
		.

.PHONY: test-with-docker
test-with-docker: docker-build
	docker run --rm \
		-e COVERALLS_REPO_TOKEN=${COVERALLS_REPO_TOKEN} \
		-e CIRCLECI=1 \
		-e CI_BUILD_NUMBER=${BUILD_NUMBER} \
		-e CI_BUILD_URL=${BUILD_URL} \
		-e CI_NAME=${CI_NAME} \
		-e CI_BRANCH=${GIT_BRANCH} \
		-e CI_PULL_REQUEST=${CI_PULL_REQUEST} \
		-e http_proxy="${http_proxy}" \
		-e https_proxy="${https_proxy}" \
		-e NO_PROXY="${NO_PROXY}" \
		govuk/${CF_APP}:${GIT_COMMIT} \
		make test

.PHONY: build-with-docker
build-with-docker: docker-build
	docker run --rm \
		-v "`pwd`:/var/project" \
		-e COVERALLS_REPO_TOKEN=${COVERALLS_REPO_TOKEN} \
		-e CIRCLECI=1 \
		-e CI_BUILD_NUMBER=${BUILD_NUMBER} \
		-e CI_BUILD_URL=${BUILD_URL} \
		-e CI_NAME=${CI_NAME} \
		-e CI_BRANCH=${GIT_BRANCH} \
		-e CI_PULL_REQUEST=${CI_PULL_REQUEST} \
		-e http_proxy="${http_proxy}" \
		-e https_proxy="${https_proxy}" \
		-e NO_PROXY="${NO_PROXY}" \
		govuk/${CF_APP}:${GIT_COMMIT} \
		make build

.PHONY: run-with-docker
run-with-docker: docker-build
		docker run --rm \
		-v "`pwd`:/var/project" \
		-e COVERALLS_REPO_TOKEN=${COVERALLS_REPO_TOKEN} \
		-e CIRCLECI=1 \
		-e CI_BUILD_NUMBER=${BUILD_NUMBER} \
		-e CI_BUILD_URL=${BUILD_URL} \
		-e CI_NAME=${CI_NAME} \
		-e CI_BRANCH=${GIT_BRANCH} \
		-e CI_PULL_REQUEST=${CI_PULL_REQUEST} \
		-e http_proxy="${http_proxy}" \
		-e https_proxy="${https_proxy}" \
		-e NO_PROXY="${NO_PROXY}" \
		govuk/${CF_APP}:${GIT_COMMIT} \
		make run

.PHONY: build-paas-artifact
build-paas-artifact:  ## Build the deploy artifact for PaaS
	rm -rf target
	mkdir -p target
	zip -y -q -r -x@deploy-exclude.lst target/${CF_APP}.zip ./


.PHONY: upload-paas-artifact ## Upload the deploy artifact for PaaS
upload-paas-artifact:
	$(if ${BUILD_NUMBER},,$(error Must specify BUILD_NUMBER))
	$(if ${JENKINS_S3_BUCKET},,$(error Must specify JENKINS_S3_BUCKET))
	aws s3 cp --region eu-west-1 --sse AES256 target/${CF_APP}.zip s3://${JENKINS_S3_BUCKET}/build/${CF_APP}/${BUILD_NUMBER}.zip
