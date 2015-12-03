#! /bin/bash

# this exists as its own script because it needs isolated environment variables for connecting to docker

test_type=$1
machine=$2
thisRepo=$3
build_script=$4
log_folder=$5
base=$(basename $thisRepo)

if [[ "$test_type" == "local" ]]; then
    echo "* local test on $mach"
    base="$base-local"
elif [[ "$test_type" == "integration" ]]; then
    echo "* integration test $base ($build_script) on machine $machine"
else
    echo "unknown test type: $test_type. must be 'integration' or 'local'"
    exit 1
fi

echo "... building/running tests for $base using $build_script"
strt=`pwd`
cd $thisRepo
# build and run the tests
$build_script &> $log_folder/$base

# logging the exit code
test_exit=$?
log_results "$base ($build_script)" $test_exit

echo " ... done tests for $base ($build_script) !"
if [[ "$test_exit" == 0 ]]; then 
    echo "****** PASS ******"
else
    echo "****** FAIL ******"
fi
echo ""

