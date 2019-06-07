FROM ubuntu:18.04
MAINTAINER Eric Raio <eric@ericraio.com> (@ericraio)

ENV LC_ALL en_US.UTF-8
ENV DEBIAN_FRONTEND noninteractive
ENV RUBY_VERSION 2.6.3
ENV RUBY_MAJOR 2.6
ENV RUBYOPT "-r openssl"

#################################
# native libs
#################################

RUN apt-get update -qq
RUN apt-get upgrade -qq -y

RUN apt-get install -y software-properties-common wget curl git git-core build-essential libjemalloc-dev locales zlib1g-dev libssl-dev libreadline-dev libyaml-dev libsqlite3-dev sqlite3 libxml2-dev libxslt1-dev cron rsyslog libcurl3 libcurl3-gnutls libcurl4-openssl-dev pkg-config automake autoconf libtool

# Clean up APT when done.
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

#################################
# install ruby
#################################

RUN locale-gen --no-purge en_US.UTF-8
RUN cd /tmp && wget -O ruby-2.6.3.tar.gz http://ftp.ruby-lang.org/pub/ruby/2.6/ruby-2.6.3.tar.gz
RUN tar -xzf ruby-2.6.3.tar.gz
RUN cd ruby-2.6.3/ && ./configure --with-jemalloc && make && make install

RUN echo "gem: --no-ri --no-rdoc" > ~/.gemrc
RUN gem install bundler
RUN gem install foreman
