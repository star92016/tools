for BDF in $(lspci -d "*:*:*" | awk '{print $1}'); do
    # skip if it doesn't support ACS
    if ! setpci -v -s "${BDF}" ECAP_ACS+0x6.w > /dev/null 2>&1; then
        continue
    fi

    echo "Disabling ACS on $(lspci -s "${BDF}")"
    if ! setpci -v -s "${BDF}" ECAP_ACS+0x6.w=0000 ; then
        echo "Error disabling ACS on ${BDF}"
        continue
    fi
    NEW_VAL=$(setpci -v -s "${BDF}" ECAP_ACS+0x6.w | awk '{print $NF}')
    if [ "${NEW_VAL}" != "0000" ]; then
        echo "Failed to disable ACS on ${BDF}"
        continue
    fi
done