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

class DeleteTest < GroongaHandlerTest
  def create_handler
    Droonga::Plugins::Groonga::Delete::Handler.new(:name      => "droonga",
                                                   :context   => @handler.context,
                                                   :messenger => @messenger,
                                                   :loop      => @loop)
  end

  def test_success
    Groonga::Schema.define do |schema|
      schema.create_table("Books", :type => :hash)
    end
    Groonga::Context.default["Books"].add("sample")
    message = {
      "table" => "Books",
      "key"   => "sample",
    }
    response = process(:delete, message)
    assert_equal(
      [NORMALIZED_HEADER_SUCCESS, true],
      [normalize_header(response.first), response.last]
    )
  end

  def test_unknown_table
    message = {
      "table" => "Unknown",
    }
    response = process(:delete, message)
    assert_equal(
      [NORMALIZED_HEADER_INVALID_ARGUMENT, false],
      [normalize_header(response.first), response.last]
    )
  end

  def test_no_identifier
    Groonga::Schema.define do |schema|
      schema.create_table("Books", :type => :hash)
    end
    message = {
      "table" => "Books",
    }
    response = process(:delete, message)
    assert_equal(
      [NORMALIZED_HEADER_INVALID_ARGUMENT, false],
      [normalize_header(response.first), response.last]
    )
  end

  data(:key_and_id => { "key" => "key", "id" => "1" },
       :id_and_filter => { "id" => "1", "filter" => "filter" },
       :key_and_filter => { "key" => "key", "filter" => "filter" })
  def test_duplicated_identifier(data)
    Groonga::Schema.define do |schema|
      schema.create_table("Books", :type => :hash)
    end
    message = {
      "table" => "Books",
    }.merge(data)
    response = process(:delete, message)
    assert_equal(
      [NORMALIZED_HEADER_INVALID_ARGUMENT, false],
      [normalize_header(response.first), response.last]
    )
  end

  class DeleteKeyTest < self
    def test_string
      setup_table_with_key_type("ShortText")
      table.add("sample")
      process(:delete,
              {"table" => "Books", "key" => "sample"})
      assert_equal(<<-DUMP, dump)
table_create Books TABLE_HASH_KEY ShortText
      DUMP
    end

    data do
      data_set = {}
      [
        "Int8",
        "UInt8",
        "Int16",
        "UInt16",
        "Int32",
        "UInt32",
        "Int64",
        "UInt64",
      ].each do |key_type|
        data_set[key_type] = key_type
      end
      data_set
    end
    def test_integer(key_type)
      setup_table_with_key_type(key_type)
      table.add(1)
      process(:delete,
              {"table" => "Books", "key" => 1})
      assert_equal(<<-DUMP, dump)
table_create Books TABLE_HASH_KEY #{key_type}
      DUMP
    end

    private
    def setup_table_with_key_type(key_type)
      Groonga::Schema.define do |schema|
        schema.create_table("Books",
                            :type     => :hash,
                            :key_type => key_type)
      end
    end

    def table
      Groonga::Context.default["Books"]
    end

    class MismatchedTypeKey < self
      class Acceptable < self
        def test_integer_for_string
          setup_table_with_key_type("ShortText")
          table.add("1")
          process(:delete,
                  {"table" => "Books", "key" => 1})
          assert_equal(<<-DUMP, dump)
table_create Books TABLE_HASH_KEY ShortText
          DUMP
        end

        def test_string_for_integer
          setup_table_with_key_type("UInt32")
          table.add(1)
          process(:delete,
                  {"table" => "Books", "key" => "1"})
          assert_equal(<<-DUMP, dump)
table_create Books TABLE_HASH_KEY UInt32
          DUMP
        end
      end
    end
  end

  class DeleteTest < self
    def test_id
      Groonga::Schema.define do |schema|
        schema.create_table("Ages", :type => :array)
      end
      Groonga::Context.default["Ages"].add([])
      process(:delete,
              {"table" => "Ages", "id" => 1})
      assert_equal(<<-DUMP, dump)
table_create Ages TABLE_NO_KEY
      DUMP
    end

    def test_filter
      Groonga::Schema.define do |schema|
        schema.create_table("Books", :type => :hash)
      end
      table = Groonga::Context.default["Books"]
      table.add("Groonga")
      table.add("Droonga")
      process(:delete,
              {"table" => "Books", "filter" => '_key @^ "D"'})
      assert_equal(<<-DUMP, dump)
table_create Books TABLE_HASH_KEY ShortText

load --table Books
[
["_key"],
["Groonga"]
]
      DUMP
    end
  end
end
