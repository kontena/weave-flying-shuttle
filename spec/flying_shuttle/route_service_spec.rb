RSpec.describe FlyingShuttle::RouteService do
  let(:subject) { described_class.new(double(:this_peer), []) }

  describe "#currently_routed_addresses" do
    it "returns addresses" do
      output = <<~OUTPUT
        10.9.145.75 dev weave scope link src 10.40.0.0
        10.32.0.0/12 dev weave proto kernel scope link src 10.40.0.0
        10.9.145.76 dev weave scope link src 10.40.0.0
        172.31.1.1 dev eth0 scope link
      OUTPUT
      allow(subject).to receive(:run_cmd).with(['ip', 'route']).and_return(output, double(:status))
      addresses = subject.currently_routed_addresses
      expect(addresses).to eq(['10.9.145.75', '10.9.145.76'])
    end
  end
end
