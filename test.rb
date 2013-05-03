#!/usr/bin/env ruby
#
# Test fedora access permissions
#

require 'rest-client'

# configuration of fedora instance

class Fedora
  attr_reader :host, :port, :admin_user, :admin_pass

  def initialize(host, port, admin_user, admin_pass)
    @host = host
    @port = port
    @admin_user = admin_user
    @admin_pass = admin_pass
  end
  def transmit(options = {})
    rest_options = {}
    rest_options[:method] = options[:method] || :get
    command = options[:command]
    rest_options[:url] = "http://#{host}:#{port}/fedora/#{command}"
    if options[:user]
      rest_options[:user] = options[:user]
      rest_options[:password] = options[:password]
    end
    #puts rest_options unless options[:not_verbose]
    rest_options[:payload] = options[:post_data] if options[:post_data]
    code = RestClient::Request.execute(rest_options) { |response, _, _| response.code }
    return code
  end
  def try_create_object(pid)
    # does object exist?
    res_code = transmit(command: "objects/#{pid}",
                        user: admin_user,
                        password: admin_pass,
                        not_verbose: true)
    case res_code
    when 200 #"Object #{pid} already exists"
    when 401 # object exists, but we don't have permission to touch it
    when 404 # object does not exist
      puts "Creating object #{pid}"
      transmit(command: "objects/#{pid}?label=test",
               user: admin_user,
               password: admin_pass,
               not_verbose: true,
               method: :post)
      return true
    else # wat?!
      # puts "Got code #{res_code} making #{pid}"
    end
    false
  end
end
class Suite
  def should_work(tests)
    tests = [tests] unless tests.respond_to?(:each)
    tests.each do |test|
      perform(200, test[:label], test)
    end
  end
  def should_not_work(tests)
    tests = [tests] unless tests.respond_to?(:each)
    tests.each do |test|
      perform(401, test[:label], test)
    end
  end
end
class TestSuite < Suite
  attr_reader :fedora
  attr_accessor :total_count, :success_count, :fail_count

  def self.with_fedora(host, port, admin_user, admin_pass)
    ts = TestSuite.new(Fedora.new(host, port, admin_user, admin_pass))
    yield ts
    ts.display_counts
  end

  def initialize(fedora)
    @fedora = fedora
    self.total_count = 0
    self.success_count = 0
    self.fail_count = 0
  end

  def display_counts
    puts <<EOS
====================
#{total_count} tests:
 #{success_count} Successes
 #{fail_count} Failures
EOS
  end

  def as_user(label, username=nil, password=nil)
    yield UserSuite.new(self, label, username, password)
  end
  def as_users(user_list)
    user_list.each do |u|
      yield UserSuite.new(self, u[:label], u[:username], u[:password])
    end
  end
  # expected result is the http status code we are expecting
  def perform(expected_result, description, api_call)
    @total_count += 1
    # make sure all $PID placeholders have been expanded
    raise "Missing pid #{description}" if api_call[:command] =~ /\$PID/

    # TODO: support the log file

    print "#{total_count}) #{description}... "
    res_code = fedora.transmit(api_call)
    print "(#{response_code_to_string(res_code)}) "
    # canonicalize the result codes for testing purposes
    res_code = 200 if res_code == 201
    res_code = 401 if res_code == 403
    res_code = 401 if res_code == 400
    if expected_result == res_code
      print "pass\n"
      @success_count += 1
    else
      print "***fail***\n"
      @fail_count += 1
    end
  end

  private
  def response_code_to_string(code)
    case code
    when 200,201 then "worked"
    when 401,403 then "rejected"
    else "#{code}"
    end
  end
end

class UserSuite < Suite
  attr_reader :label, :username, :password, :target

  def initialize(target, label, username, password)
    @target = target
    @label = label
    @username = username
    @password = password
  end
  def with_namespace(nss)
    nss = [nss] unless nss.respond_to?(:each)
    nss.each do |ns|
      yield ::NamespaceSuite.new(self, ns)
    end
  end
  def perform(expected_result, description, api_call)
    new_api_call = api_call.merge({user: username, password: password})
    target.perform(expected_result, "#{description} as #{label}", new_api_call)
  end
  def fedora
    target.fedora
  end
end

