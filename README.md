# integration-tests

This repo provides shell scripts for two testing goals:

1) use circle-ci to boot docker machines and run tests on them

2) run a suite of cross-repository tests when certain repos push to a "staging" branch 

We assume repos that want to run integration tests have their own tests to run along with the integration tests,
and that these will also run using our provisioned docker machine/s. 

The local tests run regardless of the branch being pushed to, and run before the integration tests when pushing to `staging`.

# Parameterization

Options for testing should be specified as environment variables in the circle.yml.

Variables that _must_ be specified include:

```
machine:
  environment:
    REPO: $GOPATH/src/github.com/eris-ltd/mindy # full path to the repository 
    BUILD_SCRIPT: test/plumbing/build.sh # test script for the repo's local test (relative to $REPO)
    INTEGRATION_TESTS_PATH: $HOME/integration-tests # where the integration-tests repo should be cloned to
```

Testing with docker-machine
---------------------------

To manage docker machines yourself, add the following to your circle.yml.

```
dependencies:
  override:
    - sudo curl -L -o /usr/bin/docker http://s3-external-1.amazonaws.com/circle-downloads/docker-$DOCKER_VERSION-circleci; chmod 0755 /usr/bin/docker; true
    - sudo service docker start
    - docker login -e $DOCKER_EMAIL -u $DOCKER_USER -p $DOCKER_PASS quay.io
    - "sudo curl -sSL -o /usr/local/bin/docker-machine https://github.com/docker/machine/releases/download/v$DOCKER_MACHINE_VERSION/docker-machine_linux-amd64 && sudo chmod +x /usr/local/bin/docker-machine"
```

You can set all the `$DOCKER` variables in your admin panel for the repo on circleci.com. 

Now, to actually run your tests using your docker machines,

```
test:
  override:
    - git clone https://github.com/eris-ltd/integration-tests $HOME/integration-tests
    - bash $INTEGRATION_TESTS_PATH/test.sh $MACHINE_NAME
```

In this case, we wish to use machine `$MACHINE_NAME`. If the machine name is left empty, a new one will be provisioned.

To ensure provisioning of new docker machines works, the following environment variables must be set through the admin panels on circlci.com:

```
AWS_ACCESS_KEY_ID
AWS_DEFAULT_REGION
AWS_SECRET_ACCESS_KEY
AWS_SECURITY_GROUP
AWS_VPC_ID
```

The machine will be torn down once the test completes.

Integration tests with docker-machine
-------------------------------------

When any of some set of repositories is pushed to a `staging` branch (possibly `develop`), we would like to run a set of tests, spanning across multiple repos.

The tests that will be run can be found at the top of `test.sh`. To run these tests when pushing to the `staging` branch, add the following to the environment variables in circle.yml:

```
INTEGRATION_TESTS_BRANCH: staging
```

Of course you can replace `staging` by anything. If the variable is blank, no integration tests will be run.

You can also specify the branch all other repos should be on for the integrations test by setting `INTEGRATION_TEST_AGAINST_BRANCH`.
