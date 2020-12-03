FROM ruby:2.7-alpine AS base

ENV APP_DIR="/srv/app" \
    BUNDLE_PATH="/srv/bundler" \
    BUILD_PACKAGES="build-base ruby-dev" \
    APP_PACKAGES="bash curl tzdata" \
    RELEASE_PACKAGES="bash" \
    APP_USER="app"

# Thes env var definitions reference values from the previous definitions, so
# they need to be split off on their own. Otherwise, they'll receive stale
# values because Docker will read the values once before it starts setting
# values.
ENV BUNDLE_BIN="${BUNDLE_PATH}/bin" \
    GEM_HOME="${BUNDLE_PATH}"
ENV PATH="${APP_DIR}:${BUNDLE_BIN}:${PATH}"

RUN mkdir -p $APP_DIR $BUNDLE_PATH
WORKDIR $APP_DIR

FROM base as build

COPY Gemfile* *.gemspec $APP_DIR/
COPY lib/kubetruth/version.rb $APP_DIR/lib/kubetruth/

RUN apk --update upgrade && \
  apk add \
    --virtual app \
    $APP_PACKAGES && \
  apk add \
    --virtual build_deps \
    $BUILD_PACKAGES && \
  bundle install && \
  apk del build_deps && \
  rm -rf /var/cache/apk/*

COPY . $APP_DIR/
RUN bundle install --deployment --jobs=4 --without development test

FROM base AS release

RUN apk --update upgrade && \
  apk add \
    --virtual app \
    $RELEASE_PACKAGES && \
  rm -rf /var/cache/apk/*

COPY --from=build $BUNDLE_PATH $BUNDLE_PATH
COPY --from=build $APP_DIR $APP_DIR

# Specify the script to use when running the container
ENTRYPOINT ["entrypoint.sh"]
# Start the main app process by sending the "app" parameter to the entrypoint
CMD ["app"]
