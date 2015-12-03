#!/bin/bash

SWARM="dca1"

###############################
# repos with integration tests
# add to $TESTS to add more integration tests

# each test should have a remote repo, a build script, a path to clone to, and a variable that specifies the branch to checkout
# NOTE: the branch variable must be in quotes!
N_ATTRS=4

# these repos will be pulled so we can run the tests in them
# TODO: break these up so we can pick which tests to run based on what was pushed to
# (ie. mindy/mint-client tests dont need to run when js is updated)
TEST_MINT_CLIENT=("github.com/eris-ltd/mint-client" "DOCKER/eris-cli/build.sh" "$GOPATH/src/github.com/eris-ltd/mint-client" "$TEST_MINT_CLIENT_BRANCH")
TEST_MINDY=("github.com/eris-ltd/mindy" "test/porcelain/build.sh" "$GOPATH/src/github.com/eris-ltd/mindy" "$TEST_MINDY_BRANCH")

# each pair is serialized into a string
TESTS=(
	"${TEST_MINT_CLIENT[@]}"
	"${TEST_MINDY[@]}" 
)

###############################

# do any preliminary setup for integrations tests
# like rebuilding docker images with new code
# NOTE: these need to run on each machine
# NOTE: this is a place for custom options for each repo. Don't forget to pull a repo that's not present
# TODO: move this to each repo?
setupForTests(){
	case $TOOL in
	"eris-cli" )  
			# build the docker image, set the eris version
			cd $GOPATH/src/github.com/eris-ltd/eris-cli
			ERIS_VERSION=`git rev-parse --abbrev-ref HEAD`
			export ERIS_VERSION
			docker build -t quay.io/eris/eris:$ERIS_VERSION .
		;;
	"mint-client" )  
		docker pull quay.io/eris/erisdb:$ERIS_VERSION
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

create_machine(){
	docker-machine create --driver amazonec2 $1
	ifExit "failed to create new machine $1"
}

