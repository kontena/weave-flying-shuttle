RSpec.describe FlyingShuttle::PeerService do
  let(:weave_client) { double(:weave_client) }
  let(:this_peer) do
    node = K8s::Resource.new(
      metadata: {
        labels: {
          'failure-domain.beta.kubernetes.io/region' => 'eu-west-1'
        }
      }
    )
    FlyingShuttle::Peer.new(node)
  end

  before(:each) do
    allow(subject).to receive(:weave_client).and_return(weave_client)
  end

  def build_labeled_node(name, region, external_ip)
    node = K8s::Resource.new(kind: 'Node', apiVersion: 'v1',
      metadata: {
        name: name,
        labels: {
          'failure-domain.beta.kubernetes.io/region' => region,
          'node-address.kontena.io/external-ip' => external_ip
        }
      },
      status: {
        addresses: [
          { type: 'InternalIP', address: external_ip.sub('192.168', '10.10') }
        ]
      }
    )
    FlyingShuttle::Peer.new(node)
  end

  describe '#update_peers' do
    before(:each) do
      allow(subject).to receive(:set_peers)
    end

    it 'calculates peers correctly' do
      peers = [
        build_labeled_node('host-02', 'eu-west-1', '192.168.100.11'),
        build_labeled_node('host-03', 'eu-central-1', '192.168.100.10')
      ]

      expect(subject).to receive(:set_peers).with([
        '10.10.100.11', '192.168.100.10'
      ].sort)
      subject.update_peers(this_peer, peers, [])
    end
  end

  describe '#set_peers' do
    it 'instructs weave about new peers' do
      peers = ['a', 'b']
      response = double(:response, status: 200)
      expect(weave_client).to receive(:post).with(
        hash_including(
          path: '/connect',
          body: 'peer=a&peer=b&replace=true'
        )
      ).and_return(response)
      expect(subject.set_peers(peers)).to be_truthy
    end

    it 'returns false if peers cannot be set' do
      peers = ['a', 'b']
      response = double(:response, status: 400, body: '')
      expect(weave_client).to receive(:post).with(
        hash_including(
          path: '/connect',
          body: 'peer=a&peer=b&replace=true'
        )
      ).and_return(response)
      expect(subject.set_peers(peers)).to be_falsey
    end
  end
end
