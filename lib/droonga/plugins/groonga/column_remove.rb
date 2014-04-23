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
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

require "groonga/command/column-remove"

require "droonga/plugin"
require "droonga/plugins/groonga/generic_command"

module Droonga
  module Plugins
    module Groonga
      module ColumnRemove
        class Command < GenericCommand
          def process_request(request)
            command_class = ::Groonga::Command.find("column_remove")
            @command = command_class.new("column_remove", request)

            table_name = @command["table"]
            if table_name.nil? or @context[table_name].nil?
              message = "table doesn't exist: <#{table_name.to_s}>"
              raise CommandError.new(:status => Status::INVALID_ARGUMENT,
                                     :message => message,
                                     :result => false)
            end

            column_name = @command["name"]
            if column_name.nil? or @context[table_name].column(column_name).nil?
              message = "column doesn't exist: <#{column_name.to_s}>"
              raise CommandError.new(:status => Status::INVALID_ARGUMENT,
                                     :message => message,
                                     :result => false)
            end

            remove_column(table_name, column_name)
          end

          private
          def remove_column(table_name, column_name)
            ::Groonga::Schema.define(:context => @context) do |schema|
              schema.change_table(table_name) do |table|
                table.remove_column(column_name)
              end
            end
            true
          end
        end

        class Handler < Droonga::Handler
          action.synchronous = true

          def handle(message)
            command = Command.new(@context)
            command.execute(message.request)
          end
        end

        Groonga.define_single_step do |step|
          step.name = "column_remove"
          step.write = true
          step.handler = Handler
          step.collector = Collectors::Or
        end
      end
    end
  end
end
