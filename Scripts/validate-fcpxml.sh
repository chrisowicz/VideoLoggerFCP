#!/bin/sh
set -eu
if [ "$#" -ne 2 ]; then
    echo 'Usage: sh Scripts/validate-fcpxml.sh /path/FCPXMLv1_9.dtd /path/export.fcpxml' >&2
    exit 2
fi
if [ ! -f "$1" ] || [ ! -f "$2" ]; then
    echo 'DTD or FCPXML file does not exist.' >&2
    exit 2
fi
# libxml 2.9 on macOS rejects a raw DTD path with spaces. Use an unchanged
# temporary copy at a safe path; the original DTD and media are never modified.
validation_directory=$(/usr/bin/mktemp -d /tmp/videologger-dtd.XXXXXX)
trap '/bin/rm -f "$validation_directory/schema.dtd"; /bin/rmdir "$validation_directory"' EXIT
/bin/cat < "$1" > "$validation_directory/schema.dtd"
/usr/bin/xmllint --nonet --noout --dtdvalid "$validation_directory/schema.dtd" "$2"
