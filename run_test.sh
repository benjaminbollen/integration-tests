#! /bin/bash

# this exists as its own script because it needs isolated environment variables for connecting to docker

# runIntegrationTest(machine, testID, log folder)
runIntegrationTest(){
    echo "Running integration test on $1"
    connect_machine $1

    setupForTests

    test=${TESTS[$2]}
    thisRepo=$GOPATH/src/${test[0]}
    build_script=${test[1]}
    echo ""
    echo "Building tests for $thisRepo on $machine"
    strt=`pwd`
    cd $thisRepo
    # build and run the tests
    base=$(basename $thisRepo)
    $build_script > $3/$base

    # logging the exit code
    test_exit=$(echo $?)
    log_results # TODO communicate which test this is
}

# runLocalTest(machine, build_script)
runLocalTest(){
    echo "Running local test on $1"
    connect_machine $1

    setupForTests

    build_script=$2 > "$3/$(basename $repo)-local"
    $build_script
}

# params
# ("integration", <machine>, <test index>, <logFolder>)
# or ("local", <machine>, <path to build script>)

if [[ "$1" == "integration" ]]; then
	runIntegrationTest $2 $3 $4
elif [[ "$1" == "local" ]]; then
	runLocalTest $2 $3
else
	echo "unknown test type: $1. must be 'integration' or 'local'"
	exit 1
fi
