#!/bin/sh -e

case "${MODE}" in
    "import")
        # echo "do import"
        exec ./sync-env.sh -v $@
    ;;
    "export")
        # echo "do export"
        exec ./backup-script.sh -v $@
    ;;
    "")
        echo "do CMD/command"
        exec $@
    ;;
    *)
        echo "not valid"
    ;;
esac