class NamespaceSuite < Suite
  attr_reader :target, :ns, :pid
  def self.count_cache
    @@count_cache ||= {}
  end
  def initialize(target, namespace)
    @target = target
    @ns = namespace
    @pid = make_next_object_in_sequence("#{ns}:test")
  end
  def perform(expected_result, description, api_call)
    if api_call[:command] =~ /\$PID/
      api_call = api_call.clone
      api_call[:command] = api_call[:command].gsub(/\$PID/, pid)
    end
    target.perform(expected_result, "#{description} in #{ns}", api_call)
  end
  private
  def make_next_object_in_sequence(basename)
    count = NamespaceSuite.count_cache.fetch(basename, 0)
    loop do
      trial_name = "#{basename}#{count}"
      if target.fedora.try_create_object(trial_name)
        NamespaceSuite.count_cache[basename] = count + 1
        return trial_name
      end
      count += 1
      break if count > 1000   # arbitrary limit. prevent endless loop
    end
    raise "Serious problem making object #{basename}*"
  end
end


# The list of every url we with to test. Some API points may be listed more than once
# if we want to test variations on the parameters.
# Each url may contain an optional '$PID' which is expanded to be the object pid

# run tests!

# The API end points we wish to test, with similar ones grouped together

@describeRepositoryLite = [{label: "describeRepositoryLite",
                           command: "describe"}
]
@api_read_only_no_object = [
  {label: "findObjectsLite",
   command: "search?query=pid%7E*&pid=true"},
  {label: "findObjects",
   command: "objects?query=pid%7E*&pid=true"}
]
@api_read_only = [
  {label: "getObjectHistoryLite", command: "getObjectHistory/$PID"},
  {label: "getObjectProfileLite", command: "get/$PID"},
  {label: "listMethodsLite",      command: "listMethods/$PID?xml=true"},
  {label: "getDatastreamDisseminationLite", command: "get/$PID/DC"},
  {label: "listDatastreamsLite",  command: "listDatastreams/$PID?xml=true"},
  {label: "getObjectHistory",     command: "objects/$PID/versions?format=xml"},
  {label: "getObjectProfile",     command: "objects/$PID?format=xml"},
  {label: "listMethods",          command: "objects/$PID/methods?format=xml"},
  {label: "getDatastreamDissemination", command: "objects/$PID/datastreams/DC/content"},
  {label: "listDatastreams",      command: "objects/$PID/datastreams?format=xml"},
  {label: "export",               command: "objects/$PID/export"},
  {label: "getDatastream",        command: "objects/$PID/datastreams/DC?format=xml"},
  {label: "getDatastreamHistory", command: "objects/$PID/datastreams/DC/history?format=xml"},
  {label: "getDatastreams",       command: "objects/$PID/datastreams?profiles=true"},
  {label: "getObjectXML",         command: "objects/$PID/objectXML"},
  {label: "getRelationships",     command: "objects/$PID/relationships"},
  {label: "validate",             command: "objects/$PID/validate"}
]
@api_modify_no_object = [
  {label: "getNextPIDLite",       command: "management/getNextPID?xml=true"},
  {label: "getNextPID",           command: "objects/nextPID", method: :post}
]
@api_modify = [
  {label: "addDatastream",
   command: "objects/$PID/datastreams/test?controlGroup=M&dsLabel=test&checksumType=SHA-256&mimeType=text/plain",
   method: :post,
   post_data: "some-content"},
  {label: "addRelationship",
   command: "objects/$PID/relationships/new?predicate=http%3a%2f%2fwww.example.org%2frels%2fname&object=dublin%20core&isLiteral=true",
   method: :post},
  {label: "modifyDatastream",     command: "objects/$PID/datastreams/test?dsLabel=test-changed", method: :put},
  {label: "modifyObject",         command: "objects/$PID?label=test--new%20label", method: :put},
  {label: "setDatastreamVersionable",
   command: "objects/$PID/datastreams/test?versionable=true",
   method: :put},
  {label: "setDatastreamState",   command: "objects/$PID/datastreams/test?dsState=I", method: :put}
]
@api_oai = [{label: "oaiIdentify", command: "oai?verb=Identify"}]
@api_purge = [
  {label: "purgeDatastream",      command: "objects/$PID/datastreams/test", method: :delete},
  {label: "purgeObject",          command: "objects/$PID", method: :delete}
]
@api_softdelete = [
  # Fedora bug? cannot set the datastream state to D...think the xacml policy is confusing
  # the current ds state with the new ds state
  #should_only_work_admin "setDatastreamState D #{prefix}" "objects/#{prefix}:#{noid}/datastreams/test?dsState=D" put
  #should_not_work "get D datastream #{prefix}" "objects/#{prefix}:#{noid}/datastreams/test/content"
  # put the object in a D state and try to access
  {label: "set object to D state",command: "objects/$PID?state=D", method: :put}
]
@api_readsoftdelete = [
  {label: "get D object",         command: "objects/$PID?format=xml"},
  {label: "get ds from D object", command: "objects/$PID/datastreams/test"},
]

