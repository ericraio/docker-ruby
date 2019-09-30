FROM ruby:2.6.4-alpine3.10

MAINTAINER eric@ericraio.com

ENV LIBV8_BRANCH v5.9.211.38.1
ENV LIBV8_VERSION 5.9.211.38.1-x86_64-linux

RUN set -ex \
    && apk add --update --no-cache --virtual .builddeps \
      make \
      python \
      git \
      bash \
      curl \
      findutils \
      binutils-gold \
      tar \
      linux-headers \
      build-base \
      xz \
      chromium-chromedriver \
    \
    && git clone -b $LIBV8_BRANCH --recursive git://github.com/cowboyd/libv8.git \
    && cd /libv8 \
    && git checkout v6.0.286.44.0beta1 vendor/.gclient \
    && git checkout v6.0.286.44.0beta1 vendor/.gclient_entries \
    && export GYP_DEFINES="$GYP_DEFINES linux_use_bundled_binutils=0 linux_use_bundled_gold=0" \
    && export PATH=/libv8/vendor/depot_tools:"$PATH" \
    && cd vendor \
    && DEPOT_TOOLS_UPDATE=0 gclient sync --with_branch_heads \
    && bundle install \
    && bundle exec rake binary \
    && gem install /libv8/pkg/libv8-$LIBV8_VERSION.gem \
    && mkdir /root/pkg \
    && mv /libv8/pkg/libv8-$LIBV8_VERSION.gem /root/pkg/ \
    && gem install mini_racer \
    && cd / \
    && apk del --purge .builddeps \
    && rm -rf /libv8 /tmp/* /var/tmp/* /var/cache/apk/*QQ /usr/local/bundle/gems/libv8-$LIBV8_VERSION/vendor

RUN apk add libstdc++
RUN ruby -rmini_racer -e "raise 'eval raised or wasnt 42' unless p MiniRacer::Context.new.eval('7 * 6') == 42"
