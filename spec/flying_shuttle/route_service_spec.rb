RSpec.describe FlyingShuttle::RouteService do
  let(:subject) { described_class.new(double(:this_peer), []) }

  before(:each) do
    allow(Open3).to receive(:capture2).and_return(['', double(:status, success?: true)])
  end

  describe "#currently_routed_peers" do
    it "returns addresses" do
      output = <<~OUTPUT
      Chain PREROUTING (policy ACCEPT)
      target     prot opt source               destination
      DNAT       tcp  --  0.0.0.0/0            10.131.110.70        tcp dpt:10250 /* weave-fs-ip=10.131.110.70 */ to:172.20.96.0:10250
      DNAT       tcp  --  0.0.0.0/0            10.131.111.72        tcp dpt:10250 /* weave-fs-ip=10.131.110.72 */ to:172.20.96.1:10250
      KUBE-SERVICES  all  --  0.0.0.0/0            0.0.0.0/0            /* kubernetes service portals */
      PREROUTING_direct  all  --  0.0.0.0/0            0.0.0.0/0
      PREROUTING_ZONES_SOURCE  all  --  0.0.0.0/0            0.0.0.0/0
      PREROUTING_ZONES  all  --  0.0.0.0/0            0.0.0.0/0

      Chain INPUT (policy ACCEPT)
      target     prot opt source               destination

      Chain OUTPUT (policy ACCEPT)
      target     prot opt source               destination
      DNAT       tcp  --  0.0.0.0/0            10.131.110.70        tcp dpt:10250 /* weave-fs-ip=10.131.110.70 */ to:172.20.96.0:10250
      KUBE-SERVICES  all  --  0.0.0.0/0            0.0.0.0/0            /* kubernetes service portals */
      OUTPUT_direct  all  --  0.0.0.0/0            0.0.0.0/0

      OUTPUT
      allow(subject).to receive(:run_cmd).with('iptables -L -n -t nat').and_return(output, double(:status))
      peers = [
        double(:peer, peer_address: double(:address, address: '10.131.110.70') ),
        double(:peer, peer_address: double(:address, address: '10.131.110.72') )
      ]
      allow(subject).to receive(:peers).and_return(peers)
      addresses = subject.currently_routed_peers.map { |peer| peer.peer_address.address }
      expect(addresses).to eq(['10.131.110.70', '10.131.110.72'])
    end
  end

  describe "#update_routes" do
    let(:peers) do
      [
        double(:peer, name: "p-1", peer_address: double(:address, address: '10.131.110.70') ),
        double(:peer, name: "p-2", peer_address: double(:address, address: '10.131.110.71') ),
        double(:peer, name: "p-3", peer_address: double(:address, address: '10.131.110.72') )
      ]
    end

    let(:subject) do
      described_class.new(double(:this_peer), peers)
    end

    it "adds new routes" do
      allow(subject).to receive(:peers_needing_routes).and_return(peers)
      allow(subject).to receive(:currently_routed_peers).and_return([])
      allow(subject).to receive(:ensure_route) do |peer|
        expect(peers.include?(peer)).to be_truthy
      end
      expect(subject).not_to receive(:remove_route)
      subject.update_routes
    end

    it "adds only new route" do
      allow(subject).to receive(:peers_needing_routes).and_return(peers)
      allow(subject).to receive(:currently_routed_peers).and_return([peers.last])
      expect(subject).to receive(:ensure_route).with(peers[0])
      expect(subject).to receive(:ensure_route).with(peers[1])
      expect(subject).not_to receive(:remove_route)
      subject.update_routes
    end

    it "does not do anything if all routes exist" do
      allow(subject).to receive(:peers_needing_routes).and_return(peers)
      allow(subject).to receive(:currently_routed_peers).and_return(peers)
      expect(subject).not_to receive(:ensure_route)
      expect(subject).not_to receive(:remove_route)
      subject.update_routes
    end
  end

  describe "#run_cmd" do
    it "accepts string" do
      cmd = "ls -l"
      expect(Open3).to receive(:capture2e).with(cmd)
      subject.run_cmd(cmd)
    end

    it "accepts array" do
      cmd = ["ls", "-l"]
      expect(Open3).to receive(:capture2e).with(cmd.join(' '))
      subject.run_cmd(cmd)
    end
  end
end
