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

module Droonga
  module Catalog
    class Slice
      def initialize(dataset, data)
        @dataset = dataset
        @data = data
      end

      def weight
        @data["weight"] || 1
      end

      def label
        @data["label"]
      end

      def boundary
        @data["boundary"]
      end

      def volume
        return nil unless @data.key?("volume")
        @volume ||= Volume.create(@dataset, @data["volume"])
      end

      def replicas
        return nil unless @data.key?("replicas")
        @replicas ||= Replicas.create(@dataset, @data["replicas"])
      end

      def all_nodes
        @all_nodes ||= collect_all_nodes
      end

      private
      def collect_all_nodes
        if volume
          volume.all_nodes
        else
          replicas.all_nodes
        end
      end
    end
  end
end
