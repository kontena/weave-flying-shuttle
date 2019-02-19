# frozen_string_literal: true

require_relative 'mixins/client_helper'
require_relative 'mixins/logging'

module FlyingShuttle
  class PeerManager
    include Contracts::Core
    include ClientHelper
    include Logging

    REGION_LABEL = 'failure-domain.beta.kubernetes.io/region'
    EXTERNAL_ADDRESS_LABEL = 'node-address.kontena.io/external-ip'

    Contract Excon::Connection => C::Any
    def initialize(weave_client = Excon.new('http://127.0.0.1:6784', persistent: true))
      @weave_client = weave_client
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
          update_peers(peers, external_addresses)
        rescue => ex
          logger.error { "error while polling: #{ex.message}" }
        end
      end
    end

    Contract [] => C::ArrayOf[String]
    def external_addresses
      configmap = client.api('v1').resource('configmaps', namespace: 'kube-system').get('flying-shuttle')

      return [] unless configmap.data['known-peers']

      data = JSON.parse(configmap.data['known-peers'])
      data['peers'] || []
    rescue K8s::Error::NotFound
      []
    end

    Contract C::ArrayOf[K8s::Resource], C::ArrayOf[String] => C::ArrayOf[String]
    def update_peers(peers, external_addresses)
      this_peer = peers.find { |peer| peer.metadata.name == hostname }
      peers.delete(this_peer)
      peer_addresses = []
      peers.each do |peer|
        if peer.metadata.labels[REGION_LABEL] == this_peer.metadata.labels[REGION_LABEL]
          peer_addresses << peer.status.addresses.find { |addr| addr.type == 'InternalIP'}.address
        else
          peer_addresses << peer.metadata.labels[EXTERNAL_ADDRESS_LABEL]
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

    Contract C::ArrayOf[String] => C::Bool
    def set_peers(peer_addresses)
      peers = peer_addresses.map { |addr| "peer[]=#{addr}"}.join("&")
      response = @weave_client.post(
        path: "/connect",
        body: "#{peers}&replace=true",
        headers: { "Content-Type" => "application/x-www-form-urlencoded" }
      )
      return false unless response.status == 200

      @previous_peers = peer_addresses

      true
    end

    def hostname
      ENV.fetch('HOSTNAME')
    end
  end
end
