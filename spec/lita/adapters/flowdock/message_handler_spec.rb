require 'spec_helper'

describe Lita::Adapters::Flowdock::MessageHandler, lita: true do
  subject { described_class.new(robot, robot_id, data, fd_client) }

  let(:fd_client) { instance_double('Flowdock::Client') }
  let(:robot) {
    instance_double('Lita::Robot', name: 'Lita', mention_name: 'lita')
  }
  let(:robot_id) { 123456 }
  let(:robot_fd_user) {
    { 'id' => robot_id, 'name' => 'Lita', 'nick' => 'lita' }
  }
  let(:test_user_id) { 3 }
  let(:test_fd_user) {
    { 'id' => test_user_id, 'name' => 'Test User3', 'nick' => 'user3' }
  }
  let(:test_flow) { 'testing:lita-test' }

  before do
    allow(fd_client).to receive(:get).with(
      "/user/#{robot_id}").and_return(robot_fd_user)
    allow(fd_client).to receive(:get).with(
      "/user/#{test_user_id}").and_return(test_fd_user)
    allow(robot).to receive(:alias)
  end

  describe "#handle" do
    context "a normal message" do
      let(:data) do
        {
          'content' => 'Hello World!',
          'event'   => 'message',
          'flow'    => test_flow,
          'user'    => test_user_id
        }
      end
      let(:message) { instance_double('Lita::Message', command!: false) }
      let(:source) { instance_double('Lita::Source', private_message?: false) }
      let(:user) { instance_double('Lita::User', id: test_user_id) }

      before do
        allow(Lita::User).to receive(:find_by_id).and_return(user)
        allow(Lita::Source).to receive(:new).with(
          user: user,
          room: test_flow
        ).and_return(source)
        allow(Lita::Message).to receive(:new).with(
          robot, 'Hello World!', source).and_return(message)
        allow(robot).to receive(:receive).with(message)
      end

      it "dispatches the message to lita" do
        expect(robot).to receive(:receive).with(message)

        subject.handle
      end

      context "when the message is nil" do
        let(:data) do
          {
            'event'   => 'message',
            'flow'    => test_flow,
            'user'    => test_user_id,
          }
        end

        it "dispatches an empty message to Lita" do
          expect(Lita::Message).to receive(:new).with(
            robot,
            "",
            source
          ).and_return(message)

          subject.handle
        end
      end
    end

    context "a message with an unsupported type" do
      let(:data) do
        {
          'content' => 'this type is not supported',
          'event'   => 'unsupported',
          'flow'    => test_flow,
          'user'    => test_user_id
        }
      end

      it "does not dispatch the message to Lita" do
        expect(robot).not_to receive(:receive)

        subject.handle
      end
    end

    context "a message from the robot itself" do
      let(:data) do
        {
          'content' => 'reply from lita',
          'event'   => 'message',
          'flow'    => test_flow,
          'user'    => robot_id
        }
      end
      let(:robot_user) { instance_double('Lita::User', id: robot_id) }

      before do
        allow(Lita::User).to receive(:find_by_id).and_return(robot_user)
      end

      it "does not dispatch the message to Lita" do
        expect(robot).not_to receive(:receive)

        subject.handle
      end
    end

    context "a message from an unknown user" do
      let(:new_user_id) { 4 }
      let(:new_fd_user) {
        { 'id' => new_user_id, 'name' => 'Test User4', 'nick' => 'user4' }
      }


      let(:data) do
        {
          'content' => "hi i'm new here",
          'event'   => 'message',
          'flow'    => test_flow,
          'user'    => new_user_id
        }
      end
      let(:user4) { instance_double(
        'Lita::User', id: 4, name: 'Test User4', mention_name: 'user4'
      )}

      before do
        allow(Lita::User).to receive(:find_by_id).with(
          new_user_id).and_return(nil)
        allow(fd_client).to receive(:get).with(
          "/user/#{new_user_id}").and_return(new_fd_user)
        allow(robot).to receive(:receive)
      end

      it "creates the new user" do
        expect(Lita::User).to receive(:create).with(
          new_user_id,
          {
            "name"  => 'Test User4',
            "mention_name"  => 'user4'
          }
        ).and_return(user4)

        subject.handle
      end
    end

    context "receives a user activity message" do
      let(:data) do
        {
          'content' => { 'last_activity' => 1317715364447 },
          'event'   => 'activity.user',
          'flow'    => test_flow,
          'user'    => test_user_id
        }
      end

      it "doesn't dispatch a message to Lita" do
        expect(robot).not_to receive(:receive)

        subject.handle
      end
    end

    context "receives an action message" do
      context "for adding a user to the flow" do
        let(:data) do
          {
            'content' => {'type' => 'add_people', 'description' => 'user5'},
            'event' => 'action',
            'flow'  => test_flow,
            'user'  => test_user_id
          }
        end
        let(:added_user_id) { 5 }
        let(:added_user_fd) do
          { 'id' => 5, 'name' => 'Test User5', 'nick' => 'user5' }
        end

        before do
          allow(Lita::User).to receive(:find_by_id).with(5).and_return(nil)
          allow(fd_client).to receive(:get).with(
            "/user/#{added_user_id}").and_return(added_user_fd)
          allow(robot).to receive(:receive)
          allow(fd_client).to receive(:get).with(
            '/users').and_return([added_user_fd])
        end

        it "creates the new user" do
          expect(Lita::User).to receive(:create).with(
            5, { 'name' => 'Test User5', 'mention_name' => 'user5' })
          subject.handle
        end
      end

      context "for a user joining the flow" do
        let(:joining_user_id) { 6 }
        let(:joining_user_fd) do
          { 'id' => 6, 'name' => 'Test User6', 'nick' => 'user6' }
        end
        let(:data) do
          {
            'content' => {'type' => 'join', 'description' => 'tbd'},
            'event'   => 'action',
            'flow'    => test_flow,
            'user'    => joining_user_id
          }
        end

        before do
          allow(Lita::User).to receive(:find_by_id).with(6).and_return(nil)
          allow(fd_client).to receive(:get).with(
            "/user/#{joining_user_id}").and_return(joining_user_fd)
          allow(robot).to receive(:receive)
          allow(fd_client).to receive(:get).with(
            '/users').and_return([joining_user_fd])
        end

        it "creates the new user" do
          expect(Lita::User).to receive(:create).with(
            6, { 'name' => 'Test User6', 'mention_name' => 'user6' })
          subject.handle
        end
      end

      context "for an unsupported action message type" do
        let(:data) do
          {
            'content' => {
              'type' => 'add_rss_feed',
              'description' => 'http://example.com/rss'
            },
            'event'   => 'action',
            'flow'    => test_flow,
            'user'    => test_user_id
          }
        end

        it "doesn't dispatch the message to Lita" do
          expect(robot).not_to receive(:receive)
          subject.handle
        end
      end
    end
  end
end
