# Copyright (C) 2014 Droonga Project
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License version 2.1 as published by the Free Software Foundation.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

require "json"
require "fileutils"

require "droonga/serf/remote_command"

module Droonga
  module Command
    class SerfEventHandler
      class << self
        def run
          new.run
        end
      end

      def initialize
        @payload = nil
      end

      def run
        command_class = detect_command_class
        return true if command_class.nil?

        serf_name = ENV["SERF_SELF_NAME"]
        command = command_class.new(serf_name, @payload)
        begin
          command.process if command.should_process?
        rescue Exception => exception
          command.log("Exception: #{exception.inspect}, #{exception.message}, #{exception.backtrace.join(", ")}")
          raise exception
        ensure
          output_response(command.response)
        end
        true
      rescue Exception => exception
        #XXX Any exception blocks following serf operations.
        #    To keep it working, I rescue any exception for now.
        begin
          FileUtils.mkdir_p(Path.serf_event_handler_errors)
          File.open(Path.serf_event_handler_error_file, "w") do |file|
            file.write(exception.inspect)
            file.write(exception.backtrace)
          end
        rescue Errno::EACCES => permission_denied_exception
        end
        puts exception.inspect
        puts exception.backtrace
        true
      end

      private
      def detect_command_class
        case ENV["SERF_EVENT"]
        when "user"
          @payload = JSON.parse($stdin.gets)
          detect_command_class_from_custom_event(ENV["SERF_USER_EVENT"])
        when "query"
          @payload = JSON.parse($stdin.gets)
          detect_command_class_from_custom_event(ENV["SERF_QUERY_NAME"])
        when "member-join", "member-leave", "member-update", "member-reap"
          Serf::RemoteCommand::UpdateClusterState
        else
          nil
        end
      end

      def detect_command_class_from_custom_event(event_name)
        case event_name
        when "change_role"
          Serf::RemoteCommand::ChangeRole
        when "report_last_message_timestamp"
          Serf::RemoteCommand::ReportLastMessageTimestamp
        when "accept_messages_newer_than"
          Serf::RemoteCommand::AcceptMessagesNewerThan
        when "join"
          Serf::RemoteCommand::Join
        when "unjoin"
          Serf::RemoteCommand::Unjoin
        when "set_replicas"
          Serf::RemoteCommand::SetReplicas
        when "add_replicas"
          Serf::RemoteCommand::AddReplicas
        when "remove_replicas"
          Serf::RemoteCommand::RemoveReplicas
        else
          nil
        end
      end

      def output_response(response)
        puts JSON.generate(response)
      end
    end
  end
end
