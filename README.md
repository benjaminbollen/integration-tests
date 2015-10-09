# integration-tests

This repo provides shell scripts for two testing goals:

1) use circle-ci for automated testing but manage the docker machines ourselves 

2) run a suite of cross-repository tests when a repo pushes to a "staging" branch (possibly just "develop")


For (1), include the following in your circle.yml

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
    - curl https://raw.githubusercontent.com/eris-ltd/integration-tests/master/test.sh | bash -s $REPO/tests
```

Here we are fetching the `test.sh` script from this repo and running it on the `tests` folder in our repo, where `$REPO` is the full path (presumably on the GOPATH) to our repo.

The tests folder should have everything required for running your tests. In addition, it must contain a `params.sh` file looking like:

```
# a name for our client tool
export client_tool=eris

# path in the GOPATH
export base=github.com/eris-ltd/eris-cli

# a script which will build all docker containers needed for testing, including a test container itself
export build_script=tests/build_tool.sh 

# image to use for the testing container, and its entrypoint
export testimage=quay.io/eris/eris
export testuser=eris
export entrypoint="/home/eris/test_tool.sh" 

export machine_results=()
export docker_versions18=( "1.8.2" )

# Primary swarm of backend machines -- uncomment out second line to use the secondary swarm
#   if/when the primary swarm is either too slow or non-responsive. Swarms here are really
#   data centers. These boxes are on Digital Ocean.
swarm_prim="dca1"
swarm_back="fra1"

# additional params for connecting to docker
export remotesocket=2376
export localsocket=/var/run/docker.sock
export machine_definitions=matDef
```








