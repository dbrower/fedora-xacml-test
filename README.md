fedora-xacml-test
=================

Test [XACML][] policies for the [Fedora Commons][fedora] 3.6 REST API.

This code was developed for our particular installation, but it should be
adaptable to others. Our setup is complicated since the access policy depends
on the user as well as the namespace of the target PID. In addition, we have an
extremely restrictive XACML setup. Almost nothing is permitted to the anonymous
user, with some exceptions for legacy objects.

  [XACML]: https://www.oasis-open.org/committees/tc_home.php?wg_abbrev=xacml
  [fedora]: http://fedora-commons.org/

How to use
----------

The exact setup depends on your Fedora installation. If you are using the
fedora in [Hydra-Jetty][], let `$JETTY_HOME` point to the base directory of your
checkout. The test script is written in Ruby, and requires the `rest-client`
gem. It was tested using Ruby 1.9.3. If you have trouble getting it to run on
some other version, or if you do get it to run on a different version, I would
like to hear about it.

  [Hydra-Jetty]: https://github.com/projecthydra/hydra-jetty

 1. Copy `fedora-users.xml` to `$JETTY_HOME/fedora/default/server/config`
 2. Remove `$JETTY_HOME/fedora/default/data/fedora-xacml-policies/repository-policies`
 2. Copy `repository-policies` to `$JETTY_HOME/fedora/default/data/fedora-xacml-policies`
 3. Run `bundle install` to update the gems this depends on
 4. Run `test.rb`

You will see output similar to the following.

    1) describeRepositoryLite as anonymous... (worked) pass
    2) findObjectsLite as anonymous... (rejected) pass
    3) findObjects as anonymous... (rejected) pass
    4) getNextPIDLite as anonymous... (rejected) pass
    5) getNextPID as anonymous... (rejected) pass
    6) oaiIdentify as anonymous... (rejected) pass
    Creating object changeme:test118
    7) getObjectHistoryLite in changeme as anonymous... (rejected) pass
    8) getObjectProfileLite in changeme as anonymous... (rejected) pass
    9) listMethodsLite in changeme as anonymous... (rejected) pass
    10) getDatastreamDisseminationLite in changeme as anonymous... (rejected) pass
    11) listDatastreamsLite in changeme as anonymous... (rejected) pass
    12) getObjectHistory in changeme as anonymous... (rejected) pass

    [ ... snip ...]

    1078) setDatastreamVersionable in VIDEO-CONTENT as Destroyer... (worked) pass
    1079) setDatastreamState in VIDEO-CONTENT as Destroyer... (worked) pass
    1080) set object to D state in VIDEO-CONTENT as Destroyer... (worked) pass
    1081) get D object in VIDEO-CONTENT as Destroyer... (worked) pass
    1082) get ds from D object in VIDEO-CONTENT as Destroyer... (worked) pass
    1083) purgeDatastream in VIDEO-CONTENT as Destroyer... (worked) pass
    1084) purgeObject in VIDEO-CONTENT as Destroyer... (worked) pass
    ====================
    1084 tests:
     1084 Successes
     0 Failures

The framework will make dummy objects as necessary to do the tests. The output
above shows the creation of the object `changeme:test118`. Each dummy object
name has the form `[prefix]:test[integer]`. The default test suite will create
about 40 dummy objects and takes about 15 seconds to run.


Writing Tests
-------------

The test framework and the tests themselves are all included in the `test.rb` file.
An individual test first gives the URL and port of the Fedora instance to connect to,
along with an admin user and password. The admin information is used to create the
dummy objects.
The tests are then scoped by user, and then by object namespace.
One can think of each test as being essentially a triple of _(API endpoint, user, object namespace)_, for which we state
whether it should work (return an HTTP status codes of `200` or `201`) or not work (return status codes
`400`, `401`, or `403`).

The API endpoints are described by giving each one a `label`; a url command to use, for which and occurences of `$PID` are repaced by the current dummy object identifier; an optional HTTP `method` to use; and even `post_data` for data to transmit in the request body.
An illustrative example is the list of API endpoints which may modify a Fedora object.

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

We do not aim to test every permutation of options to the endpoint.
The goal is only to test whether the operation is allowed or denied.

The API endpoint list is actually invoked after a user had been identified.
The following is a sample test for the admin user.
Note that the dummy object is created in the `with_namespace` method.

    TestSuite.with_fedora("localhost", "8983", "fedoraAdmin", "fedoraAdmin") do |fedora|
      special_prefixes = %w(ARCH-SEASIDE CATHOLLIC-PAMPHLET CYL LAPOP NDU RBSC- VIDEO-CONTENT)
      deletable_prefixes = %w(ARCH-SEASIDE CATHOLLIC-PAMPHLET CYL LAPOP RBSC- VIDEO-CONTENT)
      all_prefixes = %w(changeme) + special_prefixes

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
    end


Fedora Bugs
-----------

In the process of developing these tests, several Fedora bugs were found. Since
Fedora development has moved to the [Fedora Futures project][futures], I don't
expect them to be fixed, which is fine. However, the knowledge of them may be
useful if a legacy 3.6 API should be created in Fedora 4.0.

 1. The API endpoint `describeRepository` is listed in the documentation, but is not implemented.
 2. Access to the endpoint `getDatastreamDissemination` depends on `listDatastreams`, so both must be enabled in the XACML policy. The problem does not manifest when using the deprecated `getDatastreamDisseminationLite`. This seems to be related to the issue [FCREPO-703][].
 3. There seems to be a problem with setting a datastream state from `A` to `D` when access to `D` datastreams is forbidden. It appears the XACML engine is confusing the current datastream state with the new datastream state.
 4. In some tests a `400` HTTP response code was received instead of (the expected) `401` code. These were tests related to the `reader` user.

  [futures]: https://github.com/futures/fcrepo4
  [FCREPO-703]: https://jira.duraspace.org/browse/FCREPO-703

API Endpoints Tested and Untested
---------------------------------

The name listed is the name given in the [Fedora API documentation][fedora-doc].
The endpoints come from both the API-A and API-M groups as well as the
deprecated API-Lite group.

  [fedora-doc]: https://wiki.duraspace.org/display/FEDORA36/REST+API

 * addDatastream
 * addRelationship
 * describeRepositoryLite
 * export
 * findObjects
 * findObjectsLite
 * getDatastream
 * getDatastreamDissemination
 * getDatastreamDisseminationLite
 * getDatastreamHistory
 * getDatastreams
 * getNextPID
 * getNextPIDLite
 * getObjectHistory
 * getObjectHistoryLite
 * getObjectProfile
 * getObjectProfileLite
 * getObjectXML
 * getRelationships
 * listDatastreams
 * listDatastreamsLite
 * listMethods
 * listMethodsLite
 * modifyDatastream
 * modifyObject
 * purgeDatastream
 * purgeObject
 * setDatastreamState
 * setDatastreamVersionable
 * validate

These API endpoints were not tested.
One, `describeRepository`, is because Fedora does not implement this endpoint which is described in its documentation.
The others are from a lack of time.

 * compareDatastreamChecksum
 * describeRepository -- This entry has not been implemented by Fedora
 * getDissemination
 * ingest
 * purgeRelationship
 * resumeFindObjects
 * resumeFindObjectsLite
 * upload
 * uploadFileLite

Contributions
-------------

Contributions and correspondence are welcome.

Contact
-------
Don Brower  
`dbrower@nd.edu`  
[Hesburgh Libraries](http://library.nd.edu)  
[University of Notre Dame](http://nd.edu)  
