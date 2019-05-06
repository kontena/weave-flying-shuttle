RSpec.describe FlyingShuttle::RouteService do
  let(:subject) { described_class.new(double(:this_peer), []) }

  before(:each) do
    allow(Open3).to receive(:capture2).and_return(['', double(:status, success?: true)])
  end

  describe "#currently_routed_addresses" do
    it "returns addresses" do
      output = <<~OUTPUT
        10.9.145.75 dev weave scope link src 10.40.0.0
        10.32.0.0/12 dev weave proto kernel scope link src 10.40.0.0
        10.9.145.76 dev weave scope link src 10.40.0.0
        172.31.1.1 dev eth0 scope link
      OUTPUT
      allow(subject).to receive(:run_cmd).with('ip route list table 10250').and_return(output, double(:status))
      addresses = subject.currently_routed_addresses
      expect(addresses).to eq(['10.9.145.75', '10.9.145.76'])
    end
  end

  describe "#update_routes" do
    it "adds new routes" do
      addresses = ['10.10.2.2', '192.168.10.10']
      allow(subject).to receive(:addresses_needing_route).and_return(addresses)
      allow(subject).to receive(:currently_routed_addresses).and_return([])
      allow(subject).to receive(:ensure_route) do |addr|
        expect(addresses.include?(addr)).to be_truthy
      end
      expect(subject).not_to receive(:remove_route)
      subject.update_routes
    end

    it "adds only new route" do
      addresses = ['10.10.2.2', '192.168.10.10']
      allow(subject).to receive(:addresses_needing_route).and_return(addresses)
      allow(subject).to receive(:currently_routed_addresses).and_return([addresses.last])
      allow(subject).to receive(:ensure_route).with(addresses.first)
      expect(subject).not_to receive(:remove_route)
      subject.update_routes
    end

    it "does not do anything if all routes exist" do
      addresses = ['10.10.2.2', '192.168.10.10']
      allow(subject).to receive(:addresses_needing_route).and_return(addresses)
      allow(subject).to receive(:currently_routed_addresses).and_return(addresses)
      expect(subject).not_to receive(:ensure_route)
      expect(subject).not_to receive(:remove_route)
      subject.update_routes
    end
  end

  describe "#run_cmd" do
    it "accepts string" do
      cmd = "ls -l"
      expect(Open3).to receive(:capture2).with(cmd)
      subject.run_cmd(cmd)
    end

    it "accepts array" do
      cmd = ["ls", "-l"]
      expect(Open3).to receive(:capture2).with(cmd.join(' '))
      subject.run_cmd(cmd)
    end
  end
end