# unimplemented API tests:
#
# resumeFindObjectsLite # not implemented
# uploadFileLite # not implemented
# describeRepository # This entry has not been implemented by Fedora
# resumeFindObjects # not implemented
# getDissemination # not implemented
# compareDatastreamChecksum # not implemented
# ingest # not implemented
# purgeRelationship # not implemented
# upload # not implemented
#

# we need to take into account every tuple of (user, namespace, api_point)
# TODO: add code which tracks each tuple tested, and knows which are missed
TestSuite.with_fedora("localhost", "8983", "fedoraAdmin", "fedoraAdmin") do |fedora|
  special_prefixes = %w(ARCH-SEASIDE CATHOLLIC-PAMPHLET CYL LAPOP NDU RBSC- VIDEO-CONTENT)
  deletable_prefixes = %w(ARCH-SEASIDE CATHOLLIC-PAMPHLET CYL LAPOP RBSC- VIDEO-CONTENT)
  all_prefixes = %w(changeme) + special_prefixes

  fedora.as_users([{label: "anonymous", username: nil, password: nil},
                   {label: "Anon User", username: "Anonymous", password: "Anonymous"}]) do |user|
    user.should_work @describeRepositoryLite
    user.should_not_work @api_read_only_no_object
    user.should_not_work @api_modify_no_object
    user.should_not_work @api_oai
    user.with_namespace("changeme") do |ns|
      ns.should_not_work @api_read_only
      ns.should_not_work @api_modify
      ns.should_not_work @api_purge
      ns.should_not_work @api_softdelete
    end
    # Must also enable listDatastreams to get the API-A version of
    # getDatastreamDissemination to work (seems related to fedora commons jira issue FCREPO-703)
    # The API-A-LITE version of getDatastreamDissemination doesn't have this problem
    access_exceptions = ["getDatastreamDisseminationLite",
                         "listDatastreamsLite",
                         "getDatastreamDissemination",
                         "listDatastreams"]
    legacy_api_ok = @api_read_only.select    { |x| access_exceptions.include?(x[:label]) }
    legacy_api_notok = @api_read_only.reject { |x| access_exceptions.include?(x[:label]) }
    user.with_namespace(special_prefixes) do |ns|
      ns.should_work legacy_api_ok
      ns.should_not_work legacy_api_notok
      ns.should_not_work @api_modify
      ns.should_not_work @api_purge
      ns.should_not_work @api_softdelete
    end
  end

  fedora.as_user("Reader", "fedoraReader", "fedoraReader") do |user|
    user.should_work @describeRepositoryLite
    user.should_work @api_read_only_no_object
    user.should_not_work @api_modify_no_object
    user.should_not_work @api_oai
    user.with_namespace(all_prefixes) do |ns|
      ns.should_work @api_read_only
      ns.should_not_work @api_modify
      ns.should_not_work @api_purge
      ns.should_not_work @api_softdelete
    end
  end

  fedora.as_user("Admin", "fedoraAdmin", "fedoraAdmin") do |user|
    user.should_work @describeRepositoryLite
    user.should_work @api_read_only_no_object
    user.should_work @api_modify_no_object
    user.should_not_work @api_oai
    user.with_namespace(all_prefixes) do |ns|
      ns.should_work @api_read_only
      ns.should_work @api_modify
      if deletable_prefixes.include?(ns.ns)
        ns.should_work @api_purge
      else
        ns.should_not_work @api_purge
        ns.should_work @api_softdelete
        ns.should_not_work @api_readsoftdelete
      end
    end
  end

  fedora.as_user("Destroyer", "reaper", "reaper") do |user|
    user.should_work @describeRepositoryLite
    user.should_work @api_read_only_no_object
    user.should_work @api_modify_no_object
    user.should_not_work @api_oai
    user.with_namespace(all_prefixes) do |ns|
      ns.should_work @api_read_only
      ns.should_work @api_modify
      # should be able to delete soft deleted items
      ns.should_work @api_softdelete
      ns.should_work @api_readsoftdelete
      ns.should_work @api_purge
    end
  end
end

