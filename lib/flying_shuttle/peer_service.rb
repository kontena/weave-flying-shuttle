# frozen_string_literal: true

require_relative "mixins/logging"

module FlyingShuttle
  class PeerService
    include Logging

    REGION_LABEL = FlyingShuttle::REGION_LABEL
    EXTERNAL_ADDRESS_LABEL = 'node-address.kontena.io/external-ip'

    attr_reader :this_peer, :weave_client

    # @param this_peer [K8s::Resource]
    # @param weave_client [Excon]
    def initialize(this_peer, weave_client: Excon.new('http://127.0.0.1:6784', persistent: true))
      @this_peer = this_peer
      @weave_client = weave_client
      @previous_peers = []
    end

    # @param peers [Array<K8s::Resource>]
    # @param external_addresses [Array<String>]
    # @return [Array<String>]
    def update_peers(peers, external_addresses)
      peer_addresses = []
      peers.each do |peer|
        if peer.metadata.labels[REGION_LABEL] == this_peer.metadata.labels[REGION_LABEL]
          address = peer.status.addresses.find { |addr| addr.type == 'InternalIP'}&.address
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
