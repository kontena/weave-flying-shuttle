# frozen_string_literal: true

require 'socket'
require 'open3'
require 'ipaddr'
require_relative 'mixins/client_helper'
require_relative 'mixins/logging'

module FlyingShuttle
  class RouteService
    include Logging

    REGION_LABEL = FlyingShuttle::REGION_LABEL
    ROUTE_REGEX = /(\d+\.\d+\.\d+\.\d+) dev weave scope link src \d+\.\d+\.\d+\.\d+/
    SIOCGIFADDR = 0x8915

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
      logger.info "addresses needing route: #{addresses.join(',')}"
      loosen_rp_filter
      ensure_ip_rule
      masquerade_marked
      current_addresses = currently_routed_addresses
      (addresses - current_addresses).each do |address|
        ensure_route(address)
      end
      (current_addresses - addresses).each do |address|
        remove_route(address)
      end

      (addresses - current_addresses)
    end

    def loosen_rp_filter
      run_cmd('echo 2 > /proc/sys/net/ipv4/conf/all/rp_filter')
    end

    def ensure_ip_rule
      output, _ = run_cmd('ip rule list lookup 10250')
      if output.strip.empty?
        run_cmd('ip rule add fwmark 10250 table 10250')
        run_cmd('ip route flush cache')
      end
    end

    def masquerade_marked
      iptables_params = '-t nat -m mark --mark 10250 -o weave -j MASQUERADE'
      _, status = run_cmd('iptables -C POSTROUTING ' + iptables_params)
      unless status.success?
        run_cmd('iptables -I POSTROUTING 1 ' + iptables_params)
      end
    end

    # @param address [String]
    # @return [Boolean]
    def ensure_route(address)
      iptables_params = ['OUTPUT -t mangle -p tcp -d', address, '--dport 10250 -j MARK --set-mark 10250']
      _, status = run_cmd(['iptables', '-C'] + iptables_params)
      run_cmd(['iptables', '-A'] + iptables_params) unless status.success?

      output, _ = run_cmd(['ip route get', address, 'mark 10250'])
      return true if output.include?("#{address} dev weave table 10250 src")

      logger.info "adding route for #{address} via weave #{weave_interface_ip}"
      _, status = run_cmd(['ip route add table 10250', address, 'dev weave src', weave_interface_ip])
      status.success?
    end

    # @param address [String]
    # @return [Boolean]
    def remove_route(address)
      logger.info "removing route for #{address} via weave #{weave_interface_ip}"
      output, _ = run_cmd('ip route')
      return true unless output.include?("#{address} dev weave scope link src")

      _, status = run_cmd(['ip route del', address, 'dev weave src', weave_interface_ip])
      status.success?
    end

    # @return [Array<String>]
    def addresses_needing_route
      needs_route = []
      peers_needing_routes.each do |peer|
        addresses = peer.status.addresses
        address = addresses.find { |addr| addr.type == 'InternalIP' } || addresses.find { |addr| addr.type == 'ExternalIP' }
        if address && addr = address.address
          needs_route << addr
        end
      end
      needs_route
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
      output, _ = run_cmd('ip route list table 10250')
      output.lines.each do |line|
        if match = line.strip.match(ROUTE_REGEX)
          addresses << match.captures.first
        end
      end

      addresses
    end

    # @param cmd [Array<String>, String]
    # @return [Array(String, Process::Status)]
    def run_cmd(cmd)
      cmd = cmd.is_a?(Array) ? cmd.join(' ') : cmd
      logger.info "running command: #{cmd}"
      Open3.capture2(cmd)
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
