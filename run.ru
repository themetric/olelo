#!/usr/bin/env rackup
# -*- coding: utf-8 -*-

start_time = Time.now

env ||= ENV['RACK_ENV'] || 'development'

path = ::File.expand_path(::File.dirname(__FILE__))

$LOAD_PATH << ::File.join(path, 'lib')
Dir[::File.join(path, 'deps', '*', 'lib')].each {|x| $: << x }

require 'rubygems'

# Load ruby 1.8 compatibility gem
if RUBY_VERSION < '1.9'
  # will soon be moved to gem
  # gem 'compatibility', '>= 0'
  require 'compatibility'
end

# We want to read all text data as UTF-8
Encoding.default_external = Encoding::UTF_8

require 'fileutils'
require 'logger'
require 'rack/patched_request'
require 'rack/session/security_patch'
require 'rack/relative_redirect'
require 'rack/remove_cache_buster'
require 'rack/encode'
require 'wiki/app'

# Try to load server gem
gem(server, '>= 0') rescue nil

config_file = if ENV['WIKI_CONFIG']
  ENV['WIKI_CONFIG']
else
  ::File.join(path, 'config.yml')
end

default_config = {
  :title        => 'Git-Wiki',
  :root         => path,
  :production   => false,
  :locale	=> 'en_US',
  :auth => {
    :service => 'yamlfile',
    :store   => ::File.join(path, '.wiki', 'users.yml'),
  },
  :cache => ::File.join(path, '.wiki', 'cache'),
  :mime => {
    :default => 'text/x-creole',
    :magic   => true,
  },
  :main_page    => 'Home',
  :disabled_plugins => [
    'authorization/private_wiki',
    'tagging',
    'filter/orgmode',
    'tag/math-ritex',
    'tag/math-itex2mml',
#   'tag/math-imaginator',
  ],
  :rack => {
    :esi          => true,
    :embed        => false,
    :rewrite_base => nil,
    :deflater     => true,
  },
  :git => {
    :repository => ::File.join(path, '.wiki', 'repository'),
  },
  :log => {
    :level => 'INFO',
    :file  => ::File.join(path, '.wiki', 'log'),
  },
}

Wiki::Config.update(default_config)
Wiki::Config.load(config_file)

use Rack::RemoveCacheBuster # remove jquery cache buster
use Rack::RelativeRedirect
use Rack::Session::Pool
use Rack::MethodOverride

if Wiki::Config.rack.deflater?
  require 'rack/deflater'
  use Rack::Deflater
end

if Wiki::Config.rack.embed?
  gem 'rack-embed', '>= 0'
  require 'rack/embed'
  use Rack::Embed, :threaded => true
end

if Wiki::Config.rack.esi?
  gem 'minad-rack-esi', '>= 0'
  require 'rack/esi'
  use Rack::ESI

  if env == 'deployment' || env == 'production'
    gem 'rack-cache', '>= 0.5.2'
    require 'rack/cache'
    require 'rack/purge'
    use Rack::Purge
    use Rack::Cache,
      :verbose     => false,
      :metastore   => "file:#{::File.join(Wiki::Config.cache, 'rack', 'meta')}",
      :entitystore => "file:#{::File.join(Wiki::Config.cache, 'rack', 'entity')}"
    Wiki::Config.production = true
  end
end

if !Wiki::Config.rack.rewrite_base.blank?
  require 'rack/rewrite'
  use Rack::Rewrite, :base => Wiki::Config.rack.rewrite_base
end

FileUtils.mkpath Wiki::Config.cache, :mode => 0755
FileUtils.mkpath ::File.dirname(Wiki::Config.log.file), :mode => 0755
logger = Logger.new(Wiki::Config.log.file)
logger.level = Logger.const_get(Wiki::Config.log.level)

use Rack::CommonLogger, logger

use Rack::Static, :urls => ['/static'], :root => path
use Rack::Encode
run Wiki::App.new(nil, :logger => logger)

logger.info "Wiki successfully started in #{((Time.now - start_time) * 1000).to_i}ms"
