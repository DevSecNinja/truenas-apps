#!/usr/bin/env bats
# Unit tests for get_project_image_info.

load '../helpers/common.bash'

setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }

@test "get_project_image_info: returns empty when no containers match" {
    create_mock docker 0 ""

    run get_project_image_info "plex"
    assert_success
    assert_output ""
}

@test "get_project_image_info: returns sorted service=image lines for containers" {
    create_mock_script docker '
case "$*" in
    *"ps -aq"*) echo "c1"; echo "c2" ;;
    *"inspect"*)
        # Emit two lines out-of-order to confirm final sort.
        echo "web=myimg:2"
        echo "api=myimg:1"
        ;;
    *) : ;;
esac
'

    run get_project_image_info "myapp"
    assert_success
    # Sorted alphabetically by service.
    assert_output --partial "api=myimg:1"
    assert_output --partial "web=myimg:2"
    # Ordering: api must come before web.
    local api_line web_line
    api_line=$(echo "${output}" | grep -n '^api=' | cut -d: -f1)
    web_line=$(echo "${output}" | grep -n '^web=' | cut -d: -f1)
    [ "${api_line}" -lt "${web_line}" ]
}
