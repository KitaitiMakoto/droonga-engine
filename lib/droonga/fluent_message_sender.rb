# -*- coding: utf-8 -*-
#
# Copyright (C) 2013 Droonga Project
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

require "fileutils"
require "thread"

require "coolio"

require "droonga/message-pack-packer"

require "droonga/loggable"
require "droonga/buffered_tcp_socket"

module Droonga
  class FluentMessageSender
    include Loggable

    def initialize(loop, host, port, options={})
      @loop = loop
      @host = host
      @port = port
      @socket = nil
      @packer = MessagePackPacker.new
      @buffering = options[:buffering]
    end

    def start
      logger.trace("start: start")
      logger.trace("start: done")
    end

    def shutdown
      logger.trace("shutdown: start")
      shutdown_socket
      logger.trace("shutdown: done")
    end

    def send(tag, data)
      logger.trace("send: start")
      packed_fluent_message = create_packed_fluent_message(tag, data)
      unless connected?
        logger.trace("send: reconnect")
        connect
      end
      @socket.write(packed_fluent_message)
      logger.trace("send: done")
    end

    def resume
      unless connected?
        logger.trace("resume: reconnect to #{target_node}")
        connect
      end
    end

    private
    def connected?
      not @socket.nil?
    end

    def connect
      logger.trace("connect: start")

      if @buffering
        data_directory = Path.accidental_buffer + "#{target_node}"
        FileUtils.mkdir_p(data_directory.to_s)
        @socket = BufferedTCPSocket.connect(@host, @port, data_directory)
        @socket.resume
      else
        @socket = Coolio::TCPSocket.connect(@host, @port)
      end
      @socket.on_write_complete do
        logger.trace("write completed")
      end
      @socket.on_connect do
        logger.trace("connected")
      end
      @socket.on_connect_failed do
        logger.error("failed to connect")
        @socket = nil
      end
      @socket.on_close do
        logger.trace("connection is closed by someone")
        @socket = nil
      end
      @loop.attach(@socket)
      # logger.trace("connect: new socket watcher attached",
      #              :watcher => @socket,
      #              :host => @host,
      #              :port => @port)

      logger.trace("connect: done")
    end

    def shutdown_socket
      return unless connected?
      unless @socket.closed?
        # logger.trace("shutdown_socket: socket watcher detaching",
        #              :watcher => @socket)
        @socket.close
        logger.trace("shutdown_socket: socket watcher detached")
      end
    end

    def create_packed_fluent_message(tag, data)
      fluent_message = [tag, Time.now.to_i, data]
      @packer.pack(fluent_message)
      packed_fluent_message = @packer.to_s
      @packer.clear
      packed_fluent_message
    end

    def target_node
      "#{@host}:#{@port}"
    end

    def log_tag
      "[#{Process.ppid}] fluent-message-sender: #{target_node}"
    end
  end
end
