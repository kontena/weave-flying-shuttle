# frozen_string_literal: true

require 'excon'

module FlyingShuttle
  module WeaveHelper
    def weave_client
      @weave_client ||= Excon.new('http://127.0.0.1:6784', persistent: true)
    end
  end
end
