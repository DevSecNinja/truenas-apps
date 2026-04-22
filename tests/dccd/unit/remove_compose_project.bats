#!/usr/bin/env bats
# Unit tests for remove_compose_project.

load '../helpers/common.bash'

setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }

@test "remove_compose_project: no-op when no containers match" {
    # docker ps -aq returns empty → "no containers found" + return 0.
    create_mock docker 0 ""

    run remove_compose_project "someproject"
    assert_success
    assert_output --partial "No containers found for project 'someproject'"
}

@test "remove_compose_project: stops + removes containers and networks when present" {
    # Always succeed; first invocation returns container IDs, subsequent
    # invocations can return networks or empty. We keep it simple by always
    # returning non-empty output so all branches execute.
    create_mock_script docker '
case "$*" in
    *"ps -aq"*) echo "c1"; echo "c2" ;;
    *"network ls"*) echo "net1" ;;
    *) : ;;
esac
'

    run remove_compose_project "myproject"
    assert_success
    assert_output --partial "Stopping and removing containers for project 'myproject'"
    assert_output --partial "Project 'myproject' cleaned up"

    # Verify docker was invoked for stop and rm.
    run mock_calls docker
    assert_output --partial "stop"
    assert_output --partial "rm -f"
}

@test "remove_compose_project: survives docker stop/rm failures (|| true)" {
    # docker returns IDs on ps -aq, fails on stop/rm — function must still succeed.
    create_mock_script docker '
case "$*" in
    *"ps -aq"*) echo "c1" ;;
    *"stop"*|*"rm -f"*) exit 1 ;;
    *"network ls"*) echo "" ;;
    *) : ;;
esac
'

    run remove_compose_project "myproject"
    assert_success
}
