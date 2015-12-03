#! /bin/bash

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

# one for each integration test plus the native test for the repo
n_TESTS=`expr ${#TESTS[@]} / $N_ATTRS`
if [[ "$TEST_SCRIPT" != "" ]]; then
	N_TESTS=$((n_TESTS + 1)) 
else
	N_TESTS=$n_TESTS
fi

source $INTEGRATION_TESTS_PATH/util.sh

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

	echo ""
	echo ""
}


echo "The following integration tests will run"
if [[ "$TEST_SCRIPT" != "" ]]; then
	echo " - $REPO_TO_TEST $TEST_SCRIPT" # print repo and build script
fi
for i in `seq 1 $n_TESTS`; do 
	j=`expr $((i - 1)) \* $N_ATTRS` # index into quasi-multi-D-array
	k=`expr $((i - 1)) \* $N_ATTRS + 1`  # index into quasi-multi-D-array
	echo " - ${TESTS[$j]}: ${TESTS[$k]}" # print repo and build script
done

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


start_connect_machine $MACHINE

echo "* run pre events for $TOOL"
setupForTests #&> "$LOG_FOLDER/$TOOL-setup"

# first run the local tests if we have them
if [[ "$TEST_SCRIPT" != "" ]]; then
	echo "First, run the local tests"
	bash $INTEGRATION_TESTS_PATH/run_test.sh "local" $MACHINE $REPO $TEST_SCRIPT $LOG_FOLDER
fi

# now the integration tests
echo "Run the integration tests"
for i in `seq 1 $n_TESTS`; do
	j=`expr $((i - 1)) \* $N_ATTRS + 1` # index into quasi-multi-D-array
	k=`expr $((i - 1)) \* $N_ATTRS + 2` # index into quasi-multi-D-array
	test_script="${TESTS[$j]}"
	thisRepo="${TESTS[$k]}"
	bash $INTEGRATION_TESTS_PATH/run_test.sh "integration" $MACHINE $thisRepo $test_script $LOG_FOLDER
done
