#!/bin/bash -x

entries_to_pack=()
declare -A additiona_payload
post_install_exec=
work_path=

function usage {
	echo "usage: $(basename $0) [-f ... ] [-s .... ] [-p file] <installer name>"
	echo "       -f file1,file2,file3,..,fileN - list of files to add to the installer"
	echo "       -s ###:file1,###:file2,###:file3,..,###:fileN - list of addtional payload files to append to the"
	echo "          end of the installer, the ### is a uniqe payload ID starting from 1"
	echo "       -p file - post install script"
	echo "       <installer name> - the file installer name"
}

function error {
	echo "$*"

	if [ -e "${work_path}" ]; then
		rm -rf "${work_path}"
	fi

	exit 1
}

while getopts ":s:f:p:" opt; do
	case ${opt} in
		p)
			if [ ! -f "${OPTARG}" -o ! -x "${OPTARG}" ]; then
				error ${OPTARG} must be an executable file
			fi
echo ${entries_to_pack[@]}
			post_install_exec="${OPTARG}"
			entries_to_pack+=( ${post_install_exec} )
			echo ${LINENO}:${entries_to_pack[@]}
		;;

		s)
			for payload in $(echo ${OPTARG} | tr ',' '\n'); do
				pid=$(echo "${payload}" | cut -f 1 -d :)
				pname=$(echo "${payload}" | cut -f 2 -d :)
				additiona_payload[${pid}]=${pname}
			done
		;;

		f)
			for entry in $(echo ${OPTARG} | tr ',' '\n'); do
				entries_to_pack+=( ${entry} )
			done
		;;

		\?)
			usage
			exit 1
		;;
	esac
done
echo ${LINENO}:${entries_to_pack}
shift $((OPTIND-1))
if [ -z "$1" ]; then
	error installer name is missing
fi
final_installer_name="${PWD}/$1.sh"

installer_content=()
work_path=$(mktemp -d /tmp/tmp.XXXXXXXXXX)
for entry in ${entries_to_pack[@]}; do
	cp -r ${entry} ${work_path} || error failed to copy ${entry} into ${work_path}
	installer_content+=( $(basename ${entry}) )
done

cd ${work_path}
tar cjf payload0 ${installer_content}
additiona_payload[0]=payload0
cat << EOF > ${final_installer_name}
\$!/bin/bash -x

work_path=\$(mktemp -d /tmp/tmp.XXXXXXXXXX)

rm -rf \${work_path}
EOF

for pid in "${!additiona_payload[@]}"; do
	echo ">>>>> payload $(printf "%03d" ${pid}) <<<<<" >> ${final_installer_name}
	cat ${additiona_payload[$pid]} >> ${final_installer_name} || error failed to append payload
done

cd - > /dev/null

rm -rf ${work_path}
