# frozen_string_literal: true

require 'socket'
require 'open3'
require_relative 'mixins/client_helper'
require_relative 'mixins/logging'

module FlyingShuttle
  class RouteService
    REGION_LABEL = FlyingShuttle::REGION_LABEL
    ROUTE_REGEX = /(\d+\.\d+\.\d+\.\d+) dev weave scope link src \d+\.\d+\.\d+\.\d+/

    attr_reader :this_peer, :peers

    # @param this_peer [K8s::Resource]
    # @param peers [Array<K8s::Resource>]
    def initialize(this_peer, peers)
      @this_peer = this_peer
      @peers = peers
    end

    # @return [Array<String>] added routes
    def update_routes
      addresses = addresses_needing_route
      current_addresses = currently_routed_addresses
      (addresses - current_addresses).each do |address|
        ensure_route(address)
      end
      (current_addresses - addresses).each do |address|
        remove_route(address)
      end

      (addresses - current_addresses)
    end

    # @param address [String]
    # @return [Boolean]
    def ensure_route(address)
      logger.info "adding route for #{address} via weave #{weave_interface_ip}"
      output, _ = run_cmd(['ip', 'route', 'get', address])
      return true if output.include?("#{address} dev weave scope link src")

      _, status = run_cmd(['ip', 'route', 'add', address, 'dev', 'weave', 'src', weave_interface_ip])
      status.success?
    end

    # @param address [String]
    # @return [Boolean]
    def remove_route(address)
      logger.info "removing route for #{address} via weave #{weave_interface_ip}"
      output, _ = run_cmd(['ip', 'route'])
      return true unless output.include?("#{address} dev weave scope link src")

      _, status = run_cmd(['ip', 'route', 'del', address, 'dev', 'weave', 'src', weave_interface_ip])
      status.success?
    end

    # @return [Array<String>]
    def addresses_needing_route
      addresses = []
      peers_needing_routes.each do |peer|
        addresses = peer.status.addresses
        address = addresses.find { |addr| addr.type == 'InternalIP' } || addresses.find { |addr| addr.type == 'ExternalIP' }
        if address && address = address.address
          addresses << address
        end
      end
      addresses
    end

    # @return [Array<K8s::Resource>]
    def peers_needing_routes
      peers.select do |peer|
        peer.metadata.labels[REGION_LABEL] != this_peer.metadata.labels[REGION_LABEL]
      end
    end

    # @return [Array<String>]
    def currently_routed_addresses
      addresses = []
      output, _ = run_cmd(['ip', 'route'])
      output.lines.each do |line|
        if match = line.strip.match(ROUTE_REGEX)
          addresses << match.captures.first
        end
      end

      addresses
    end

    # @param cmd [Array<String>]
    # @return [Array(String, Process::Status)]
    def run_cmd(cmd)
      Open3.capture2(cmd)
    end

    # @return [String]
    def weave_interface_ip
      return @weave_interface_ip if @weave_interface_ip

      weave = Socket.getifaddrs.find { |ifaddr| ifaddr.name == 'weave' }
      raise "Cannot find weave ip address" if weave.nil? || weave&.addr&.ip_addr.nil?

      @weave_interface_ip = weave.addr.ip_addr
    end
  end
end
