require 'lita/adapters/flowdock/users_creator'
require 'lita/source/flowdock_source'

module Lita
  module Adapters
    class Flowdock < Adapter
      class MessageHandler
        def initialize(robot, robot_id, data, flowdock_client)
          @robot = robot
          @robot_id = robot_id
          @data = data
          @flowdock_client = flowdock_client
          @type = data['event']
        end

        def handle
          case type
          when "comment"
            handle_message
          when "message"
            handle_message
          when "activity.user"
            handle_user_activity
          when "action"
            handle_action
          else
            handle_unknown
          end
        end

        private
          attr_reader :robot, :robot_id, :data, :type, :flowdock_client

          def body
            content = data['content'] || ""
            return content.is_a?(Hash) ? content['text'] : content
          end

          def tags
            data['tags']
          end

          def parent_id
            influx_tag = tags.select { |t| t =~ /influx:(\d+)/ }.first
            influx_tag.split(':')[-1].to_i
          end

          def message_id
            type == 'comment' ? parent_id : id
          end

          def dispatch_message(user)
            source = FlowdockSource.new(
              user: user,
              room: flow,
              message_id: message_id,
              private_message: flow.nil?
            )

            tmp_body = body.dup
            if flow.nil? && tmp_body !~ /#{robot.mention_name}/
              tmp_body = "#{robot.mention_name} #{tmp_body}"
            end

            message = Message.new(robot, tmp_body, source)
            robot.receive(message)
          end

          def flow
            data['flow']
          end

          def id
            data['id']
          end

          def from_self?(user)
            user.id.to_i == robot_id
          end

          def log
            Lita.logger
          end

          def handle_message
            log.debug("Handling message: #{data.inspect}")
            user = User.find_by_id(data['user']) || create_user(data['user'])
            log.debug("User found: #{user.inspect}")
            return if from_self?(user)
            dispatch_message(user)
          end

          def handle_user_activity
            log.debug("Handling user activity: #{data.inspect}")
          end

          def handle_action
            log.debug("Handling action: #{data.inspect}")
            if %w{add_people join}.include?(data['content']['type'])
              UsersCreator.create_users(flowdock_client.get('/users'))
            end
          end

          def handle_unknown
            log.debug("Unknown message type: #{data.inspect}")
          end

          def create_user(id)
            user = flowdock_client.get("/user/#{id}")
            UsersCreator.create_user(user)
          end
      end
    end
  end
end
