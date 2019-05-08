require "k8s-client"
require "forwardable"

module FlyingShuttle
  class Peer
    extend Forwardable

    REGION_LABEL = FlyingShuttle::REGION_LABEL

    attr_reader :node

    def_delegators :@node, :status, :metadata

    # @param node [K8s::Resource]
    def initialize(node)
      @node = node
    end

    # @return [String]
    def name
      node.metadata.name
    end

    # @return [K8s::Resource]
    def peer_address
      address_for('InternalIP') || address_for('ExternalIP')
    end

    # @param type [String]
    # @return [K8s::Resource]
    def address_for(type)
      node.status.addresses.find { |addr| addr.type == type }
    end

    # @return [String]
    def region
      node.metadata.labels[REGION_LABEL] || 'default'
    end

    # @param ip [String]
    def weave_interface_ip=(ip)
      @weave_interface_ip = ip
    end

    # @return [String, NilClass]
    def weave_interface_ip
      return @weave_interface_ip if @weave_interface_ip

      node.metadata.annotations[:'weave.kontena.io/bridge-ip']
    end
  end
end
