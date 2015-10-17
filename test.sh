#!/bin/bash

SWARM="dca1"

# repos with integration tests
# add to $TESTS to add more integration tests
# these repos will be pulled so we can run the tests in them
# TODO: break these up so we can pick which tests to run based on what was pushed to
# (ie. mindy/mint-client tests dont need to run when js is updated)
TEST_MINT_CLIENT=("github.com/eris-ltd/mint-client" "DOCKER/eris-cli/build.sh")
TEST_MINDY=("github.com/eris-ltd/mindy" "test/porcelain/build.sh")

# each pair is serialized into a string
TESTS=(
	"${TEST_MINT_CLIENT[@]}"
	"${TEST_MINDY[@]}" 
)

ATTRS_PER_TEST=2 # each test should have a repo and a build script

# one for each integration test plus the native test for the repo
# this is how many docker-machines we'll start
n_TESTS=`expr ${#TESTS[@]} / $ATTRS_PER_TEST`
N_TESTS=$((n_TESTS + 1)) 

# do any preliminary setup for integrations tests
# like rebuilding docker images with new code
# NOTE: these need to run on each machine
# NOTE: this is a place for custom options for each repo. Don't forget to pull a repo that's not present
# TODO: move this to each params.sh
setupForTests(){
	case $TOOL in
	"eris-cli" )  # installed already by circle
		;;
	"mint-client" )  
		git clone https://github.com/eris-ltd/eris-db $GOPATH/src/github.com/eris-ltd/eris-db
		cd $GOPATH/src/github.com/eris-ltd/eris-db
		docker build -t eris/erisdb:$ERIS_VERISON -f ./DOCKER/Dockerfile .
		;; 
	"eris-db" )  cd $GOPATH/src/github.com/eris-ltd/eris-db; docker build -t eris/erisdb:$ERIS_VERISON -f ./DOCKER/Dockerfile .
		;;
	"eris-db.js" )  # ?
		;;  
	"eris-contracts.js" )  # ?
		;;
	*) 	echo "must specify a valid TOOL. Got: $TOOL."
		;;
	esac
}

export -f setupForTests

# ----------------------------------------------------------------------------
# Functions we'll need for checking machines/swarms and running the tests

# so we can launch machines in parallel
declare -A launch_procs
declare -A launch_results	

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
    launch_results[$proc]=$?
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
	# NOTE: names starting with an integer cause trouble
	cat /dev/urandom | tr -dc 'a-zA-Z' | fold -w 8 | head -n 1
}

ifExit(){
	if [ $? -ne 0 ]; then
		echo "ifExit"
		echo "$1"
		exit 1
	fi
}

export -f ifExit


# create_connect_machine(machine_name)
create_connect_machine(){
	create_machine $1
	connect_machine $1
}

connect_machine(){
	echo "* connecting to machine $1"
	eval $(docker-machine env $1)
	ifExit "failed to connect to $1"
}

export -f connect_machine

