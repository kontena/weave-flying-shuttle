# frozen_string_literal: true

require_relative 'mixins/client_helper'
require_relative 'mixins/logging'
require_relative 'peer_service'
require_relative 'route_service'

module FlyingShuttle
  class PeerManager
    include ClientHelper
    include Logging

    def initialize
      @previous_peers = []
    end

    def start
      poll!
    end

    def poll!
      loop do
        begin
          sleep(rand(10.0 ... 30.0))
          peers = client.api('v1').resource('nodes').list
          this_peer = peers.find { |peer| peer.metadata.name == hostname }
          if this_peer
            peers.delete(this_peer)
            PeerService.new(this_peer).update_peers(peers, external_addresses)
            RouteService.new(this_peer, peers).update_routes
          else
            logger.warn "cannot find self from list of peers"
          end
        rescue => ex
          logger.error "error while polling: #{ex.message}"
          logger.error ex.backtrace.join("\n")
        end
      end
    end

    # @return [Array<String>]
    def external_addresses
      configmap = client.api('v1').resource('configmaps', namespace: 'kube-system').get('flying-shuttle')

      return [] unless configmap.data['known-peers']

      data = JSON.parse(configmap.data['known-peers'])
      data['peers'] || []
    rescue K8s::Error::NotFound
      []
    end

    # @return [String]
    def hostname
      ENV.fetch('HOSTNAME')
    end
  end
end
