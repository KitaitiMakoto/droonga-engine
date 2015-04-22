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

module Droonga
  module ProcessControlProtocol
    module Messages
      STOP_GRACEFUL    = "stop-graceful\n"
      STOP_IMMEDIATELY = "stop-immediately\n"
      REFRESH_SELF_REFERENCE = "refresh-self-reference\n"

      READY  = "ready\n"
      FINISH = "finish\n"
    end
  end
end
