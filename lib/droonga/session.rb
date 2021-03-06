# Copyright (C) 2013-2015 Droonga Project
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

require "coolio"

require "droonga/loggable"

module Droonga
  class Session
    include Loggable

    def initialize(id, dispatcher, collector_runner, tasks, inputs)
      @id = id
      @dispatcher = dispatcher
      @collector_runner = collector_runner
      @tasks = tasks
      @n_dones = 0
      @inputs = inputs
      logger.trace("initialized", :tasks => tasks, :inputs => inputs)
    end

    def done?
      @n_dones == @tasks.size
    end

    #TODO: We don't have to wait results if no collection step is
    #      in the list of tasks, because:
    #
    #       * Currently the "super step" mecahnism is not
    #         implemented yet.
    #       * So, results won't be used by other handlers directly.
    #         Results will be used only for the "response" for the
    #         sender.
    #       * So, if there is no collection step, no-one requires
    #         results and there is no need to wait for results.
    #
    #      However, in the future after the "super step" mechanism
    #      is introduced, results can be used by other handlers
    #      even if there is no collection step.
    #      Then we must update this logic.
    def need_result?
      @tasks.any? do |task|
        @collector_runner.collectable?("task" => task)
      end
    end

    def start
      tasks = @inputs[nil] || []
      logger.trace("start: no task!") if tasks.empty?
      tasks.each do |task|
        local_message = {
          "id"   => @id,
          "task" => task,
        }
        logger.trace("start: dispatching local message", :message => local_message)
        @dispatcher.process_local_message(local_message)
        @n_dones += 1
      end
    end

    def finish
      @timeout_timer.detach if @timeout_timer
      @timeout_timer = nil
    end

    def receive(name, value)
      tasks = @inputs[name]
      logger.trace("receive: process response",
                   :name => name, :value => value, :task => tasks)
      unless tasks
        #TODO: result arrived before its query
        return
      end
      tasks.each do |task|
        task["n_of_inputs"] += 1
        step = task["step"]
        command = step["type"]
        n_of_expects = step["n_of_expects"]
        message = {
          "task"=>task,
          "name"=>name,
          "value"=>value
        }
        @collector_runner.collect(message)
        return if task["n_of_inputs"] < n_of_expects
        #the task is done
        result = task["values"]
        post = step["post"]
        if post
          # XXX: It is just a workaround.
          # Remove me when super step is introduced.
          if result["errors"]
            reply_body = result
          elsif command == "search_gather"
            reply_body = result
          else
            reply_body = result["result"]
          end
          @dispatcher.reply("body" => reply_body)
        end
        send_to_descendantas(step["descendants"], result)
        @n_dones += 1
      end
    end

    def set_timeout(loop, timeout, &block)
      @timeout_timer = Coolio::TimerWatcher.new(timeout)
      @timeout_timer.on_timer do
        @timeout_timer.detach
        @timeout_timer = nil
        report_timeout_error
        yield
      end
      loop.attach(@timeout_timer)
    end

    private
    def send_to_descendantas(descendantas, result)
      descendantas.each do |name, routes|
        message = {
          "id" => @id,
          "input" => name,
          "value" => result[name]
        }
        routes.each do |route|
          @dispatcher.dispatch(message, route)
        end
      end
    end

    def report_timeout_error
      #TODO: implement me!
    end

    def log_tag
      "session"
    end
  end
end
