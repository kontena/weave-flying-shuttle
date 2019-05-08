# frozen_string_literal: true

require 'socket'
require_relative 'mixins/client_helper'
require_relative 'mixins/logging'
require_relative 'peer'
require_relative 'peer_service'
require_relative 'route_service'

module FlyingShuttle
  class PeerManager
    include ClientHelper
    include Logging

    SIOCGIFADDR = 0x8915

    def initialize
      @previous_peers = []
    end

    def start
      poll!
    end

    def poll!
      peer_service = PeerService.new
      loop do
        begin
          peers = client.api('v1').resource('nodes').list.map { |node| Peer.new(node) }
          this_peer = peers.find { |peer| peer.name == hostname }
          if this_peer
            update_node_annotations(this_peer)
            peers.delete(this_peer)
            peer_service.update_peers(this_peer, peers, external_addresses)
            RouteService.new(this_peer, peers).update_routes
          else
            logger.warn "cannot find self from list of peers"
          end
          sleep(rand(10.0 ... 30.0))
        rescue => ex
          logger.error "error while polling: #{ex.message}"
          logger.error ex.backtrace.join("\n")
          sleep 1
        end
      end
    end

    # @param peer [FlyingShuttle::Peer]
    def update_node_annotations(peer)
      return if peer.weave_interface_ip.to_s == weave_interface_ip

      peer.weave_interface_ip = weave_interface_ip
      client.api('v1').resource('nodes').merge_patch(peer.name, {
        metadata: {
          annotations: {
            'weave.kontena.io/bridge-ip' => weave_interface_ip
          }
        }
      })
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

    # @return [String]
    def weave_interface_ip
      @weave_interface_ip ||= interface_ip('weave')
    end

    # @param [String] iface
    # @return [String, NilClass]
    def interface_ip(iface)
      sock = UDPSocket.new
      buf = [iface,""].pack('a16h16')
      sock.ioctl(SIOCGIFADDR, buf);
      sock.close
      buf[20..24].unpack("CCCC").join(".")
    rescue Errno::EADDRNOTAVAIL
      # interface is up, but does not have any address configured
      nil
    rescue Errno::ENODEV
      nil
    end
  end
end
