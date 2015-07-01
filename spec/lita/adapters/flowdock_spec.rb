require "spec_helper"

describe Lita::Adapters::Flowdock, lita: true do
  subject { described_class.new(robot) }

  let(:robot) { Lita::Robot.new(registry) }
  let(:connector) { instance_double('Lita::Adapters::Flowdock::Connector') }
  let(:api_token) { '46d96d3c91623d4cb6235bb94ac771fb' }
  let(:organization) { 'lita-test' }
  let(:flows) { ['test-flow'] }

  before do
    registry.register_adapter(:flowdock, described_class)
    registry.config.adapters.flowdock.api_token = api_token
    registry.config.adapters.flowdock.organization = organization
    registry.config.adapters.flowdock.flows = flows

    allow(
      described_class::Connector
    ).to receive(:new).with(
      robot,
      api_token,
      organization,
      flows,
      nil,
      {:user => 1, :active => 'true'}
    ).and_return(connector)
    allow(connector).to receive(:run)
    allow(Lita.redis).to receive(:get).with("flows/1234abcd").and_return("dcba4321")
  end

  it "registers with Lita" do
    expect(Lita.adapters[:flowdock]).to eql(described_class)
  end

  describe "#run" do
    it "starts the streaming connection" do
      expect(connector).to receive(:run)
      subject.run
    end

    it "does nothing if the streaming connection is already created" do
      expect(connector).to receive(:run).once

      subject.run
      subject.run
    end
  end

  describe "#send_messages" do
    let(:id) { 8888 }
    let(:room_source) { Lita::FlowdockSource.new(room: '1234abcd', message_id: id) }
    let(:user) { Lita::User.new('987654') }
    let(:user_source) { Lita::Source.new(user: user) }

    it "sends messages to flows" do
      expect(connector).to receive(:send_messages).with(room_source, ['foo'], true)

      subject.run

      subject.send_messages(room_source, ['foo'])
    end

    context "with thread_responses disabled" do
      before do
        registry.config.adapters.flowdock.thread_responses = :disabled
      end

      it "sends messages to flow without the original message id" do
        expect(connector).to receive(:send_messages).with(room_source, ['foo'], false)
        subject.run
        subject.send_messages(room_source, ['foo'])
      end
    end

    context "from a private message source" do
      let(:room_source) { Lita::FlowdockSource.new(room: '1234abcd', message_id: id, private_message: true) }

      it "responds via a private message to flowdock" do
        expect(connector).to receive(:send_messages).with(room_source, ['foo'], false)
        subject.run
        subject.send_messages(room_source, ['foo'])
      end
    end
  end

  describe "#shut_down" do
    before { allow(connector).to receive(:shut_down) }

    it "shuts down the streaming connection" do
      expect(connector).to receive(:shut_down)

      subject.run
      subject.shut_down
    end

    it "does nothing if the streaming connection hasn't been created yet" do
      expect(connector).not_to receive(:shut_down)

      subject.shut_down
    end
  end
end
