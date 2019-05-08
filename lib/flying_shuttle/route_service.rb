# frozen_string_literal: true

require 'open3'
require_relative 'mixins/weave_helper'
require_relative 'mixins/logging'

module FlyingShuttle
  class RouteService
    include Logging
    include WeaveHelper

    REGION_LABEL = FlyingShuttle::REGION_LABEL
    IPTABLES_DNAT = 'iptables %s -w -t nat -p tcp -d %s --dport 10250  -j DNAT --to-destination %s:10250'

    attr_reader :this_peer, :peers

    # @param this_peer [K8s::Resource]
    # @param peers [Array<K8s::Resource>]
    def initialize(this_peer, peers)
      @this_peer = this_peer
      @peers = peers
    end

    # @return [Array<FlyingShuttle>] added routes
    def update_routes
      peers = peers_needing_routes
      logger.debug "peers needing route: #{peers.map(&:name).join(',')}"
      current_peers = currently_routed_peers

      (peers - current_peers).each do |peer|
        ensure_route(peer)
      end
      orphan_peers.each do |peer|
        remove_route(peer)
      end

      (peers - current_peers)
    end

    # @param peer [FlyingShuttle::Peer]
    # @return [Boolean]
    def ensure_route(peer)
      dest_address = peer.weave_interface_ip
      unless dest_address
        logger.error "cannot find weave bridge for #{peer.name}"
        return false
      end

      address = peer.peer_address.address

      _, output = run_cmd(IPTABLES_DNAT % ['-C OUTPUT', address, dest_address])
      _, prerouting = run_cmd(IPTABLES_DNAT % ['-C PREROUTING', address, dest_address])
      return true if output.success? && prerouting.success?

      logger.info "adding DNAT for #{address} via weave #{dest_address}"
      comment = ' -m comment --comment "weave-fs-ip=%s"' % [address]
      _, output = run_cmd(IPTABLES_DNAT % ['-I OUTPUT 1', address, dest_address] + comment) unless output.success?
      _, prerouting = run_cmd(IPTABLES_DNAT % ['-I PREROUTING 1', address, dest_address] + comment) unless prerouting.success?

      output.success? && prerouting.success?
    end

    # @param peer [FlyingShuttle::Peer]
    # @return [Boolean]
    def remove_route(peer)
      dest_address = peer.weave_interface_ip
      return false unless dest_address

      address = peer.peer_address.address
      comment = ' -m comment --comment "weave-fs-ip=%s"' % [address]
      _, output = run_cmd(IPTABLES_DNAT % ['-C OUTPUT', address, dest_address] + comment)
      _, prerouting = run_cmd(IPTABLES_DNAT % ['-C PREROUTING', address, dest_address] + comment)
      if !output.success? && !prerouting.success?
        logger.info "did not find matching DNAT rules for #{address}.. maybe they have already removed"
        return true
      end

      logger.info "removing DNAT for #{address} via weave #{dest_address}"
      _, output = run_cmd(IPTABLES_DNAT % ['-D OUTPUT', address, dest_address] + comment) if output.success?
      _, prerouting = run_cmd(IPTABLES_DNAT % ['-D PREROUTING', address, dest_address] + comment) if prerouting.success?

      output.success? && prerouting.success?
    end

    # @return [Array<FlyingShuttle::Peer>]
    def peers_needing_routes
      peers.select do |peer|
        peer.region != this_peer.region && peer.peer_address&.address
      end
    end

    # @return [Array<FlyingShuttle::Peer>]
    def currently_routed_peers
      current_peers = []
      output, _ = run_cmd('iptables -L -n -t nat')
      output.lines.each do |line|
        if match = line.strip.match(/.+weave-fs-ip=(\S+).+/)
          address = match.captures.first
          if peer = peers.find { |peer| peer.peer_address&.address == address }
            current_peers << peer
          end
        end
      end

      current_peers.uniq
    end

    # @return [Array<FlyingShuttle::Peer>]
    def orphan_peers
      orphan_peers = []
      output, _ = run_cmd('iptables -L -n -t nat')
      output.lines.each do |line|
        if match = line.strip.match(/.+weave-fs-ip=(\S+).+to:(\S+):10250/)
          address = match.captures[0]
          bridge_ip = match.captures[1]
          unless peers.find { |peer| peer.peer_address&.address == address }
            orphan_peers << FlyingShuttle::Peer.new(K8s::Resource.new({
              metadata: {
                annotations: {
                  'weave.kontena.io/bridge-ip' => bridge_ip
                }
              },
              status: {
                addresses: [
                  { type: 'InternalIP', address: address }
                ]
              }
            }))
          end
        end
      end

      orphan_peers.uniq
    end

    # @param cmd [Array<String>, String]
    # @return [Array(String, Process::Status)]
    def run_cmd(cmd)
      cmd = cmd.is_a?(Array) ? cmd.join(' ') : cmd
      logger.debug "running command: #{cmd}"
      Open3.capture2e(cmd)
    end
  end
end