start_connect_machine() {
  echo "Starting Machine."
  docker-machine start $1 1>/dev/null
  until [[ $(docker-machine status $1) == "Running" ]] || [ $ping_times -eq 10 ]
  do
     ping_times=$[$ping_times +1]
     sleep 3
  done
  if [[ $(docker-machine status $1) != "Running" ]]
  then
    echo "Could not start the machine. Exiting this test."
    exit 1
  else
    echo "Machine Started."
    # docker-machine regenerate-certs -f $1 2>/dev/null
  fi
  sleep 5
  echo "Connecting to Machine."
  eval "$(docker-machine env $1)" &>/dev/null
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


# params (machine, test_exit)
log_results() {
  if [[ "$2" == "0" ]]
  then
    echo "$1 is Green!" >> $RESULTS_FILE
  else
    echo "$1 is Red. :(" >> $RESULTS_FILE
  fi
}

export -f log_results

# ----------------------------------------------------------------------------
# 				START
# ----------------------------------------------------------------------------
# Read args and set parameters

machine_definitions=matDef

machine=$1 # either "local", a machine in the matdef, or empty to create a new one


if [[ "$REPO" == "" ]]; then
	echo "must specify full path to the repo in $REPO"
	exit 1
fi

if [[ "$INTEGRATION_TESTS_PATH" == "" ]]; then
	echo "must specify full path to the integrations-test repo"
	exit 1
fi


# if this is the integrations test, we have more tests to run
BRANCH=`git rev-parse --abbrev-ref HEAD`

# if its not integrations testing branch and we have no test_script, there's nothing to do!
if [[ "$BRANCH" != "$INTEGRATION_TESTS_BRANCH" && "$TEST_SCRIPT" == "" ]]; then
	echo "Not an integrations-test branch ($BRANCH) and no local TEST_SCRIPT. Nothing to do."
	exit 0
fi

# ----------------------------------------------------------------------------
# Set definitions and defaults

# one for each integration test plus the native test for the repo
n_TESTS=`expr ${#TESTS[@]} / $N_ATTRS`
if [[ "$TEST_SCRIPT" != "" ]]; then
	N_TESTS=$((n_TESTS + 1)) 
else
	N_TESTS=$n_TESTS
fi

if [ "$CIRCLE_BRANCH" ]
then
  IN_CIRCLE=true
else
  IN_CIRCLE=false
fi

export TOOL=$(basename $REPO)
export REPO_TO_TEST=$TOOL

# create an id for the machine and its log files for this run
MACHINE_INDEX=$(rand8)
if [ "$CIRCLE_ARTIFACTS" ]
then
	LOG_FOLDER="$CIRCLE_ARTIFACTS"
else
	LOG_FOLDER="$HOME/integration_test_logs/eris_integration_tests_$MACHINE_INDEX"
fi


export RESULTS_FILE=$HOME/integration-tests-results
touch $RESULTS_FILE

LOG_CONFIG=/etc/log_files.yml

cd $REPO

# ---------------------------------------------------------------------------
# Go!

echo "******************"
echo "Hello! I'm the testing suite for eris."
echo "My job is to provision docker machines from circle ci and to run tests in docker containers on them."
echo "You pushed to $REPO_TO_TEST. Let's run its tests!"
echo ""

if [[ "$CIRCLE_ARTIFACTS" != "" ]]; then
	echo "Hello CIRCLE_ARTIFACTS!" > $CIRCLE_ARTIFACTS/hello
fi

#echo "First thing first, create log folder ($LOG_FOLDER) and run a docker container to forward logs to papertrail:"
#mkdir -p $LOG_FOLDER
#docker run -d --name papertrail -v $LOG_FOLDER:/test_logs quay.io/eris/papertrail 
echo ""

if [ "$BRANCH" == "$INTEGRATION_TESTS_BRANCH" ]; then
	echo "We're on an integration test branch ($BRANCH)."

	if [[ "$INTEGRATION_TEST_AGAINST_BRANCH" == "" ]]; then
		INTEGRATION_TEST_AGAINST_BRANCH="master"
	fi

	echo "Integration tests will run against $INTEGRATION_TEST_AGAINST_BRANCH. Fetching repos ..."

	# grab all the repos except the one we're testing (use n_TESTS)
	for i in `seq 1 $n_TESTS` 
	do
		j=`expr $((i - 1)) \* $N_ATTRS` # index into quasi-multi-D-array
		k=`expr $((i - 1)) \* $N_ATTRS + 2` # index into quasi-multi-D-array
		l=`expr $((i - 1)) \* $N_ATTRS + 3` # index into quasi-multi-D-array
		nextRepo=${TESTS[$j]}
		if [ "$(basename $nextRepo)" != "$REPO_TO_TEST" ];  then
			wd=${TESTS[$k]}
			mkdir -p $wd
			git clone https://$nextRepo $wd
			cd $wd
			branch=$INTEGRATION_TEST_AGAINST_BRANCH
			# if a more specific branch is given, use it
			if [[ "${TESTS[$l]}" != "" ]]; then
				branch=${TESTS[$l]}
			fi
			git checkout $branch

		fi
	done

	echo "Done fetching repos for integration tests"
	echo ""

	# optionally specify machines to run the tests on
	if [[ "$machine" != "" ]]; then
		echo "Using given machine: $machine"
		echo "Grabbing machine definition files"
		if [ "$IN_CIRCLE" = true ]; then
		  docker pull quay.io/eris/test_machines &>/dev/null
		  docker run --name $machine_definitions quay.io/eris/test_machines &>/dev/null
		  rm -rf .docker &>/dev/null
		  docker cp $machine_definitions:/home/eris/.docker $HOME &>/dev/null
		else
		  docker run --name $machine_definitions quay.io/eris/test_machines &>/dev/null
		fi

	else
		NEW_MACHINE=true
		
		echo "Launching one machine to run all $N_TESTS tests:"
		# print tests to run
		if [[ "$TEST_SCRIPT" != "" ]]; then
			echo " - $REPO_TO_TEST $TEST_SCRIPT" # print repo and build script
		fi
		for i in `seq 1 $n_TESTS`; do 
			j=`expr $((i - 1)) \* $N_ATTRS` # index into quasi-multi-D-array
			k=`expr $((i - 1)) \* $N_ATTRS + 1`  # index into quasi-multi-D-array
			echo " - ${TESTS[$j]}: ${TESTS[$k]}" # print repo and build script
		done

		machine="eris-test-$SWARM-it-$TOOL-$MACHINE_INDEX"
		create_machine $machine
		echo "Done launching machine"
	fi

	start_connect_machine $machine

	echo "* run pre events for $TOOL"
	setupForTests #&> "$LOG_FOLDER/$TOOL-setup"

	# first run the local tests if we have them
	if [[ "$TEST_SCRIPT" != "" ]]; then
		echo "First, run the local tests"
		bash $INTEGRATION_TESTS_PATH/run_test.sh "local" $machine $REPO $TEST_SCRIPT $LOG_FOLDER
	fi

	# now the integration tests
	echo "Run the integration tests"
	for ii in `seq 1 $n_TESTS`; do
		i=`expr $ii - 1`
		j=`expr $((i - 1)) \* $N_ATTRS + 1` # index into quasi-multi-D-array
		k=`expr $((i - 1)) \* $N_ATTRS + 2` # index into quasi-multi-D-array
		test_script="${TESTS[$j]}"
		thisRepo="${TESTS[$k]}"
		bash $INTEGRATION_TESTS_PATH/run_test.sh "integration" $machine $thisRepo $test_script $LOG_FOLDER
	done
else 
	# no integration tests to run, just launch a machine and run the local test
	echo "We are not an integration branch ($BRANCH). Just run the local tests"

	if [[ $machine == "" ]]; then
		NEW_MACHINE="true"

		machine="eris-test-$SWARM-$TOOL-$MACHINE_INDEX"
		create_connect_machine $machine
		machines=( $machine )
		echo "Succesfully created and connected to new docker machine: $machine"
	else
		# we run the tests in sequence on our local docker or on some specified machine

		if [[ $machine != "local" ]]; then
			echo "Getting machine definition files sorted so we can connect to $machine"
			if [ "$IN_CIRCLE" = true ]; then
			  docker pull quay.io/eris/test_machines &>/dev/null
			  docker run --name $machine_definitions quay.io/eris/test_machines &>/dev/null
			  rm -rf .docker &>/dev/null
			  docker cp $machine_definitions:/home/eris/.docker $HOME &>/dev/null
			else
			  docker run --name $machine_definitions quay.io/eris/test_machines &>/dev/null
			fi

			eval $(docker-machine env $machine)
		fi
	fi

	echo ""
	echo "Building and running tests for $TOOL"
	strt=`pwd`
	cd $REPO
	# build and run the tests
	$TEST_SCRIPT

	# logging the exit code
	test_exit=$?
	log_results "$TOOL ($TEST_SCRIPT)" $test_exit
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
#		docker-machine rm -f $mach
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
