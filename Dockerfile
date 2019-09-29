# Based on https://gist.github.com/tylerchr/15a74b05944cfb90729db6a51265b6c9
#
# Building V8 for alpine is a real pain. We have to compile from source, because it has to be
# linked against musl, and we also have to recompile some of the build tools as the official
# build workflow tends to assume glibc by including vendored tools that link against it.
#
# The general strategy is this:
#
#   1. Build GN for alpine (this is a build dependency)
#   2. Use depot_tools to fetch the V8 source and dependencies (needs glibc)
#   3. Build V8 for alpine
#   4. Make warez
#

#
# STEP 1
# Build GN for alpine
#
FROM alpine:latest as gn-builder

# This is the GN commit that we want to build. Most commits will probably build just fine but
# this happened to be the latest commit when I did this.
ARG GN_COMMIT=d7111cb6877187d1f378bd231e14ffdd5fdd87ae

RUN \
  apk add --update --virtual .gn-build-dependencies \
    alpine-sdk \
    binutils-gold \
    clang \
    curl \
    git \
    llvm4 \
    ninja \
    python \
    tar \
    xz \

  # Two quick fixes: we need the LLVM tooling in $PATH, and we
  # also have to use gold instead of ld.
  && PATH=$PATH:/usr/lib/llvm4/bin \
  && cp -f /usr/bin/ld.gold /usr/bin/ld \

  # Clone and build gn
  && git clone https://gn.googlesource.com/gn /tmp/gn \
  && git -C /tmp/gn checkout ${GN_COMMIT} \
  && cd /tmp/gn \
  && python build/gen.py --no-sysroot \
  && ninja -C out \
  && cp -f /tmp/gn/out/gn /usr/local/bin/gn \

  # Remove build dependencies and temporary files
  && apk del .gn-build-dependencies \
  && rm -rf /tmp/* /var/tmp/* /var/cache/apk/*

#
# STEP 2
# Use depot_tools to fetch the V8 source and dependencies
#
# The depot_tools scripts have a hard dependency on glibc (or at least a soft one that I didn't
# bother figuring out). Fortunately we only need it to actually download the source and its dependencies
# so we can do this in a place with glibc, and then pass the results on to an alpine builder.
#
FROM debian:9 as source

# The V8 version we want to use. It's assumed that this will be a version tag, but it's just
# used as "git commit $V8_VERSION" so anything that git can resolve will work.
ARG V8_VERSION=6.7.288.46

RUN \
  set -x && \
  apt-get update && \
  apt-get install -y \
    git \
    curl \
    python && \

  # Clone depot_tools
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git /tmp/depot_tools && \
  PATH=$PATH:/tmp/depot_tools && \

  # fetch V8
  cd /tmp && \
  fetch v8 && \
  cd /tmp/v8 && \
  git checkout ${V8_VERSION} && \
  gclient sync && \

  # cleanup
  apt-get remove --purge -y \
    git \
    curl \
    python && \
  apt-get autoremove -y && \
  rm -rf /var/lib/apt/lists/*

#
# STEP 3
# Build V8 for alpine
#
FROM alpine:latest as v8

COPY --from=source /tmp/v8 /tmp/v8
COPY --from=gn-builder /usr/local/bin/gn /tmp/v8/buildtools/linux64/gn
COPY BUILD.gn /tmp/v8/BUILD.gn
COPY build-config-BUILD.gn /tmp/v8/build/config/BUILD.gn

RUN \
  apk add --update --virtual .v8-build-dependencies \
    curl \
    g++ \
    gcc \
    glib-dev \
    icu-dev \
    libstdc++ \
    linux-headers \
    make \
    ninja \
    python \
    tar \
    xz \

  # Configure our V8 build
  && cd /tmp/v8 && \
  ./tools/dev/v8gen.py x64.release -- \
    binutils_path=\"/usr/bin\" \
    target_os=\"linux\" \
    target_cpu=\"x64\" \
    v8_target_cpu=\"x64\" \
    v8_enable_future=true \
    is_official_build=true \
    is_component_build=false \
    is_cfi=false \
    is_clang=false \
    use_custom_libcxx=false \
    use_sysroot=false \
    use_gold=false \
    use_allocator_shim=false \
    treat_warnings_as_errors=false \
    symbol_level=0 \
    strip_debug_info=true \
    v8_use_external_startup_data=false \
    v8_enable_i18n_support=false \
    v8_enable_gdbjit=false \
    v8_static_library=true \
    v8_experimental_extra_library_files=[] \
    v8_extra_library_files=[] \
    v8_monolithic=true \

  # Build V8
  && ninja -C out.gn/x64.release -j $(getconf _NPROCESSORS_ONLN) \

  # Brag
  && find /tmp/v8/out.gn/x64.release -name '*.a' \

  # clean up
  && apk del .v8-build-dependencies


RUN apk add --no-cache \
		gmp-dev

# skip installing gem documentation
RUN mkdir -p /usr/local/etc \
	&& { \
		echo 'install: --no-document'; \
		echo 'update: --no-document'; \
	} >> /usr/local/etc/gemrc

ENV RUBY_MAJOR 2.6
ENV RUBY_VERSION 2.6.3
ENV RUBY_DOWNLOAD_SHA256 11a83f85c03d3f0fc9b8a9b6cad1b2674f26c5aaa43ba858d4b0fcc2b54171e1

# some of ruby's build scripts are written in ruby
#   we purge system ruby later to make sure our final image uses what we just built
# readline-dev vs libedit-dev: https://bugs.ruby-lang.org/issues/11869 and https://github.com/docker-library/ruby/issues/75
RUN set -ex \
	\
	&& apk add --update alpine-sdk \
	&& apk add --no-cache --virtual .ruby-builddeps \
		autoconf \
		bash \
		bison \
		bzip2 \
		bzip2-dev \
		build-base \
		ca-certificates \
		coreutils \
		dpkg-dev dpkg \
		gcc \
		git \
		gdbm-dev \
		glib-dev \
		libc-dev \
		libffi-dev \
		libxml2-dev \
		libxslt-dev \
		linux-headers \
		make \
		ncurses-dev \
		libressl \
		libressl-dev \
		procps \
		readline-dev \
		ruby \
		tar \
		xz \
		yaml-dev \
		zlib-dev \
		chromium-chromedriver \
	\
	&& wget -O ruby.tar.xz "https://cache.ruby-lang.org/pub/ruby/${RUBY_MAJOR%-rc}/ruby-$RUBY_VERSION.tar.xz" \
	&& echo "$RUBY_DOWNLOAD_SHA256 *ruby.tar.xz" | sha256sum -c - \
	\
	&& mkdir -p /usr/src/ruby \
	&& tar -xJf ruby.tar.xz -C /usr/src/ruby --strip-components=1 \
	&& rm ruby.tar.xz \
	\
	&& cd /usr/src/ruby \
	\
# https://github.com/docker-library/ruby/issues/196
# https://bugs.ruby-lang.org/issues/14387#note-13 (patch source)
# https://bugs.ruby-lang.org/issues/14387#note-16 ("Therefore ncopa's patch looks good for me in general." -- only breaks glibc which doesn't matter here)
	&& wget -O 'thread-stack-fix.patch' 'https://bugs.ruby-lang.org/attachments/download/7081/0001-thread_pthread.c-make-get_main_stack-portable-on-lin.patch' \
	&& echo '3ab628a51d92fdf0d2b5835e93564857aea73e0c1de00313864a94a6255cb645 *thread-stack-fix.patch' | sha256sum -c - \
	&& patch -p1 -i thread-stack-fix.patch \
	&& rm thread-stack-fix.patch \
	\
# hack in "ENABLE_PATH_CHECK" disabling to suppress:
#   warning: Insecure world writable dir
	&& { \
		echo '#define ENABLE_PATH_CHECK 0'; \
		echo; \
		cat file.c; \
	} > file.c.new \
	&& mv file.c.new file.c \
	\
	&& autoconf \
	&& gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)" \
# the configure script does not detect isnan/isinf as macros
	&& export ac_cv_func_isnan=yes ac_cv_func_isinf=yes \
	&& ./configure \
		--build="$gnuArch" \
		--disable-install-doc \
		--enable-shared \
	&& make -j "$(nproc)" \
	&& make install \
	\
	&& runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)" \
	&& apk add --no-network --virtual .ruby-rundeps $runDeps \
		bzip2 \
		ca-certificates \
		libffi-dev \
		procps \
		yaml-dev \
		zlib-dev \
	&& apk del --no-network .ruby-builddeps \
	&& cd / \
	&& rm -r /usr/src/ruby \
# rough smoke test
	&& ruby --version && gem --version && bundle --version

# install things globally, for great justice
# and don't create ".bundle" in all our apps
ENV GEM_HOME /usr/local/bundle
ENV BUNDLE_PATH="$GEM_HOME" \
	BUNDLE_SILENCE_ROOT_WARNING=1 \
	BUNDLE_APP_CONFIG="$GEM_HOME"
# path recommendation: https://github.com/bundler/bundler/pull/6469#issuecomment-383235438
ENV PATH $GEM_HOME/bin:$BUNDLE_PATH/gems/bin:$PATH
# adjust permissions of a few directories for running "gem install" as an arbitrary user
RUN mkdir -p "$GEM_HOME" && chmod 777 "$GEM_HOME"
# (BUNDLE_PATH = GEM_HOME, no need to mkdir/chown both)


# COPY --from=v8 /tmp/v8/include /tmp/v8/include
# COPY --from=v8 /tmp/v8/out.gn/x64.release/obj /tmp/v8/lib

ENV LIBV8_VERSION 6.7.288.46.1

RUN gem install libv8 -v $LIBV8_VERSION

COPY --from=v8 /tmp/v8/include /usr/local/bundle/gems/libv8-$LIBV8_VERSION-x86_64-linux/vendor/v8/include
COPY --from=v8 /tmp/v8/out.gn/x64.release/obj/libv8_monolith.a /usr/local/bundle/gems/libv8-$LIBV8_VERSION-x86_64-linux/vendor/v8/out.gn/libv8/obj/libv8_monolith.a
COPY --from=v8 /tmp/v8/out.gn/x64.release/obj/libv8_libplatform.a /usr/local/bundle/gems/libv8-$LIBV8_VERSION-x86_64-linux/vendor/v8/out.gn/libv8/obj/libv8_libplatform.a
COPY --from=v8 /tmp/v8/out.gn/x64.release/obj/libv8_libbase.a /usr/local/bundle/gems/libv8-$LIBV8_VERSION-x86_64-linux/vendor/v8/out.gn/libv8/obj/libv8_libbase.a

RUN apk add --update alpine-sdk && gem install mini_racer && apk del alpine-sdk && apk add libstdc++

CMD [ "irb" ]
