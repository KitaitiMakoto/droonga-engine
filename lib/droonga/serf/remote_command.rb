# Copyright (C) 2014-2015 Droonga Project
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

require "droonga/path"
require "droonga/serf"
require "droonga/node_name"
require "droonga/catalog/generator"
require "droonga/catalog/modifier"
require "droonga/catalog/fetcher"
require "droonga/safe_file_writer"
require "droonga/timestamp"
require "droonga/service_installation"

module Droonga
  class Serf
    module RemoteCommand
      class Base
        attr_reader :response

        def initialize(serf_name, params)
          @serf_name = serf_name
          @params    = params
          @response  = {
            "log" => []
          }
          @serf = Serf.new(@serf_name)

          @service_installation = ServiceInstallation.new
          @service_installation.ensure_using_service_base_directory

          log("params = #{params}")
        end

        def process
          # override me!
        end

        def should_process?
          if @params.nil?
            log("anonymous query (to be processed)")
            return true
          end
          unless for_this_cluster?
            log("query for different cluster (mine: #{cluster_id}, to be ignroed)")
            return false
          end

          unless @params.include?("node")
            log("anonymous node query (to be processed)")
            return true
          end
          unless for_me?
            log("query for different node (me: #{@serf_name}, to be ignored)")
            return false
          end

          log("query for this node (to be processed)")
          true
        end

        def log(message)
          @response["log"] << message
        end

        private
        def node
          @node ||= NodeName.parse(@serf_name)
        end

        def host
          node.host
        end

        def cluster_id
          @serf.cluster_id
        end

        def target_cluster
          return nil unless @params
          @params["cluster_id"]
        end

        def target_node
          return nil unless @params
          @target_node ||= NodeName.parse(@params["node"] || "")
        rescue ArgumentError
          nil
        end

        def for_this_cluster?
          target_cluster.nil? or target_cluster == cluster_id
        end

        def for_me?
          target_node == node
        end

        def catalog
          @catalog ||= JSON.parse(Path.catalog.read)
        end
      end

      class ChangeRole < Base
        def process
          log("old role: #{@serf.role}")
          @serf.role = @params["role"]
          log("new role: #{@serf.role}")
        end
      end

      class ReportLastMessageTimestamp < Base
        def process
          timestamp = Timestamp.last_message_timestamp
          if timestamp
            @response["timestamp"] = Timestamp.stringify(timestamp)
          else
            @response["timestamp"] = nil
          end
        end
      end

      class AcceptMessagesNewerThan < Base
        def process
          log("old timestamp: #{@serf.accept_messages_newer_than_timestamp}")
          @serf.accept_messages_newer_than(@params["timestamp"])
          log("new timestamp: #{@serf.accept_messages_newer_than_timestamp}")
        end
      end

      class CrossNodeCommandBase < Base
        private
        def source_node
          return nil unless @params
          @source_node ||= NodeName.parse(@params["source"] || "")
        rescue ArgumentError
          nil
        end

        def dataset
          @dataset ||= @params["dataset"]
        end

        def source_host
          source_node.host
        end

        def port
          @port ||= @params["port"] || source_node.port
        end

        def tag
          @tag ||= @params["tag"] || source_node.tag
        end
      end

      class Join < CrossNodeCommandBase
        def process
          log("type = #{type}")
          case type
          when "replica"
            join_as_replica
          end
        end

        private
        def type
          @params["type"]
        end

        def joining_node
          target_node
        end

        def joining_host
          joining_node.host
        end

        def valid_params?
          not dataset.nil? and
            not source_node.nil? and
            not joining_node.nil?
        end

        def join_as_replica
          return unless valid_params?

          log("source_node = #{source_node}")

          @catalog = fetch_catalog

          @other_hosts = replica_hosts
          log("other_hosts = #{@other_hosts}")
          return if @other_hosts.empty?

          join_to_cluster
        end

        def replica_hosts
          generator = Catalog::Generator.new
          generator.load(catalog)
          dataset = generator.dataset_for_host(source_host) ||
                      generator.dataset_for_host(host)
          return [] unless dataset
          dataset.replicas.hosts
        end

        def fetch_catalog
          fetcher = Catalog::Fetcher.new(:host          => source_host,
                                         :port          => port,
                                         :tag           => tag,
                                         :receiver_host => host)
          fetcher.fetch(:dataset => dataset)
        end

        def join_to_cluster
          log("joining to the cluster")
          @serf.join(*@other_hosts)

          log("update catalog.json from fetched catalog")
          Catalog::Modifier.new(catalog).modify do |modifier, file|
            modifier.datasets[dataset].replicas.hosts += [joining_host]
            modifier.datasets[dataset].replicas.hosts.uniq!
            @service_installation.ensure_correct_file_permission(file)
          end
          log("done")
        end
      end

      class ModifyReplicasBase < Base
        private
        def dataset
          @params["dataset"]
        end

        def hosts
          @hosts ||= prepare_hosts
        end

        def prepare_hosts
          hosts = @params["hosts"]
          return nil unless hosts
          hosts = [hosts] if hosts.is_a?(String)
          hosts
        end
      end

      class SetReplicas < ModifyReplicasBase
        def process
          return if dataset.nil? or hosts.nil?

          log("new replicas: #{hosts.join(",")}")

          log("joining to the cluster")
          @serf.join(*hosts)

          log("setting replicas to the cluster")
          Catalog::Modifier.new(catalog).modify do |modifier, file|
            modifier.datasets[dataset].replicas.hosts = hosts
            @service_installation.ensure_correct_file_permission(file)
          end
          log("done")
        end
      end

      class AddReplicas < ModifyReplicasBase
        def process
          return if dataset.nil? or hosts.nil?

          added_hosts = hosts - [host]
          log("adding replicas: #{added_hosts.join(",")}")
          return if added_hosts.empty?

          log("joining to the cluster")
          @serf.join(*added_hosts)

          log("adding replicas to the cluster")
          Catalog::Modifier.new(catalog).modify do |modifier, file|
            modifier.datasets[dataset].replicas.hosts += added_hosts
            modifier.datasets[dataset].replicas.hosts.uniq!
            @service_installation.ensure_correct_file_permission(file)
          end
          log("done")
        end
      end

      class RemoveReplicas < ModifyReplicasBase
        def process
          return if dataset.nil? or hosts.nil?

          log("removing replicas: #{hosts.join(",")}")

          log("removing replicas from the cluster")
          Catalog::Modifier.new(catalog).modify do |modifier, file|
            modifier.datasets[dataset].replicas.hosts -= hosts
            @service_installation.ensure_correct_file_permission(file)
          end
          log("done")
        end
      end

      class Unjoin < ModifyReplicasBase
        def process
          return if dataset.nil? or hosts.nil?

          log("unjoining replicas: #{hosts.join(",")}")

          log("unjoining from the cluster")
          Catalog::Modifier.new(catalog).modify do |modifier, file|
            if unjoining_node?
              modifier.datasets[dataset].replicas.hosts = hosts
            else
              modifier.datasets[dataset].replicas.hosts -= hosts
            end
            @service_installation.ensure_correct_file_permission(file)
          end
          log("done")
        end

        private
        def unjoining_node?
          hosts.include?(host)
        end
      end

      class UpdateClusterState < Base
        def process
          log("updating cluster state")
          @serf.update_cluster_state
          log("done")
        end
      end
    end
  end
end
