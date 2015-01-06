# -*- coding: utf-8 -*-
#
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

require "droonga/slice"

module Droonga
  class Farm
    attr_writer :on_ready
    def initialize(name, catalog, loop, options={})
      @name = name
      @catalog = catalog
      @loop = loop
      @options = options
      @slices = {}
      slices = @catalog.slices(name)
      slices.each do |slice_name, slice_options|
        dataset = @catalog.datasets[slice_options[:dataset]]
        slice = Droonga::Slice.new(dataset,
                                   @loop,
                                   @options.merge(slice_options))
        @slices[slice_name] = slice
      end
    end

    def start
      n_slices = @slices.size
      if n_slices.zero?
        on_ready
        return
      end

      n_ready_slices = 0
      @slices.each_value do |slice|
        slice.on_ready = lambda do
          n_ready_slices += 1
          if n_ready_slices == n_slices
            on_ready
          end
        end
        slice.start
      end
    end

    def stop_gracefully
      n_slices = @slices.size
      if n_slices.zero?
        yield if block_given?
        return
      end

      n_done_slices = 0
      @slices.each_value do |slice|
        slice.stop_gracefully do
          n_done_slices += 1
          if n_done_slices == n_slices
            yield if block_given?
          end
        end
      end
    end

    def stop_immediately
      @slices.each_value do |slice|
        slice.stop_immediately
      end
    end

    def process(slice_name, message)
      @slices[slice_name].process(message)
    end

    private
    def on_ready
      @on_ready.call if @on_ready
    end
  end
end
