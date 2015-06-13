FROM ubuntu:14.04
MAINTAINER Eric Raio <eric@car.social> (@ericraio)

RUN locale-gen --no-purge en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV DEBIAN_FRONTEND noninteractive
ENV RUBY_VERSION 2.2.2
ENV RUBY_MAJOR 2.2

#################################
# native libs
#################################

RUN apt-get update -qq
RUN apt-get upgrade -qq -y

RUN apt-get install -y wget curl git git-core build-essential zlib1g-dev libssl-dev libreadline-dev libyaml-dev libsqlite3-dev sqlite3 libxml2-dev libxslt1-dev cron rsyslog

# Clean up APT when done.
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

#################################
# install ruby
#################################

RUN wget -O ruby-2.2.2.tar.gz http://ftp.ruby-lang.org/pub/ruby/2.1/ruby-2.2.2.tar.gz
RUN tar -xzf ruby-2.2.2.tar.gz
RUN cd ruby-2.2.2/ && ./configure && make && make install

RUN echo "gem: --no-ri --no-rdoc" > ~/.gemrc
RUN gem install bundler
RUN gem install foreman
