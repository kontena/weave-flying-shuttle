# frozen_string_literal: true

require 'k8s-client'

module FlyingShuttle
  module ClientHelper
    def client
      @client ||= create_client
    end

    def create_client
      if ENV['KUBECONFIG']
        K8s::Client.config(K8s::Config.load_file(ENV['KUBECONFIG']))
      elsif File.exist?(File.join(Dir.home, '.kube', 'config'))
        K8s::Client.config(K8s::Config.load_file(File.join(Dir.home, '.kube', 'config')))
      else
        K8s::Client.in_cluster_config
      end
    end
  end
end