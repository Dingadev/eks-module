# ----------------------------------------------------------------------------------------------------------------------
# CONTAINER FOR aws-auth-merger
# ----------------------------------------------------------------------------------------------------------------------

# Build Phase 1: go compiler
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~

FROM golang:1.16
MAINTAINER Gruntwork <info@gruntwork.io>

# Build the aws-auth-merger binary
COPY ./aws-auth-merger /tmp/builddir/aws-auth-merger
WORKDIR /tmp/builddir/aws-auth-merger
RUN CGO_ENABLED=0 go build -o /usr/local/bin/aws-auth-merger .


# Build Phase 2: Install binaries
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FROM scratch
MAINTAINER Gruntwork <info@gruntwork.io>

COPY --from=0 /usr/local/bin/aws-auth-merger /aws-auth-merger/aws-auth-merger
ENV HOME /aws-auth-merger
ENV USER aws-auth-merger:aws-auth-merger
ENV PATH /usr/local/bin:/aws-auth-merger
WORKDIR /workspace
ENTRYPOINT ["/aws-auth-merger/aws-auth-merger"]
