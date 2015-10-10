#!/bin/bash

SWARM="dca1"

# repos with integration tests
# add repos+build scripts here to add more integration tests
# TODO: break these up so we can pick which tests to run based on what was pushed to
# (ie. mindy/mint-client tests dont need to run when js is updated)
TEST_MINT_CLIENT=("github.com/eris-ltd/mint-client" "DOCKER/eris-cli/build.sh")
TEST_MINDY=("github.com/eris-ltd/mindy" "test/porcelain/build.sh")
TESTS=(
	$TEST_MINT_CLIENT	
	$TEST_MINDY
)

N_TESTS=`expr ${#TESTS[@]} + 1` # one for each integration test plus the native test for the repo


# do any preliminary setup for integrations tests
# TODO: these need to run on each machine
setupForTests(){
	case $REPO_TO_TEST in
	"eris-cli" )  # installed already by circle
		;;
	"mint-client" )  cd $GOPATH/src/github.com/eris-ltd/eris-db; docker build -t eris/erisdb:$ERIS_VERISON -f ./DOCKER/Dockerfile .
		;; 
	"eris-db" )  cd $GOPATH/src/github.com/eris-ltd/eris-db; docker build -t eris/erisdb:$ERIS_VERISON -f ./DOCKER/Dockerfile .
		;;
	"eris-db.js" )  # ?
		;;  
	"eris-contracts.js" )  # ?
		;;
	*) 	echo "must specify a valid REPO_TO_TEST. Got: $REPO_TO_TEST."
		;;
	esac
}

# ----------------------------------------------------------------------------
# Functions we'll need for checking machines/swarms and running the tests

# so we can launch machines in parallel
declare -a launch_procs
declare -a launch_results	

clear_procs() {
  launch_procs=()
  launch_results=()
}

set_procs() {
  launch_procs[$1]=$!
}

wait_procs() {
  for proc in "${!launch_procs[@]}"
  do
    wait ${launch_procs[$proc]}
    results[$proc]=$?
  done
}

check_procs() {
  for res in "${!launch_results[@]}"
  do
    if [ ${launch_results[$res]} -ne 0 ]
    then
      return 1
    fi
  done
  return 0
}

rand8(){
	cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1
}

ifExit(){
	if [ $? -ne 0 ]; then
		echo "ifExit"
		echo "$1"
		exit 1
	fi
}


# create_connect_machine(machine_name)
create_connect_machine(){
	create_machine $1
	connect_machine $1
}

connect_machine(){
	echo "Machine started. Connecting ..."
	eval $(docker-machine env $1)
	ifExit "failed to connect to $1"
}

create_machine(){
	echo "Create new machine named $1"
	docker-machine create --driver amazonec2 $1
	ifExit "failed to create new machine $1"
}

connect() {
  echo "Starting Machine."
  docker-machine start $machine 1>/dev/null
  until [[ $(docker-machine status $machine) == "Running" ]] || [ $ping_times -eq 10 ]
  do
     ping_times=$[$ping_times +1]
     sleep 3
  done
  if [[ $(docker-machine status $machine) != "Running" ]]
  then
    echo "Could not start the machine. Exiting this test."
    exit 1
  else
    echo "Machine Started."
    docker-machine regenerate-certs -f $machine 2>/dev/null
  fi
  sleep 5
  echo "Connecting to Machine."
  eval "$(docker-machine env $machine)" &>/dev/null
  echo "Connected to Machine."
  echo ""
  clear_stuff
}

clear_stuff() {
  echo "Clearing images and containers."
  set +e
  docker rm $(docker ps -a -q) &>/dev/null
  docker rmi $(docker images -q) &>/dev/null
  set -e
  echo ""
}


set_machine() {
  echo "eris-test-$swarm-$ver"
}

check_swarm() {
  machine=$(set_machine)

  if [[ $(docker-machine status $machine) == "Running" ]]
  then
    echo "Machine Running. Switching Swarm."
    if [[ "$swarm" == "$swarm_back" ]]
    then
      swarm=$swarm_prim
    else
      swarm=$swarm_back
    fi

    machine=$(set_machine)
    if [[ $(docker-machine status $machine) == "Running" ]]
    then
      echo "Backup Swarm Machine Also Running."
      return 1
    fi
  else
    echo "Machine not Running. Keeping Swarm."
    machine=$(set_machine)
  fi
}

reset_swarm() {
  swarm=$swarm_prim
}

log_results() {
  if [ "$test_exit" -eq 0 ]
  then
    machine_results=("$machine is Green!")
  else
    machine_results=("$machine is Red.  :(")
  fi
}

# runIntegrationTest(testID, log folder)
runIntegrationTest(){
    setupForTests

    test=${TESTS[$1]}
    repo=$GOPATH/src/${test[0]}
    build_script=${test[1]}
    echo ""
    echo "Building tests for $repo on $machine"
    strt=`pwd`
    cd $repo
    # build and run the tests
    basename=$(basename $repo)
    $build_script > $2/$basename

    # logging the exit code
    test_exit=$(echo $?)
    log_results # TODO communicate which test this is
}

