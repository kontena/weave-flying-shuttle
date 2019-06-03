# frozen_string_literal: true

require_relative "mixins/logging"
require_relative "mixins/weave_helper"

module FlyingShuttle
  class PeerService
    include Logging
    include WeaveHelper

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
          address = peer.address_for('InternalIP')&.address || peer.address_for('ExternalIP')&.address
          peer_addresses << address if address
        else
          address = peer.address_for('ExternalIP')&.address || peer.metadata.labels[EXTERNAL_ADDRESS_LABEL]
          peer_addresses << address if address
        end
      end
      peer_addresses = peer_addresses + external_addresses
      peer_addresses.sort!

      logger.info "peers: #{peer_addresses.join(',')}" if peer_addresses != @previous_peers
      set_peers(peer_addresses)

      peer_addresses
    end

    # @param peer_addresses [Array<String>]
    # @return [Boolean]
    def set_peers(peer_addresses)
      peers = peer_addresses.map { |addr| "peer=#{addr}"}.join("&")
      response = weave_client.post(
        path: "/connect",
        body: "#{peers}&replace=true",
        headers: { "Content-Type" => "application/x-www-form-urlencoded" }
      )
      unless response.status == 200
        logger.error "failed to connect peers: #{response.status} - #{response.body}"
        return false
      end

      @previous_peers = peer_addresses

      true
    end
  end
end
