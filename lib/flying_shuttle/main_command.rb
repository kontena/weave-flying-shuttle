# frozen_string_literal: true

require 'clamp'
require_relative 'peer_manager'

module FlyingShuttle
  class MainCommand < Clamp::Command
    include Logging

    def execute
      puts "~~ Flying Shuttle v#{FlyingShuttle::VERSION} ~~"
      puts ""

      manager = PeerManager.new
      manager.start
    end
  end
end
