# frozen_string_literal: true

require 'logger'

module FlyingShuttle
  module Logging
    def logger
      return @logger if @logger

      @logger = Logger.new(STDOUT)
      @logger.progname = self.class.name.sub('FlyingShuttle::', '')
      if ENV['DEBUG'].to_s == 'true'
        @logger.level = Logger::DEBUG
      else
        @logger.level = Logger::INFO
      end

      @logger
    end
  end
end
