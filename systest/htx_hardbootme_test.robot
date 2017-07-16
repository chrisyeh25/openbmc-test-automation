*** Settings ***

Documentation  Stress the system using HTX exerciser.

# Test Parameters:
# OPENBMC_HOST        The BMC host name or IP address.
# OS_HOST             The OS host name or IP Address.
# OS_USERNAME         The OS login userid (usually root).
# OS_PASSWORD         The password for the OS login.
# HTX_DURATION        Duration of HTX run, for example, 8 hours, or
#                     30 minutes.
# HTX_LOOP            The number of times to loop HTX.
# HTX_INTERVAL        The time delay between consecutive checks of HTX
#                     status, for example, 30s.
#                     In summary: Run HTX for $HTX_DURATION, looping
#                     $HTX_LOOP times checking every $HTX_INTERVAL.
# HTX_KEEP_RUNNING    If set to 1, this indicates that the HTX is to
#                     continue running after an error.
# CHECK_INVENTORY     If set to 1, this enables OS inventory checking
#                     before and after each HTX run.  This parameter
#                     is optional.
# PREV_INV_FILE_PATH  The file path and name of a previous inventory
#                     snapshot file.  After HTX start the system inventory
#                     is compared to the contents of this file.  Setting this
#                     parameter is optional.  CHECK_INVENTORY does not
#                     need to be set if PREV_INV_FILE_PATH is set.

Resource        ../syslib/utils_os.robot
Library         ../syslib/utils_keywords.py

Suite Setup     Run Key  Start SOL Console Logging
Test Setup      Pre Test Case Execution
Test Teardown   Post Test Case Execution

*** Variables ****

${stack_mode}                skip
${json_initial_file_path}    ${EXECDIR}/data/os_inventory_initial.json
${json_final_file_path}      ${EXECDIR}/data/os_inventory_final.json
${json_diff_file_path}       ${EXECDIR}/data/os_inventory_diff.json
${last_inventory_file_path}  ${EMPTY}
${run_the_inventory}         0
&{ignore_dict}               processor=size

*** Test Cases ***

Hard Bootme Test
    [Documentation]  Stress the system using HTX exerciser.
    [Tags]  Hard_Bootme_Test

    Rprintn
    Rpvars  HTX_DURATION  HTX_INTERVAL

    # Set last inventory file to PREV_INV_FILE_PATH otherwise set
    # it to ${EMPTY}.
    ${last_inventory_file_path}=  Get Variable Value  ${PREV_INV_FILE_PATH}
    ...  ${EMPTY}

    # Set ${run_the_inventory} if PREV_INV_FILE_PATH was specified,
    # else set ${run_the_inventory} from the ${CHECK_INVENTORY} parameter.
    ${run_the_inventory}=  Run Keyword If
    ...  '${last_inventory_file_path}' != '${EMPTY}'  Set Variable  ${1}
    ...  ELSE  Run Keyword If  '${last_inventory_file_path}' == '${EMPTY}'
    ...  Get Variable Value  ${CHECK_INVENTORY}  ${EMPTY}

    Set Suite Variable  ${run_the_inventory}  children=true
    Set Suite Variable  ${last_inventory_file_path}  children=true

    Repeat Keyword  ${HTX_LOOP} times  Run HTX Exerciser


*** Keywords ***

Run HTX Exerciser
    [Documentation]  Run HTX exerciser.
    # Test Flow:
    # - Power on.
    # - Establish SSH connection session.
    # - Do inventory collection, compare with
    #   previous inventory run if applicable.
    # - Create HTX mdt profile.
    # - Run HTX exerciser.
    # - Check HTX status for errors.
    # - Do inventory collection, compare with
    #   previous inventory run.
    # - Power off.

    Boot To OS

    # Post Power off and on, the OS SSH session needs to be established.
    Login To OS

    Run Keyword If  '${run_the_inventory}' != '${EMPTY}'
    ...  Do Inventory And Compare  ${json_initial_file_path}
    ...  ${last_inventory_file_path}

    Run Keyword If  '${HTX_MDT_PROFILE}' == 'mdt.bu'
    ...  Create Default MDT Profile

    Run MDT Profile

    Loop HTX Health Check

    Shutdown HTX Exerciser

    Run Keyword If  '${run_the_inventory}' != '${EMPTY}'
    ...  Do Inventory And Compare  ${json_final_file_path}
    ...  ${last_inventory_file_path}

    Power Off Host

    # Close all SSH and REST active sessions.
    Close All Connections
    Flush REST Sessions

    Rprint Timen  HTX Test ran for: ${HTX_DURATION}


Do Inventory and Compare
    [Documentation]  Do inventory and compare.
    [Arguments]  ${inventory_file_path}  ${last_inventory_file_path}
    # Description of argument(s):
    # inventory_file_path        The file to receive the inventory snapshot.
    # last_inventory_file_path   The previous inventory to compare with.

    Create JSON Inventory File  ${inventory_file_path}
    Run Keyword If  '${last_inventory_file_path}' != '${EMPTY}'
    ...  Compare Json Inventory Files  ${inventory_file_path}
    ...  ${last_inventory_file_path}
    ${last_inventory_file_path}=   Set Variable  ${inventory_file_path}
    Set Suite Variable  ${last_inventory_file_path}  children=true


Compare Json Inventory Files
    [Documentation]  Compare JSON inventory files.
    [Arguments]  ${file1}  ${file2}
    # Description of argument(s):
    # file1   A file that has an inventory snapshot in JSON format.
    # file2   A file that has an inventory snapshot, to compare with file1.

    ${diff_rc}=  JSON_Inv_File_Diff_Check  ${file1}
     ...  ${file2}  ${json_diff_file_path}  ${ignore_dict}
    Run Keyword If  '${diff_rc}' != '${0}'
    ...  Report Inventory Mismatch  ${diff_rc}  ${json_diff_file_path}


Report Inventory Mismatch
    [Documentation]  Report inventory mismatch.
    [Arguments]  ${diff_rc}  ${json_diff_file_path}
    # Description of argument(s):
    # diff_rc              The failing return code from the difference check.
    # json_diff_file_path  The file that has the latest inventory snapshot.

    Log To Console  Difference in inventory found, return code:
    ...  no_newline=true
    Log to Console  ${diff_rc}
    Log to Console  Differences are listed in file:  no_newline=true
    Log to Console  ${json_diff_file_path}
    Fail  Inventory mismatch, rc=${diff_rc}


Loop HTX Health Check
    [Documentation]  Run until HTX exerciser fails.
    Repeat Keyword  ${HTX_DURATION}
    ...  Run Keywords  Check HTX Run Status
    ...  AND  Sleep  ${HTX_INTERVAL}


Post Test Case Execution
    [Documentation]  Do the post test teardown.
    # 1. Shut down HTX exerciser if test Failed.
    # 2. Capture FFDC on test failure.
    # 3. Close all open SSH connections.

    # Keep HTX running if user set HTX_KEEP_RUNNING to 1.
    Run Keyword If
    ...  '${TEST_STATUS}' == 'FAIL' and ${HTX_KEEP_RUNNING} == ${0}
    ...  Shutdown HTX Exerciser

    ${keyword_buf}=  Catenate  Stop SOL Console Logging
    ...  \ targ_file_path=${EXECDIR}${/}logs${/}SOL.log
    Run Key  ${keyword_buf}

    FFDC On Test Case Fail
    Close All Connections