# runLocalTest(build_script)
runLocalTest(){
    setupForTests

    build_script=$1
    $build_script
}

# ----------------------------------------------------------------------------
# Read args and set parameters

machine_definitions=matDef

if [ "$#" -lt 1 ]; then
	    echo "Must provide at least the location of the test folder"
fi

test_folder=$1
machine=$2 # either "local", a machine in the matdef, or empty to create a new one

source $test_folder/params.sh

# ----------------------------------------------------------------------------
# Set definitions and defaults

# Where are the Things 
if [ "$CIRCLE_BRANCH" ]
then
  repo=${GOPATH%%:*}/src/github.com/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}
  circle=true
else
  repo=$GOPATH/src/$base
  circle=false
fi
branch=${CIRCLE_BRANCH:=master}
branch=${branch/-/_}


# ---------------------------------------------------------------------------
# Get the machine definitions, connect to one, build the images

echo "Hello! I'm the testing suite for eris."
echo "My job is to provision docker machines from circle ci and to run tests in docker containers on them."


if [[ $machine == "" ]]; then
	NEW_MACHINE="true"

	# if this is the integrations branch, we spawn multiple machines in parallel.
	# otherwise, just one
	BRANCH=`git rev-parse --abbrev-ref HEAD`
	if [ "$BRANCH" == "$integration_tests_branch" ]; then
		TEST_AGAINST_BRANCH=$integration_test_against_branch
		if [[ "$TEST_AGAINST_BRANCH" == "" ]]; then
			TEST_AGAINST_BRANCH="master"
		fi

		# grab all the repos except the one we're testing
		for rtest in "${TESTS[@]}"
		do
			repo=${rtest[0]}
			if [ "$repo" != "$REPO_TO_TEST" ];  then
				wd=$GOPATH/src/$repo
				git clone https://$repo $wd
				cd $wd; git checkout $TEST_AGAINST_BRANCH
			fi
		done


		# launch one machine for each test
		for i in `seq 1 N_TESTS`;
		do
			MACHINE_INDEX=rand8
			machine="eris-test-$SWARM-$MACHINE_INDEX"
			create_machine $machine &
			set_procs $machine
		done 
		wait_procs
		check_procs
		if [[ $? -ne 0 ]]; then
			# TODO: remove machines that did start and exit
		fi
		machines=${launch_procs[@]}
		clear_procs

		# create an id for log files for this run
		logID=rand8
		logFolder=/var/log/eris_integration_tests_$logID
		mkdir -p $logFolder

		# now loop over all the machines and run a test on each one
		# the first machine gets the local test, all others get an integrations test from $TESTS
		i=0
		for mach in "${!machines[@]}"
		do
			if [[ $i -ne 0 ]]; then
				# the integration tests get logged into files watched by papertrail
				runIntegrationTest $i $logFolder &
				set_procs $i
			else
				# the base test gets logged in circle
				runLocalTest $build_script &
				set_procs $i
			fi
			i=$((i+1))
	    	done
		wait_procs # this will wait for all to finish, but we should really die as soon as something fails
		check_procs
		if [[ $? -ne 0 ]]; then
			# TODO: remove machines that did start and exit
		fi
	else 
		# no integration tests to run, just launch a machine and run the local test
		MACHINE_INDEX=rand8
		machine="eris-test-$SWARM-$MACHINE_INDEX"
		create_connect_machine $machine
		echo "Succesfully created and connected to new docker machine: $machine"

		echo ""
		echo "Building tests for $repo on $machine"
		strt=`pwd`
		cd $repo
		# build and run the tests
		$build_script 

		# logging the exit code
		test_exit=$(echo $?)
		log_results
	fi
else
	# we run the tests in sequence on our local docker or on some specified machine
	# this is not meant to run on circle

	if [[ $machine != "local" ]]; then
		echo "Getting machine definition files sorted so we can connect to $2"
		if [ "$circle" = true ]; then
		  docker pull quay.io/eris/test_machines &>/dev/null
		  docker run --name $machine_definitions quay.io/eris/test_machines &>/dev/null
		  rm -rf .docker &>/dev/null
		  docker cp $machine_definitions:/home/eris/.docker $HOME &>/dev/null
		else
		  docker run --name $machine_definitions quay.io/eris/test_machines &>/dev/null
		fi

		eval $(docker-machine env $2)
	fi

	echo ""
	echo "Building tests for $repo"
	strt=`pwd`
	cd $repo
	# build and run the tests
	$build_script 

	# logging the exit code
	test_exit=$(echo $?)
	log_results
fi

# ---------------------------------------------------------------------------
# Cleaning up

echo ""
echo ""
echo "Your summary good human...."
printf '%s\n' "${machine_results[@]}"
echo ""
echo ""
if [[ "$NEW_MACHINE" == "true" ]];
then
	for mach in ${machines[@]}; do
		echo "Removing $mach"
		docker-machine rm $mach
		ifExit "error removing machine $mach"
	done
	echo ""
	echo ""
fi
echo "Done. Exiting with code: $test_exit"
cd $strt
exit $test_exit
