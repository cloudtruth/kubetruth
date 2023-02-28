FROM ruby:3.0-alpine AS base

ARG APP_USER_UID=65532
ARG APP_USER_GID=65532

ENV APP_DIR="/srv/app" \
    BUNDLE_PATH="/srv/bundler" \
    BUILD_PACKAGES="build-base ruby-dev" \
    APP_PACKAGES="bash curl tzdata git less" \
    RELEASE_PACKAGES="bash shadow" \
    APP_USER="app"

# Thes env var definitions reference values from the previous definitions, so
# they need to be split off on their own. Otherwise, they'll receive stale
# values because Docker will read the values once before it starts setting
# values.
ENV BUNDLE_BIN="${BUNDLE_PATH}/bin" \
    BUNDLE_APP_CONFIG="${BUNDLE_PATH}" \
    GEM_HOME="${BUNDLE_PATH}"
ENV PATH="${APP_DIR}:${APP_DIR}/bin:${BUNDLE_BIN}:${PATH}"

RUN mkdir -p $APP_DIR $BUNDLE_PATH
WORKDIR $APP_DIR

FROM base as build

RUN apk add --no-cache \
    --virtual app \
    $APP_PACKAGES && \
  apk add --no-cache \
    --virtual build_deps \
    $BUILD_PACKAGES

COPY client $APP_DIR/client
COPY Gemfile* $APP_DIR/
RUN bundle config --local without 'development test' && \
    bundle install --jobs=4

RUN apk add --no-cache -X http://dl-cdn.alpinelinux.org/alpine/edge/testing kubectl

COPY . $APP_DIR/


FROM build as development

RUN bundle config --local --delete without && \
    bundle install --jobs=4

# Specify the script to use when running the container
ENTRYPOINT ["entrypoint.sh"]
# Start the main app process by sending the "app" parameter to the entrypoint
CMD ["app"]


FROM base AS release

RUN apk add --no-cache \
    --virtual app \
    $RELEASE_PACKAGES

# Create a non-root user for running the container
RUN groupadd -g $APP_USER_GID $APP_USER
RUN useradd --no-log-init --create-home --shell /bin/false --gid $APP_USER_GID --uid $APP_USER_UID $APP_USER

COPY --from=build $BUNDLE_PATH $BUNDLE_PATH
COPY --from=build $APP_DIR $APP_DIR

# make sure Gemfile.lock has correct platform so running doesn't require touching it
RUN ruby -r 'bundler/setup' -e ''

USER ${APP_USER}

# Specify the script to use when running the container
ENTRYPOINT ["entrypoint.sh"]
# Start the main app process by sending the "app" parameter to the entrypoint
CMD ["app"]
