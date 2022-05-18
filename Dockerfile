ARG DOCKER_VERSION=20.10
############################################################
# builder                                                  #
# -> golang image used solely for building the k3d binary  #
# -> built executable can then be copied into other stages #
############################################################
FROM golang:1.18 as builder
ARG GIT_TAG_OVERRIDE
WORKDIR /app
COPY . .
RUN make build -e GIT_TAG_OVERRIDE=${GIT_TAG_OVERRIDE} && bin/k3d version

#######################################################
# dind                                                #
# -> k3d + some tools in a docker-in-docker container #
# -> used e.g. in our CI pipelines for testing        #
#######################################################
FROM ubuntu:22.04 as dind
ARG OS
ARG ARCH

ENV OS=${OS}
ENV ARCH=${ARCH}

# Helper script to install some tooling
COPY scripts/install-tools.sh /scripts/install-tools.sh

# install some basic packages needed for testing, etc.
RUN apt-get update && \
    apt-get install bash curl sudo jq git make netcat-openbsd

# Install docker
RUN apt-get update && \
    apt-get install ca-certificates curl gnupg lsb-release
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
RUN echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

RUN apt-get update && apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin

# install kubectl to interact with the k3d cluster
# install yq (yaml processor) from source, as the busybox yq had some issues
RUN /scripts/install-tools.sh kubectl yq

COPY --from=builder /app/bin/k3d /bin/k3d

#########################################
# binary-only                           #
# -> only the k3d binary.. nothing else #
#########################################
FROM scratch as binary-only
COPY --from=builder /app/bin/k3d /bin/k3d
ENTRYPOINT ["/bin/k3d"]
