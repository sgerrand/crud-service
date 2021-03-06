require "crud-service"

describe CrudService::GenericDal do
  before(:each) do
    @mock_mysql = get_mysql_mock
    @mock_memcache = double('Memcache')
    @mock_log = double('Log')

    @generic_dal = CrudService::GenericDal.new(@mock_mysql, @mock_memcache, @mock_log)
    @generic_dal.table_name = "testtable"
  end

  describe '#initialize' do 
    it 'should inject dependencies correctly' do
      @generic_dal.mysql.should eq @mock_mysql
      @generic_dal.memcache.should eq @mock_memcache
      @generic_dal.log.should eq @mock_log
    end
  end

  describe '#cached_query' do
    it 'should attempt to query the cache before the database' do

      testdata = [ { "field_one" => "one" } ]

      mock_result = get_mysql_result_mock(testdata)

      query = 'test invalid query'
      query_hash = "geoservice-"+Digest::MD5.hexdigest(query+":testtable-1")

      @mock_memcache.should_receive(:get).ordered.with("testtable-version").and_return(1)
      @mock_memcache.should_receive(:get).ordered.with(query_hash).and_return(nil)
      @mock_mysql.should_receive(:query).with(query).and_return(mock_result)
      @mock_memcache.should_receive(:set).ordered.with(query_hash, testdata)

      @generic_dal.cached_query(query,[]).should eq testdata
    end

    it 'should not attempt to query the database on a cache hit' do
      
      testdata = [ { "field_one" => "one" } ]

      query = 'test invalid query'
      query_hash = "geoservice-"+Digest::MD5.hexdigest(query+":testtable-1")

      @mock_memcache.should_receive(:get).ordered.with("testtable-version").and_return(1)
      @mock_memcache.should_receive(:get).ordered.with(query_hash).and_return(testdata)
      @mock_mysql.should_not_receive(:query)
      @mock_memcache.should_not_receive(:set).ordered

      @generic_dal.cached_query(query,[]).should eq testdata
    end

    it 'should handle zero record return' do
      mock_result = get_mysql_result_mock([])
      memcache_null(@mock_memcache)

      query = 'test invalid query'
      query_hash = "geoservice-"+Digest::MD5.hexdigest(query)

      @mock_mysql.should_receive(:query).with(query).and_return(get_mysql_result_mock([]))

      @generic_dal.cached_query(query,[]).should eq([])
    end

    it 'should write a new table version to cache when not found' do
      testdata = [ { "field_one" => "one" } ]

      mock_result = get_mysql_result_mock(testdata)

      query = 'test invalid query'
      query_hash = "geoservice-"+Digest::MD5.hexdigest(query+":testtable-1")

      @mock_memcache.should_receive(:get).ordered.with("testtable-version").and_return(nil)
      @mock_memcache.should_receive(:get).ordered.with("testtable-version").and_return(nil)
      @mock_memcache.should_receive(:set).ordered.with("testtable-version",1,nil,{:raw=>true})
      @mock_memcache.should_receive(:get).ordered.with(query_hash).and_return(nil)
      @mock_mysql.should_receive(:query).ordered.with(query).and_return(mock_result)
      @mock_memcache.should_receive(:set).ordered.with(query_hash, testdata)

      @generic_dal.cached_query(query,[]).should eq testdata
    end

    it 'should miss the cache when a table version has changed' do
      testdata = [ { "field_one" => "one" } ]

      mock_result = get_mysql_result_mock(testdata)

      query = 'test invalid query'
      query_hash = "geoservice-"+Digest::MD5.hexdigest(query+":testtable-1")

      @mock_memcache.should_receive(:get).ordered.with("testtable-version").and_return(1)
      @mock_memcache.should_receive(:get).ordered.with(query_hash).and_return(nil)
      @mock_mysql.should_receive(:query).with(query).and_return(mock_result)
      @mock_memcache.should_receive(:set).ordered.with(query_hash, testdata)

      @generic_dal.cached_query(query,[]).should eq testdata

      query_hash = "geoservice-"+Digest::MD5.hexdigest(query+":testtable-2")

      @mock_memcache.should_receive(:get).ordered.with("testtable-version").and_return(2)
      @mock_memcache.should_receive(:get).ordered.with(query_hash).and_return(nil)
      @mock_mysql.should_receive(:query).with(query).and_return(mock_result)
      @mock_memcache.should_receive(:set).ordered.with(query_hash, testdata)

      @generic_dal.cached_query(query,[]).should eq testdata
    end

  end

  describe '#build_where' do
    it 'should return an empty string when called with no query' do
      query = { }
      @generic_dal.build_where(query).should eq ""
    end

    it 'should return a valid where clause when called with a single field query string value' do
      query = { "one" => "two" }
      @generic_dal.build_where(query).should eq "(`one` = 'two')"
    end

    it 'should return a valid where clause when called with a single field query integer value' do
      query = { "one" => 2 }
      @generic_dal.build_where(query).should eq "(`one` = 2)"
    end

    it 'should return a valid where clause when called with a single field query float value' do
      query = { "one" => 2.123 }
      @generic_dal.build_where(query).should eq "(`one` = 2.123)"
    end

    it 'should return a valid where clause when called with a multiple field query' do
      query = { "one" => "two", "three" => "four" }
      @generic_dal.build_where(query).should eq "(`one` = 'two') AND (`three` = 'four')"
    end

    it 'should return a valid where clause when called with a query with a nil value' do
      query = { "one" => "two", "three" => nil}
      @generic_dal.build_where(query).should eq "(`one` = 'two') AND (`three` IS NULL)"
    end

    it 'should escape field names' do
      query = { "on`=1; DROP TABLE countries" => "two" }
      @generic_dal.build_where(query).should eq "(`on=1; DROP TABLE countries` = 'two')"
    end

    it 'should escape field values when string based' do
      query = { "one" => "two'; DROP TABLE countries;" }
      @generic_dal.build_where(query).should eq "(`one` = 'two\\'; DROP TABLE countries;')"
    end

    it 'should not build include or exclude into queries' do
      query = { "one" => 2, "include" => "subdivisions", "exclude" => "countries", "two"=>3 }
      @generic_dal.build_where(query).should eq "(`one` = 2) AND (`two` = 3)"
    end
  end

  describe '#build_where_ns_ns' do
    it 'should return an empty string when called with no query' do
      query = { }
      @generic_dal.build_where_ns(query,'a').should eq ""
    end

    it 'should return a valid where clause when called with a single field query string value' do
      query = { "one" => "two" }
      @generic_dal.build_where_ns(query,'b').should eq "(`b`.`one` = 'two')"
    end

    it 'should return a valid where clause when called with a single field query integer value' do
      query = { "one" => 2 }
      @generic_dal.build_where_ns(query,'c').should eq "(`c`.`one` = 2)"
    end

    it 'should return a valid where clause when called with a single field query float value' do
      query = { "one" => 2.123 }
      @generic_dal.build_where_ns(query,'d').should eq "(`d`.`one` = 2.123)"
    end

    it 'should return a valid where clause when called with a multiple field query' do
      query = { "one" => "two", "three" => "four" }
      @generic_dal.build_where_ns(query,'e').should eq "(`e`.`one` = 'two') AND (`e`.`three` = 'four')"
    end

    it 'should return a valid where clause when called with a query with a nil value' do
      query = { "one" => "two", "three" => nil}
      @generic_dal.build_where_ns(query,'f').should eq "(`f`.`one` = 'two') AND (`f`.`three` IS NULL)"
    end

    it 'should escape field names' do
      query = { "on`=1; DROP TABLE countries" => "two" }
      @generic_dal.build_where_ns(query,'g').should eq "(`g`.`on=1; DROP TABLE countries` = 'two')"
    end

    it 'should escape field values when string based' do
      query = { "one" => "two'; DROP TABLE countries;" }
      @generic_dal.build_where_ns(query,'h').should eq "(`h`.`one` = 'two\\'; DROP TABLE countries;')"
    end

    it 'should not build include or exclude into queries' do
      query = { "one" => 2, "include" => "subdivisions", "exclude" => "countries", "two"=>3 }
      @generic_dal.build_where_ns(query,'i').should eq "(`i`.`one` = 2) AND (`i`.`two` = 3)"
    end
  end

  describe '#build_fields' do
    it 'should return an empty string with no fields' do
      @generic_dal.build_select_fields([],nil).should eq ""
    end

    it 'should return fields correctly' do
      @generic_dal.build_select_fields(['one','two'],nil).should eq "`one`,`two`"
    end

    it 'should return namespaced fields correctly' do
      @generic_dal.build_select_fields(['one','two'],'a').should eq "`a`.`one`,`a`.`two`"
    end
  end

  describe '#build_fields' do
    before(:each) do
      @generic_dal.fields = {
        "test1" => { :type=>:string },
        "test2" => { :type=>:string },
        "testX" => { :type=>:string },
      }
    end
    
    it 'should return all fields with nil excludes' do
      @generic_dal.build_fields({}).should eq "`test1`,`test2`,`testX`"
    end

    it 'should return all fields with empty excludes' do
      @generic_dal.build_fields({"exclude"=>nil}).should eq "`test1`,`test2`,`testX`"
    end

    it 'should exclude a single field' do
      @generic_dal.build_fields({"exclude"=>'test1'}).should eq "`test2`,`testX`"
    end

    it 'should exclude multiple fields' do
      @generic_dal.build_fields({"exclude"=>'test1,testX'}).should eq "`test2`"
    end
  end

  describe '#build_fields_with_ns' do
    before(:each) do
      @generic_dal.fields = {
        "test1" => { :type=>:string },
        "test2" => { :type=>:string },
        "testX" => { :type=>:string },
      }
    end
    
    it 'should return all fields with nil excludes' do
      @generic_dal.build_fields_with_ns({},'a').should eq "`a`.`test1`,`a`.`test2`,`a`.`testX`"
    end

    it 'should return all fields with empty excludes' do
      @generic_dal.build_fields_with_ns({"exclude"=>nil},'b').should eq "`b`.`test1`,`b`.`test2`,`b`.`testX`"
    end

    it 'should exclude a single field' do
      @generic_dal.build_fields_with_ns({"exclude"=>'test1'},'c').should eq "`c`.`test2`,`c`.`testX`"
    end

    it 'should exclude multiple fields' do
      @generic_dal.build_fields_with_ns({"exclude"=>'test1,testX'},'d').should eq "`d`.`test2`"
    end
  end

  describe '#get_includes' do
    before(:each) do
      @generic_dal.fields = ["test1", "test2", "testX"]
    end

    it 'should return an empty array with a nil query' do
      @generic_dal.get_includes(nil).should eq []
    end

    it 'should return an empty array with no fields or includes' do
      query = { }
      @generic_dal.get_includes(query).should eq []
    end

    it 'should return an empty array with fields and no includes' do
      query = { "field2" => "xxas"}
      @generic_dal.get_includes(query).should eq []
    end

    it 'should return a single include' do
      query = { "include"=>"test1" }
      @generic_dal.get_includes(query).should eq ['test1']
    end

    it 'should return multiple includes' do
      query = { "include"=>"test1,test2"}
      @generic_dal.get_includes(query).should eq ['test1','test2']
    end
  end

  describe '#get_excludes' do
    before(:each) do
      @generic_dal.fields = {
        "test1" => { :type=>:string },
        "test2" => { :type=>:string },
        "testX" => { :type=>:string },
      }
    end

    it 'should return an empty array with a nil query' do
      @generic_dal.get_excludes(nil).should eq []
    end

    it 'should return an empty array with no fields or excludes' do
      query = { }
      @generic_dal.get_excludes(query).should eq []
    end

    it 'should return an empty array with fields and no excludes' do
      query = { "field2" => "xxas"}
      @generic_dal.get_excludes(query).should eq []
    end

    it 'should return a single exclude' do
      query = { "exclude"=>"test1", "field2" => "xxas"}
      @generic_dal.get_excludes(query).should eq ['test1']
    end

    it 'should return multiple excludes' do
      query = { "exclude"=>"test1,test2"}
      @generic_dal.get_excludes(query).should eq ['test1','test2']
    end
  end

  describe '#build_equal_condition' do
    it 'should return IS NULL for a nil' do
      @generic_dal.build_equal_condition(nil).should eq 'IS NULL'
    end

    it 'should return correct response for an integer' do
      @generic_dal.build_equal_condition(1).should eq '= 1'
    end

    it 'should return correct response for a float' do
      @generic_dal.build_equal_condition(1.123).should eq '= 1.123'
    end

    it 'should return correct response for a string' do
      @generic_dal.build_equal_condition('ABC').should eq "= 'ABC'"
    end

    it 'should return correct escaped response for a string' do
      @generic_dal.build_equal_condition("AB'; DROP TABLE test_table --").should eq "= 'AB\\'; DROP TABLE test_table --'"
    end
  end

  describe '#valid_query?' do
    before(:each) do
      @generic_dal.fields = {
        "one" => { :type=>:string },
        "two" => { :type=>:string },
        "three" => { :type=>:string },
      }
      @generic_dal.relations = {
        "four" => { :type=>:string },
        "five" => { :type=>:string },
        "six" => { :type=>:string },
      }
    end
    
    it 'should return true with valid fields' do
      @generic_dal.valid_query?({"one"=>1}).should be true
    end

    it 'should return false with invalid fields' do
      @generic_dal.valid_query?({"five"=>1}).should be false
    end

    it 'should return true with valid relations' do
      @generic_dal.valid_query?({"include"=>'four,five'}).should be true
    end

    it 'should return false with invalid relations' do
      @generic_dal.valid_query?({"include"=>'ten'}).should be false
    end

    it 'should return false with nil' do
      @generic_dal.valid_query?(nil).should be false
    end

    it 'should return true with no fields' do
      @generic_dal.valid_query?({}).should be true
    end

    it 'should return true regardless of include' do
      @generic_dal.valid_query?({"one"=>1,"include"=>"two"}).should be true
    end

    it 'should return true regardless of exclude' do
      @generic_dal.valid_query?({"one"=>1,"exclude"=>"one"}).should be true
    end

    it 'should return false as cannot exclude a relation' do
      @generic_dal.valid_query?({"one"=>1,"exclude"=>"five"}).should be false
    end
  end

  describe '#escape_str_field' do
    it 'should escape single quotes' do
      @generic_dal.escape_str_field("ABC'BC").should eq "ABC\\'BC"
    end

    it 'should remove backtics' do
      @generic_dal.escape_str_field("ABC`BC").should eq "ABCBC"
    end

    it 'should resolve symbols as well as strings' do
      @generic_dal.escape_str_field(:testing).should eq "testing"
    end
  end

  describe '#get_all_by_query' do
    it 'should call cached_query with the correct query for one field' do
      memcache_null(@mock_memcache)
      @generic_dal.fields = {
        "one" => { :type=>:string },
        "two" => { :type=>:string },
      }
      @generic_dal.table_name = 'test_table'

      @mock_mysql.should_receive(:query).with("SELECT `one`,`two` FROM `test_table` WHERE (`field` = 'test2')")

      @generic_dal.get_all_by_query({ :field => 'test2' })
    end

    it 'should call cached_query with the correct query for multiple fields' do
      memcache_null(@mock_memcache)
      @generic_dal.fields = {
        "one" => { :type=>:string },
        "two" => { :type=>:string },
      }
      @generic_dal.table_name = 'test_table'

      @mock_mysql.should_receive(:query).with("SELECT `one`,`two` FROM `test_table` WHERE (`field` = 'test2') AND (`twofield` = 2) AND (`nullfield` IS NULL)")

      @generic_dal.get_all_by_query({ :field => 'test2', "twofield" =>2, "nullfield" => nil })
    end
  end

  describe '#get_one' do
    before(:each) do
      memcache_null(@mock_memcache)

      @generic_dal.fields = {
        "one" => { :type=>:string },
        "two" => { :type=>:string },
      }

      @generic_dal.table_name = 'test_table'

      @mock_result = get_mysql_result_mock([
        { "field_one" => "one" },
        { "field_one" => "two" } 
      ])
    end

    it 'should call cached_query with the correct query for one field and return a single object' do
      @mock_mysql.should_receive(:query)
        .with("SELECT `one`,`two` FROM `test_table` WHERE (`field` = 'test2')")
        .and_return(@mock_result)

      @generic_dal.get_one({ :field => 'test2' }).should eq({ "field_one" => "one" })
    end

    it 'should call cached_query with the correct query for one field and return a single object' do
      @mock_mysql.should_receive(:query)
        .with("SELECT `one`,`two` FROM `test_table` WHERE (`field` = 'test2') AND (`field_two` = 'test3')")
        .and_return(@mock_result)

      @generic_dal.get_one({ :field => 'test2', :field_two => 'test3' }).should eq({ "field_one" => "one" })
    end
  end

  describe '#map_to_hash_by_primary_key' do
    before(:each) do
      @generic_dal.primary_key = 'id'
    end

    it 'should return an empty hash when given an empty array' do
      test = []

      @generic_dal.map_to_hash_by_primary_key(test).should eq({})
    end

    it 'should correctly map an array' do
      test = [
        { "id" => 1, "field_one" => "one" },
        { "id" => 2.5, "field_one" => "two point five" },
        { "id" => "3", "field_one" => "three" },
        { "id" => nil, "field_one" => "four" } 
      ]

      @generic_dal.map_to_hash_by_primary_key(test).should eq({
        1 => { "id" => 1, "field_one" => "one" },
        2.5 => { "id" => 2.5, "field_one" => "two point five" },
        "3" => { "id" => "3", "field_one" => "three" },
        nil =>  { "id" => nil, "field_one" => "four" } 
      })
    end
  end

  describe '#remove_key_from_hash_of_arrays!' do
  
    it 'should remove a key from each hash in each array in each hash value' do

      test = {
        'one' => [ ],
        2 => [ {"x" => 'a', "y" => 'b', 'z' => 'c' } ],
        nil => [ {"x" => 'd', "y" => 'e', 'z' => 'f' }, {"x" => 'g', "y" => 'h', 'z' => 'i' } ],
      }

      @generic_dal.remove_key_from_hash_of_arrays!(test,'z')

      test.should eq({
        'one' => [ ],
        2 => [ {"x" => 'a', "y" => 'b'} ],
        nil => [ {"x" => 'd', "y" => 'e' }, {"x" => 'g', "y" => 'h' } ],
      })

    end
  end

  describe '#map_to_hash_of_arrays_by_key' do
    it 'should return an empty hash when given an empty array' do
      test = []

      @generic_dal.map_to_hash_of_arrays_by_key(test,'field_one').should eq({})
    end

    it 'should correctly map an array' do
      test = [
        { "id" => 1, "field_one" => 1 },
        { "id" => 2.5, "field_one" => "two point five" },
        { "id" => "3", "field_one" => "three" },
        { "id" => nil, "field_one" => 4.5 }, 
        { "id" => nil, "field_one" => 1 },
        { "id" => 90, "field_one" => "two point five" },
        { "id" => nil, "field_one" => "four" },
        { "id" => "16", "field_one" => "three" },
        { "id" => 2.1, "field_one" => 4.5 },
        { "id" => 328, "field_one" => "one" },
        { "id" => nil, "field_one" => nil },
        { "id" => 123, "field_one" => nil },
      ]

      @generic_dal.map_to_hash_of_arrays_by_key(test,'field_one').should eq({
        nil => [
          { "id" => nil, "field_one" => nil },
          { "id" => 123, "field_one" => nil },
        ],
        1 => [
          { "id" => 1, "field_one" => 1 },
          { "id" => nil, "field_one" => 1 },
        ],
        "two point five" => [
          { "id" => 2.5, "field_one" => "two point five" },
          { "id" => 90, "field_one" => "two point five" },
        ],
        "three" => [
          { "id" => "3", "field_one" => "three" },
          { "id" => "16", "field_one" => "three" },
        ],
        "four" => [
          { "id" => nil, "field_one" => "four" },
        ],
        4.5 => [
          { "id" => nil, "field_one" => 4.5 },
          { "id" => 2.1, "field_one" => 4.5 },
        ],
        "one" => [
          { "id" => 328, "field_one" => "one" },
        ]
      })
    end
  end

  describe '#add_field_from_map!' do
    it 'should map correctly' do
      records = [
        {"id"=>1, "fk_code"=>"EU", "name"=>"Test1" },
        {"id"=>2, "fk_code"=>"EU", "name"=>"Test2" },
        {"id"=>3, "fk_code"=>"AU", "name"=>"Test3" },
        {"id"=>4, "fk_code"=>"GB", "name"=>"Test4" },
        {"id"=>5, "fk_code"=>"US", "name"=>"Test5" },
        {"id"=>6, "fk_code"=>nil, "name"=>"Test5" },
      ]

      map = {
        'EU' => 1,
        'AU' => { "name"=>"one" },
        'US' => nil,
        'GB' => "test!"
      }

      @generic_dal.add_field_from_map!(records, map, 'fk_field', 'fk_code')

      records.should eq [
        {"id"=>1, "fk_code"=>"EU", "name"=>"Test1", "fk_field"=>1 },
        {"id"=>2, "fk_code"=>"EU", "name"=>"Test2", "fk_field"=>1 },
        {"id"=>3, "fk_code"=>"AU", "name"=>"Test3", "fk_field"=>{ "name"=>"one" } },
        {"id"=>4, "fk_code"=>"GB", "name"=>"Test4", "fk_field"=>"test!" },
        {"id"=>5, "fk_code"=>"US", "name"=>"Test5", "fk_field"=>nil },
        {"id"=>6, "fk_code"=>nil, "name"=>"Test5" },
      ]

    end
  end

  describe '#get_relation_query_sql' do
    it 'should return the correct sql for a has_one relation with no query' do

      @generic_dal.table_name = "currencies"

      rel = { 
        :type         => :has_one, 
        :table        => 'countries',
        :table_key    => 'default_currency_code', 
        :this_key     => 'code',
        :table_fields => 'code_alpha_2,name',
      }

      @generic_dal.get_relation_query_sql(rel,{}).should eq(
        "SELECT `a`.`code_alpha_2`,`a`.`name`,`b`.`code` AS `_table_key` FROM `countries` AS `a`, `currencies` AS `b` WHERE (`a`.`default_currency_code` = `b`.`code`)"
      )
      
    end

    it 'should return the correct sql for a has_one relation with a query' do

      @generic_dal.table_name = "currencies"

      rel = { 
        :type         => :has_one, 
        :table        => 'countries',
        :table_key    => 'default_currency_code', 
        :this_key     => 'code',
        :table_fields => 'code_alpha_2,name',
      }

      @generic_dal.get_relation_query_sql(rel,{'testfield'=>1}).should eq(
        "SELECT `a`.`code_alpha_2`,`a`.`name`,`b`.`code` AS `_table_key` FROM `countries` AS `a`, `currencies` AS `b` WHERE (`a`.`default_currency_code` = `b`.`code`) AND (`b`.`testfield` = 1)"
      )
      
    end

    it 'should return the correct sql for a has_many relation' do

      @generic_dal.table_name = "houses"

      rel = { 
        :type         => :has_many,
        :table        => 'cats',
        :table_key    => 'house_id', 
        :this_key     => 'id',
        :table_fields => 'cat_id,name',
      }

      @generic_dal.get_relation_query_sql(rel,{}).should eq(
        "SELECT `a`.`cat_id`,`a`.`name`,`b`.`id` AS `_table_key` FROM `cats` AS `a`, `houses` AS `b` WHERE (`a`.`house_id` = `b`.`id`)"
      )
      
    end

    it 'should return the correct sql for a has_many relation with a query' do

      @generic_dal.table_name = "houses"

      rel = { 
        :type         => :has_many,
        :table        => 'cats',
        :table_key    => 'house_id', 
        :this_key     => 'id',
        :table_fields => 'cat_id,name',
      }

      @generic_dal.get_relation_query_sql(rel,{"colour"=>"ginger"}).should eq(
        "SELECT `a`.`cat_id`,`a`.`name`,`b`.`id` AS `_table_key` FROM `cats` AS `a`, `houses` AS `b` WHERE (`a`.`house_id` = `b`.`id`) AND (`b`.`colour` = 'ginger')"
      )
      
    end

    it 'should return the correct sql for a has_many_through relation' do

      @generic_dal.table_name = "countries"

      rel = { 
        :type         => :has_many_through,
        :table        => 'regions',
        :link_table   => 'region_countries',
        :link_key     => 'country_code_alpha_2',
        :link_field   => 'region_code',
        :table_key    => 'code', 
        :this_key     => 'code_alpha_2',
        :table_fields => 'code,name',
      }

      @generic_dal.get_relation_query_sql(rel,{}).should eq(
        "SELECT `a`.`code`,`a`.`name`,`c`.`code_alpha_2` AS `_table_key` FROM `regions` AS `a`, `region_countries` AS `b`, `countries` AS `c` WHERE (`a`.`code` = `b`.`region_code` AND `b`.`country_code_alpha_2` = `c`.`code_alpha_2`)"
      )
      
    end

    it 'should return the correct sql for a has_many_through relation with a query' do

      @generic_dal.table_name = "countries"

      rel = { 
        :type         => :has_many_through,
        :table        => 'regions',
        :link_table   => 'region_countries',
        :link_key     => 'country_code_alpha_2',
        :link_field   => 'region_code',
        :table_key    => 'code', 
        :this_key     => 'code_alpha_2',
        :table_fields => 'code,name',
      }

      @generic_dal.get_relation_query_sql(rel,{"default_currency_code"=>"EUR"}).should eq(
        "SELECT `a`.`code`,`a`.`name`,`c`.`code_alpha_2` AS `_table_key` FROM `regions` AS `a`, `region_countries` AS `b`, `countries` AS `c` WHERE (`a`.`code` = `b`.`region_code` AND `b`.`country_code_alpha_2` = `c`.`code_alpha_2`) AND (`c`.`default_currency_code` = 'EUR')"
      )
      
    end
  end

  describe "#get_relation_tables" do
    it 'should return the correct tables for a has_one relation' do
      @generic_dal.table_name = "currencies"

      rel = { 
        :type         => :has_one, 
        :table        => 'countries',
        :table_key    => 'default_currency_code', 
        :this_key     => 'code',
        :table_fields => 'code_alpha_2,name',
      }

      @generic_dal.get_relation_tables(rel).should eq(["countries", "currencies"])
    end

    it 'should return the correct tables for a has_many relation' do
      @generic_dal.table_name = "houses"

      rel = { 
        :type         => :has_many,
        :table        => 'cats',
        :table_key    => 'house_id', 
        :this_key     => 'id',
        :table_fields => 'cat_id,name',
      }

      @generic_dal.get_relation_tables(rel).should eq(["cats", "houses"])
    end

    it 'should return the correct tables for a has_many_through relation' do
      @generic_dal.table_name = "countries"

      rel = { 
        :type         => :has_many_through,
        :table        => 'regions',
        :link_table   => 'region_countries',
        :link_key     => 'country_code_alpha_2',
        :link_field   => 'region_code',
        :table_key    => 'code', 
        :this_key     => 'code_alpha_2',
        :table_fields => 'code,name',
      }

      @generic_dal.get_relation_tables(rel).should eq(["countries","region_countries","regions"])
    end
  end

  describe '#expire_table_cache' do
    it 'should set a table version when it doesnt exist' do

      @mock_memcache.should_receive(:get).ordered.with("testtable-version").and_return(nil)
      @mock_memcache.should_receive(:set).ordered.with("testtable-version",1,nil,{:raw=>true}).and_return(nil)

      @generic_dal.expire_table_cache(['testtable'])
    end

    it 'should increment a table version when it exists' do

      @mock_memcache.should_receive(:get).ordered.with("testtable-version").and_return(1)
      @mock_memcache.should_receive(:incr).ordered.with("testtable-version",1,nil).and_return(nil)

      @generic_dal.expire_table_cache(['testtable'])
    end

    it 'should expire multiple tables' do

      @mock_memcache.should_receive(:get).ordered.with("testtable-version").and_return(1)
      @mock_memcache.should_receive(:incr).ordered.with("testtable-version",1,nil).and_return(nil)
      @mock_memcache.should_receive(:get).ordered.with("tabletwo-version").and_return(1)
      @mock_memcache.should_receive(:incr).ordered.with("tabletwo-version",1,nil).and_return(nil)

      @generic_dal.expire_table_cache(['testtable','tabletwo'])
    end
  end

  describe '#exists_by_primary_key?' do
    before do
      memcache_null(@mock_memcache)

      @generic_dal.table_name = 'pktesttable'
      @generic_dal.primary_key = 'id'

      @mock_result = get_mysql_result_mock([ { "c" => 1 } ])
    end

    it 'should call cached_query with correct sql with a numeric primary key' do
      @mock_mysql.should_receive(:query).with("SELECT COUNT(*) AS `c` FROM `pktesttable` WHERE (`id` = 2002)").and_return(@mock_result)

      @generic_dal.exists_by_primary_key?(2002).should eq(true)
    end

    it 'should call cached_query with correct sql with a string primary key' do
      @mock_mysql.should_receive(:query).with("SELECT COUNT(*) AS `c` FROM `pktesttable` WHERE (`id` = 'test')").and_return(@mock_result)

      @generic_dal.exists_by_primary_key?('test').should eq(true)
    end

    it 'should return true when count is not 0' do
      @mock_result = get_mysql_result_mock([ { "c" => 1 } ])

      @mock_mysql.should_receive(:query).with("SELECT COUNT(*) AS `c` FROM `pktesttable` WHERE (`id` = 'test')").and_return(@mock_result)

      @generic_dal.exists_by_primary_key?('test').should eq(true)
    end

    it 'should return false when count is 0' do
      @mock_result = get_mysql_result_mock([ { "c" => 0 } ])

      @mock_mysql.should_receive(:query).with("SELECT COUNT(*) AS `c` FROM `pktesttable` WHERE (`id` = 'test')").and_return(@mock_result)

      @generic_dal.exists_by_primary_key?('test').should eq(false)
    end
  end

  describe '#valid_insert?' do
    it 'should return false if object nil' do
      @generic_dal.valid_insert?(nil).should eq(false)
    end

    it 'should return false if object empty' do
      @generic_dal.valid_insert?({}).should eq(false)
    end

    it 'should return true if all fields exist' do
      @generic_dal.fields = {
        "one" => { :type=>:string },
        "two" => { :type=>:string },
      }

      @generic_dal.valid_insert?({ "one"=>"1", "two"=>"2" }).should eq(true)
    end

    it 'should return false if fields do not exist' do
      @generic_dal.fields = {
        "one" => { :type=>:string },
        "two" => { :type=>:string },
      }

      @generic_dal.valid_insert?({ "five"=>"1", "two"=>"2" }).should eq(false)
    end

    it 'should return true if data is within the max length' do
      @generic_dal.fields = {
        "one" => { :type=>:string },
        "two" => { :type=>:string, :length=>4 },
      }

      @generic_dal.valid_insert?({ "one"=>"1", "two"=>"2" }).should eq(true)
    end

    it 'should return false if data is greater than the max length' do
      @generic_dal.fields = {
        "one" => { :type=>:string },
        "two" => { :type=>:string, :length=>4 },
      }

      @generic_dal.valid_insert?({ "one"=>"1", "two"=>"22332" }).should eq(false)
    end

    it 'should return false if required key is missing' do
      @generic_dal.fields = {
        "one" => { :type=>:string },
        "two" => { :type=>:string, :required=>true },
      }

      @generic_dal.valid_insert?({ "one"=>"1" }).should eq(false)
    end

    it 'should return true if required keys are ok' do
      @generic_dal.fields = {
        "one" => { :type=>:string, :required=>true  },
        "two" => { :type=>:string, :required=>true },
      }

      @generic_dal.valid_insert?({ "one"=>"1","two"=>"2" }).should eq(true)
    end
  end

  describe '#valid_update?' do
    it 'should return false if object nil' do
      @generic_dal.valid_update?(nil).should eq(false)
    end

    it 'should return false if object empty' do
      @generic_dal.valid_update?({}).should eq(false)
    end

    it 'should return true if all fields exist' do
      @generic_dal.fields = {
        "one" => { :type=>:string },
        "two" => { :type=>:string },
      }

      @generic_dal.valid_update?({ "one"=>"1", "two"=>"2" }).should eq(true)
    end

    it 'should return false if fields do not exist' do
      @generic_dal.fields = {
        "one" => { :type=>:string },
        "two" => { :type=>:string },
      }

      @generic_dal.valid_update?({ "five"=>"1", "two"=>"2" }).should eq(false)
    end

    it 'should return false if data is greater than the max length' do
      @generic_dal.fields = {
        "one" => { :type=>:string },
        "two" => { :type=>:string, :length=>4 },
      }

      @generic_dal.valid_update?({ "one"=>"1", "two"=>"22332" }).should eq(false)
    end
  end

  describe "#escape_value" do
    it 'should return NULL for nil' do
      @generic_dal.escape_value(nil).should eq('NULL')
    end

    it 'should return integer for int/float' do
      @generic_dal.escape_value(1).should eq('1')
      @generic_dal.escape_value(1.45).should eq('1.45')
    end

    it 'should return a quoted string for string' do
      @generic_dal.escape_value('test').should eq("'test'")
    end

    it 'should escape sql values properly' do
      @generic_dal.escape_value("test '; DROP TABLE test; --").should eq("'test \\'; DROP TABLE test; --'")
    end
  end

  describe "#build_insert" do
    it 'should return correct SQL fragment for basic fields' do
      data = {
        "one" => 1,
        "two" => "2",
        "three" => nil,
      }

      @generic_dal.build_insert(data).should eq("(`one`, `two`, `three`) VALUES (1, '2', NULL)")
    end

    it 'should escape field names and data' do
      data = {
        "one`; DROP TABLE test; -- " => 1,
        "two" => "two",
        "three" => "'; DROP TABLE test; --'",
      }

      @generic_dal.build_insert(data).should eq("(`one; DROP TABLE test; -- `, `two`, `three`) VALUES (1, 'two', '\\'; DROP TABLE test; --\\'')")
    end
  end

  describe "#build_update" do
    it 'should return correct SQL fragment for basic fields' do
      data = {
        "one" => 1,
        "two" => "two",
        "three" => nil,
      }

      @generic_dal.build_update(data).should eq("`one` = 1, `two` = 'two', `three` = NULL")
    end

    it 'should escape field names and data' do
      data = {
        "one`; DROP TABLE test; -- " => 1,
        "two" => "2",
        "three" => "'; DROP TABLE test; --'",
      }

      @generic_dal.build_update(data).should eq("`one; DROP TABLE test; -- ` = 1, `two` = '2', `three` = '\\'; DROP TABLE test; --\\''")
    end
  end

  describe "#get_all_related_tables" do
    it 'should return the table name for nil relations' do
      @generic_dal.table_name = 'test1'

      @generic_dal.relations = nil

      @generic_dal.get_all_related_tables.should eq(["test1"])
    end

    it 'should return the table name for empty relations' do
      @generic_dal.table_name = 'test1'

      @generic_dal.relations = {}

      @generic_dal.get_all_related_tables.should eq(["test1"])
    end

    it 'should return the table name for a single relations' do
      @generic_dal.table_name = 'test1'

       @generic_dal.relations = {
        'countries' => { 
          :type         => :has_one, 
          :table        => 'countries',
          :table_key    => 'default_currency_code', 
          :this_key     => 'code',
          :table_fields => 'code_alpha_2,name',
        },
      }

      @generic_dal.get_all_related_tables.should eq(["countries","test1"])
    end


    it 'should return the correct table names for multiple relations with dedupe' do
      @generic_dal.table_name = 'test1'

      @generic_dal.relations = {
        'countries' => { 
          :type         => :has_one, 
          :table        => 'countries',
          :table_key    => 'default_currency_code', 
          :this_key     => 'code',
          :table_fields => 'code_alpha_2,name',
        },
        'countries2' => { 
          :type         => :has_many, 
          :table        => 'countries',
          :table_key    => 'default_currency_code', 
          :this_key     => 'code',
          :table_fields => 'code_alpha_2,name',
        },
        'regions' => { 
          :type         => :has_many_through,
          :table        => 'regions',
          :link_table   => 'region_countries',
          :link_key     => 'country_code_alpha_2',
          :link_field   => 'region_code',
          :table_key    => 'code', 
          :this_key     => 'code_alpha_2',
          :table_fields => 'code,name',
        }
      }

      @generic_dal.get_all_related_tables.should eq(["countries", "region_countries", "regions", "test1"])
    end
  end

  describe '#insert' do
    it 'should call the correct sql and expire the correct cache' do
      testdata = { "field_one" => "one" }

      @generic_dal.table_name = "test_table"
      @generic_dal.fields = {
        "field_one" => { :type => :integer }
      }

      query = "INSERT INTO `test_table` (`field_one`) VALUES ('one')"

      @mock_mysql.should_receive(:query).ordered.with(query)

      @mock_memcache.should_receive(:get).ordered.with('test_table-version').and_return(1)
      @mock_memcache.should_receive(:incr).ordered.with('test_table-version',1,nil)
      
      @mock_memcache.should_receive(:get).ordered.with('test_table-version').and_return(1)
      @mock_memcache.should_receive(:get).ordered.and_return([{ "field_one" => "one","id"=>1 }])
            
      @generic_dal.insert(testdata)
    end
  end

  describe '#update_by_primary_key' do
    it 'should call the correct sql and expire the correct cache' do
      testdata = { "field_one" => "two" }

      @generic_dal.table_name = "test_table"
      @generic_dal.primary_key = "code"
      @generic_dal.fields = {
        "field_one" => { :type => :integer }
      }

      query = "UPDATE `test_table` SET `field_one` = 'two' WHERE (`code` = 2)"

      @mock_mysql.should_receive(:query).ordered.with(query)
      
      @mock_memcache.should_receive(:get).ordered.with('test_table-version').and_return(1)
      @mock_memcache.should_receive(:incr).ordered.with('test_table-version',1,nil)
      
      @mock_memcache.should_receive(:get).ordered.with('test_table-version').and_return(1)
      @mock_memcache.should_receive(:get).ordered.and_return([{ "field_one" => "two","id"=>2}])
      
      @generic_dal.update_by_primary_key(2, testdata)
    end
  end

  describe '#delete_by_primary_key' do
    it 'should call the correct sql and expire the correct cache' do

      @generic_dal.table_name = "test_table"
      @generic_dal.primary_key = "code"

      query = "DELETE FROM `test_table` WHERE (`code` = 'three')"

      @mock_mysql.should_receive(:query).ordered.with(query)
      @mock_memcache.should_receive(:get).ordered.with('test_table-version').and_return(1)
      @mock_memcache.should_receive(:incr).ordered.with('test_table-version',1,nil)
      
      @generic_dal.delete_by_primary_key('three')
    end
  end

end