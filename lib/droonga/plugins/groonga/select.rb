# Copyright (C) 2013-2014 Droonga Project
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

require "droonga/plugin"

module Droonga
  module Plugins
    module Groonga
      module Select
        DRILLDOWN_RESULT_PREFIX = "drilldown_result_"

        class RequestConverter
          def convert(select_request)
            @table = select_request["table"]
            @result_name = @table + "_result"

            output_columns = select_request["output_columns"] || ""
            attributes = output_columns.split(/, */)
            offset = (select_request["offset"] || "0").to_i
            limit = (select_request["limit"] || "10").to_i

            search_request = {
              "queries" => {
                @result_name => {
                  "source" => @table,
                  "output" => {
                    "elements"   => [
                      "startTime",
                      "elapsedTime",
                      "count",
                      "attributes",
                      "records",
                    ],
                    "attributes" => attributes,
                    "offset" => offset,
                    "limit" => limit,
                  },
                }
              }
            }

            condition = convert_condition(select_request)
            if condition
              search_request["queries"][@result_name]["condition"] = condition
            end

            drilldown_queries = convert_drilldown(select_request)
            if drilldown_queries
              search_request["queries"].merge!(drilldown_queries)
            end

            search_request
          end

          def convert_condition(select_request)
            match_columns = select_request["match_columns"]
            match_to = match_columns ? match_columns.split(/ *\|\| */) : []
            query = select_request["query"]
            filter = select_request["filter"]

            conditions = []
            if query
              conditions << {
                "query"  => query,
                "matchTo"=> match_to,
                "defaultOperator"=> "&&",
                "allowPragma"=> false,
                "allowColumn"=> true,
              }
            end

            if filter
              conditions << filter
            end

            condition = nil

            case conditions.size
            when 1
              condition = conditions.first
            when 2
              condition = ["&&"] + conditions
            end

            condition
          end

          def convert_drilldown(select_request)
            drilldown_keys = select_request["drilldown"]
            return nil if drilldown_keys.nil? or drilldown_keys.empty?

            drilldown_keys = drilldown_keys.split(",")

            sort_keys = (select_request["drilldown_sortby"] || "").split(",")
            columns   = (select_request["drilldown_output_columns"] || "").split(",")
            offset    = (select_request["drilldown_offset"] || "0").to_i
            limit     = (select_request["drilldown_limit"] || "10").to_i

            queries = {}
            drilldown_keys.each_with_index do |key, index|
              query = {
                "source" => @result_name,
                "groupBy" => key,
                "output" => {
                  "elements"   => [
                    "count",
                    "attributes",
                    "records",
                  ],
                  "attributes" => columns,
                  "limit" => limit,
                },
              }

              if sort_keys.empty?
                query["output"]["offset"] = offset
              else
                query["sortBy"] = {
                  "keys"   => sort_keys,
                  "offset" => offset,
                  "limit"  => limit,
                }
              end

              queries["#{DRILLDOWN_RESULT_PREFIX}#{key}"] = query
            end
            queries
          end
        end

        class ResponseConverter
          def convert(search_response)
            @drilldown_results = []
            search_response.each do |key, value|
              if key.start_with?(DRILLDOWN_RESULT_PREFIX)
                key = key[DRILLDOWN_RESULT_PREFIX.size..-1]
                convert_drilldown_result(key, value)
              else
                convert_main_result(value)
              end
            end

            select_results = [@header, [@body]]
            unless @drilldown_results.empty?
              select_results.last += @drilldown_results
            end

            select_results
          end

          private
          def convert_main_result(result)
            status_code = 0
            start_time = result["startTime"]
            start_time_in_unix_time = if start_time
                                        Time.parse(start_time).to_f
                                      else
                                        Time.now.to_f
                                      end
            elapsed_time = result["elapsedTime"] || 0
            @header = [status_code, start_time_in_unix_time, elapsed_time]
            @body = convert_search_result(result)
          end

          def convert_drilldown_result(key, result)
            @drilldown_results << convert_search_result(result)
          end

          def convert_search_result(result)
            count      = result["count"]
            attributes = convert_attributes(result["attributes"])
            records    = result["records"]
            if records.empty?
              [[count], attributes]
            else
              [[count], attributes, records]
            end
          end

          def convert_attributes(attributes)
            attributes = attributes || []
            attributes.collect do |attribute|
              name = attribute["name"]
              type = attribute["type"]
              [name, type]
            end
          end
        end

        class Adapter < Droonga::Adapter
          input_message.pattern = ["type", :equal, "select"]

          def adapt_input(input_message)
            converter = RequestConverter.new
            select_request = input_message.body
            search_request = converter.convert(select_request)
            input_message.type = "search"
            input_message.body = search_request
          end

          def adapt_output(output_message)
            converter = ResponseConverter.new
            search_response = output_message.body
            select_response = converter.convert(search_response)
            output_message.body = select_response
          end
        end
      end
    end
  end
end
