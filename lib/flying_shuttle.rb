# frozen_string_literal: true

require 'contracts'
require 'concurrent'

module FlyingShuttle
  VERSION = '0.1.0'

  C = Contracts
end

require_relative 'flying_shuttle/main_command'