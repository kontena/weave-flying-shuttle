# frozen_string_literal: true

require 'contracts'
require 'concurrent'

module FlyingShuttle
  VERSION = '0.2.0'

  C = Contracts
end

require_relative 'flying_shuttle/main_command'
