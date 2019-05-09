# frozen_string_literal: true

require 'concurrent'

module FlyingShuttle
  VERSION = '0.2.0'
  REGION_LABEL = 'failure-domain.beta.kubernetes.io/region'
end

require_relative 'flying_shuttle/main_command'