create_machine(){
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


export RESULTS_FILE=$HOME/integration-tests-results
touch $RESULTS_FILE

# params (machine, test_exit)
log_results() {
  if [ "$2" -eq 0 ]
  then
    echo "$1 is Green!" >> $RESULTS_FILE
  else
    "$1 is Red. :(" >> $RESULTS_FILE
  fi
}

export -f log_results

# ----------------------------------------------------------------------------
# 				START
# ----------------------------------------------------------------------------
# Read args and set parameters

machine_definitions=matDef

if [ "$#" -lt 1 ]; then
	    echo "Must provide at least the location of the test folder"
fi

test_folder=`readlink -f $1` # get full path
machine=$2 # either "local", a machine in the matdef, or empty to create a new one

# sourcing params.sh gives us:
# - $base
# - $build_script
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


export TOOL=$(basename $base)
export REPO_TO_TEST=$base

# create an id for log files for this run
logID=$(rand8)
logFolder="$HOME/integration_test_logs/eris_integration_tests_$logID"

LOG_CONFIG=/etc/log_files.yml

cd $repo

# ---------------------------------------------------------------------------
# Get the machine definitions, connect to one, build the images

echo ""
echo "Hello! I'm the testing suite for eris."
echo "My job is to provision docker machines from circle ci and to run tests in docker containers on them."
echo "You pushed to $REPO_TO_TEST. Let's run its tests!"
echo ""

echo "First thing first, create log folder ($logFolder) and run a docker container to forward logs to papertrail:"
mkdir -p $logFolder
docker run -d --name papertrail -v $logFolder:/test_logs quay.io/eris/papertrail 
echo ""

# if this is the integrations branch, we spawn multiple machines in parallel.
# otherwise, just one
BRANCH=`git rev-parse --abbrev-ref HEAD`

if [ "$BRANCH" == "$integration_tests_branch" ]; then
	echo "We're on an integration test branch ($BRANCH)."

	TEST_AGAINST_BRANCH=$integration_test_against_branch
	if [[ "$TEST_AGAINST_BRANCH" == "" ]]; then
		TEST_AGAINST_BRANCH="master"
	fi

	echo "Integration tests will run against $TEST_AGAINST_BRANCH. Fetching repos ..."

	# grab all the repos except the one we're testing (use n_TESTS)
	for i in `seq 1 $n_TESTS` 
	do
		j=`expr $((i - 1)) \* 2` # index into quasi-multi-D-array
		nextRepo=${TESTS[$j]}
		if [ "$nextRepo" != "$REPO_TO_TEST" ];  then
			wd=$GOPATH/src/$nextRepo
			git clone https://$nextRepo $wd
			cd $wd; git checkout $TEST_AGAINST_BRANCH
		fi
	done

	echo "Done fetching repos for integration tests"
	echo ""

	# optionally specify machines to run the tests on
	machs=(${@:2})
	if [[ "$machs" != "" ]]; then
		# if machs are given, there must be enough of them
		if [[ "${#machs[@]}" != $N_TESTS ]]; then
			echo "if machines are specified, there must be enough to run all the tests. got ${#machs[@]}, required $N_TESTS"
			exit 1
		fi

		machines=(${machs[@]})
		echo "Using given machines: ${machines[@]}"
	else
		NEW_MACHINE=true
		# launch one machine for each test
		echo "Launching one machine for each of the $N_TESTS tests:"
			echo " - $REPO_TO_TEST $build_script" # print repo and build script
		for i in `seq 1 $n_TESTS`; do 
			j=`expr $((i - 1)) \* 2` # index into quasi-multi-D-array
			k=`expr $((i - 1)) \* 2 + 1`  # index into quasi-multi-D-array
			echo " - ${TESTS[$j]}: ${TESTS[$k]}" # print repo and build script
		done

		for i in `seq 1 $N_TESTS`;
		do
			if [[ "$i" -ne 1 ]]; then
				j=`expr $((i - 2)) \* 2` # index into quasi-multi-D-array
				thisRepo="${TESTS[$j]}"
				base=$(basename $thisRepo)
			else
				base="$TOOL-local" # for the repos own tests
			fi
			MACHINE_INDEX=$(rand8)
			machine="eris-test-$SWARM-$base-$MACHINE_INDEX"
			create_machine $machine &
			set_procs $machine
			echo "... initialized machine creation for $machine"
		done 
		echo "Waiting for machines to start ..."
		wait_procs
		check_procs
		if [[ $? -ne 0 ]]; then
			echo "Error starting a machine. Removing machines ..."
			for mach in "${launch_procs[@]}"; do
				docker-machine rm -f $mach
			done
			exit 1
		fi
		echo "All machines started!"
		machines=(${!launch_procs[@]})
		clear_procs
		echo "Done launching machines"
	fi

	# fetch the run_test.sh script 
	echo ""
	echo "Fetching run_test.sh script for individual tests"
	curl https://raw.githubusercontent.com/eris-ltd/integration-tests/master/run_test.sh > $HOME/run_test.sh
	echo ""

	echo "Run a test with each machine (${machines[@]})"

	# now loop over all the machines and run a test on each one
	# the first machine gets the local test, all others get an integrations test from $TESTS
	i=0
	for mach in "${machines[@]}"
	do
		echo "Running test $i with machine $mach"
		# everything gets logged into files watched by papertrail
		if [[ $i -ne 0 ]]; then
			j=`expr $((i - 1)) \* 2` # index into quasi-multi-D-array
			k=`expr $((i - 1)) \* 2 + 1` # index into quasi-multi-D-array
			thisRepo="${TESTS[$j]}"
			build_script="${TESTS[$k]}"
			bash $HOME/run_test.sh "integration" $mach $thisRepo $build_script $logFolder &
			set_procs $i
		else
			bash $HOME/run_test.sh "local" $mach $repo/$build_script $logFolder &
			set_procs $i
		fi
		i=$((i+1))
	done
	echo "Waiting for all tests to finish ..."
	wait_procs # this will wait for all to finish, but we should really die as soon as something fails
	echo "All tests finished"
	check_procs
	#if [[ $? -ne 0 ]]; then
	#	a test failed. it's caught at the end
	#fi
else 
	# no integration tests to run, just launch a machine and run the local test
	echo "We're not on an integration branch. Just run the local tests ..."

	if [[ $machine == "" ]]; then
		NEW_MACHINE="true"

		MACHINE_INDEX=$(rand8)
		base=$(basename $repo)
		machine="eris-test-$SWARM-$base-$MACHINE_INDEX"
		create_connect_machine $machine
		machines=( $machine )
		echo "Succesfully created and connected to new docker machine: $machine"
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
cat $RESULTS_FILE | grep Red # precarious but the best we can do
if [[ "$?" == "1" ]]; then
    test_exit=0
else
    test_exit=1
fi

cat $RESULTS_FILE

rm $RESULTS_FILE

echo ""
echo ""
if [[ "$NEW_MACHINE" == "true" ]];
then
	for mach in ${machines[@]}; do
		echo "Removing $mach"
		docker-machine rm -f $mach
		ifExit "error removing machine $mach"
	done
	echo ""
	echo ""
fi

docker stop papertrail > /dev/null
docker rm -v papertrail > /dev/null


if [[ "$test_exit" == "1" ]]; then
	echo "Done. Some tests failed."
elif [[ "$test_exit" == "0" ]]; then
	echo "Done. All tests passed."
else
	echo "WOOPS!"
fi
cd $strt
exit $test_exit
