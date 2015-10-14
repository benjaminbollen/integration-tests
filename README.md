# integration-tests

This repo provides shell scripts for two testing goals:

1) use circle-ci to boot docker machines and run tests on them

2) run a suite of cross-repository tests when certain repos push to a "staging" branch 

We assume repos that want to run integration tests have their own tests to run along with the integration tests,
and that these will also run using our provisioned docker machines. 


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

You can set all the `$DOCKER` variables in your admin panel for the repo on circleci.com. We use `quay.io` for docker images, rather than the default, `hub.docker.com`, because it's been more reliable.

Now, to actually run your tests using your docker machines,

```
test:
  override:
    - curl https://raw.githubusercontent.com/eris-ltd/integration-tests/master/test.sh > $HOME/test.sh && bash $HOME/test.sh $REPO/tests $MACHINE_NAME
```

Here we are fetching the `test.sh` script from the integration tests repo and running it on the `tests` folder in the repo we're testing, where `$REPO` is the full path (presumably on the GOPATH). `$MACHINE_NAME` is the name of the docker-machine to use, if it is already provisioned (and included in the `eris/test_machines` image). If `$MACHINE_NAME` is empty, a new machine will be provisioned. 

The tests folder should have everything required for running your tests. In addition, it must contain a `params.sh` file looking like:

```
# path in the GOPATH
export base=github.com/eris-ltd/mindy

# scripts for building containers and running dependency containers
export build_script=test/plumbing/build.sh
```

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

Details for which tests will be run can be found in `integration_tests.sh`. To run these tests when pushing to the `staging` branch, add the following to the params.sh

```
integration_tests_branch=staging
```

Of course you can replace `staging` by anything. If the variable is blank, no integration tests will be run.

You can also specify the branch all other repos should be on for the integrations test by setting `integration_test_against_branch`.
