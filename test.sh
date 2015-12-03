#!/bin/bash

export SWARM="dca1"

# Read args and check required vars

export MACHINE=$1 # either "local", a machine in the matdef, or empty to create a new one


if [[ "$REPO" == "" ]]; then
	echo "must specify full path to the repo in $REPO"
	exit 1
fi

if [[ "$INTEGRATION_TESTS_PATH" == "" ]]; then
	echo "must specify full path to the integrations-test repo"
	exit 1
fi

# if this is the integrations test, we have more tests to run
cd $REPO
BRANCH=`git rev-parse --abbrev-ref HEAD`

# if its not integrations testing branch and we have no test_script, there's nothing to do!
if [[ "$BRANCH" != "$INTEGRATION_TESTS_BRANCH" && "$TEST_SCRIPT" == "" ]]; then
	echo "Not an integrations-test branch ($BRANCH) and no local TEST_SCRIPT. Nothing to do."
	exit 0
fi

# ----------------------------------------------------------------------------
# Set some important and exported variables

export RESULTS_FILE=$HOME/integration-tests-results
touch $RESULTS_FILE

# grab utility functions
source $INTEGRATION_TESTS_PATH/util.sh

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
	export LOG_FOLDER="$CIRCLE_ARTIFACTS"
else
	export LOG_FOLDER="$HOME/integration_test_logs/eris_integration_tests_$MACHINE_INDEX"
fi

LOG_CONFIG=/etc/log_files.yml


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
		export INTEGRATION_TEST_AGAINST_BRANCH="master"
	fi

	# optionally specify machine to run the tests on
	if [[ "$MACHINE" != "" ]]; then
		echo "Using given machine: $MACHINE"
		echo "Grabbing machine definition files"
		if [ "$IN_CIRCLE" = true ]; then
		  docker pull quay.io/eris/test_machines &>/dev/null
		  docker run --name $machine_definitions quay.io/eris/test_machines &>/dev/null
		  rm -rf .docker &>/dev/null
		  docker cp $machine_definitions:/home/eris/.docker $HOME &>/dev/null
		else
		  docker run --name $machine_definitions quay.io/eris/test_machines &>/dev/null
		fi

		# XXX: test_machines expect /home/eris, so we overwrite the config
		find $HOME/.docker/machine -type f -name "config.json" -exec sed -i "s/home\/eris/home\/$USER/g" {} +
		bash $INTEGRATION_TESTS_PATH/fetch_connect_run.sh
	else
		NEW_MACHINE=true
		
		echo "Launching a machine to run the tests"

		MACHINE="eris-test-$SWARM-it-$TOOL-$MACHINE_INDEX"
		create_machine $MACHINE
		echo "Done launching machine"

		# fetch necessary repos, connect to machine, run the tests
		bash $INTEGRATION_TESTS_PATH/fetch_connect_run.sh
	fi

else 
	# no integration tests to run, just launch a machine and run the local test
	echo "We are not an integration branch ($BRANCH). Just run the local tests"

	if [[ $MACHINE == "" ]]; then
		NEW_MACHINE="true"

		MACHINE="eris-test-$SWARM-$TOOL-$MACHINE_INDEX"
		create_connect_machine $MACHINE
		echo "Succesfully created and connected to new docker machine: $MACHINE"
	else
		# we run the tests in sequence on our local docker or on some specified machine

		if [[ "$MACHINE" != "local" ]]; then
			echo "Getting machine definition files sorted so we can connect to $MACHINE"
			if [ "$IN_CIRCLE" = true ]; then
			  docker pull quay.io/eris/test_machines &>/dev/null
			  docker run --name $machine_definitions quay.io/eris/test_machines &>/dev/null
			  rm -rf .docker &>/dev/null
			  docker cp $machine_definitions:/home/eris/.docker $HOME &>/dev/null
			else
			  docker run --name $machine_definitions quay.io/eris/test_machines &>/dev/null
			fi

			eval $(docker-machine env $MACHINE)
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
	echo "Removing $MACHINE"
	docker-machine rm -f $MACHINE
	ifExit "error removing machine $MACHINE"
	echo ""
	echo ""
fi

#docker stop papertrail > /dev/null
#docker rm -v papertrail > /dev/null


if [[ "$test_exit" == "1" ]]; then
	echo "Done. Some tests failed."
elif [[ "$test_exit" == "0" ]]; then
	echo "Done. All tests passed."
else
	echo "WOOPS!"
fi
cd $strt
exit $test_exit
