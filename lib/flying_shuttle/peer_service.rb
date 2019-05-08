# frozen_string_literal: true

require_relative "mixins/logging"
require_relative "mixins/weave_helper"

module FlyingShuttle
  class PeerService
    include Logging
    include WeaveHelper

    REGION_LABEL = FlyingShuttle::REGION_LABEL
    EXTERNAL_ADDRESS_LABEL = 'node-address.kontena.io/external-ip'

    def initialize
      @previous_peers = []
    end

    # @param this_peer [K8s::Resource]
    # @param peers [Array<K8s::Resource>]
    # @param external_addresses [Array<String>]
    # @return [Array<String>]
    def update_peers(this_peer, peers, external_addresses)
      peer_addresses = []
      peers.each do |peer|
        if peer.region == this_peer.region
          address = peer.address_for('InternalIP')&.address
          peer_addresses << address if address
        else
          address = peer.metadata.labels[EXTERNAL_ADDRESS_LABEL]
          peer_addresses << address if address
        end
      end
      peer_addresses = peer_addresses + external_addresses
      peer_addresses.sort!

      if peer_addresses != @previous_peers
        logger.info { "peers: #{peer_addresses.join(',')}" }
        set_peers(peer_addresses)
      else
        logger.info { "no changes detected" }
      end

      peer_addresses
    end

    # @param peer_addresses [Array<String>]
    # @return [Boolean]
    def set_peers(peer_addresses)
      peers = peer_addresses.map { |addr| "peer[]=#{addr}"}.join("&")
      response = weave_client.post(
        path: "/connect",
        body: "#{peers}&replace=true",
        headers: { "Content-Type" => "application/x-www-form-urlencoded" }
      )
      return false unless response.status == 200

      @previous_peers = peer_addresses

      true
    end
  end
end
