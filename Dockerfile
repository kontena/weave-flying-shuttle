FROM alpine:3.8
LABEL maintainer="Kontena, Inc. <info@kontena.io>"

RUN apk update && apk --update add tzdata ruby ruby-irb ruby-bigdecimal \
    ruby-io-console ruby-json ruby-etc \
    ca-certificates openssl iptables iproute2

ADD Gemfile /app/
ADD Gemfile.lock /app/

RUN apk --update add --virtual build-dependencies ruby-dev build-base && \
    gem install bundler -v 1.17.3 --no-ri --no-rdoc && \
    cd /app ; bundle install --without development test && \
    apk del build-dependencies

WORKDIR /app
ADD . /app

ENV MALLOC_ARENA_MAX=2

ENTRYPOINT [ "/app/bin/flying-shuttle" ]
