#!/bin/bash

# This file is part of the simpler pkg installer creation (https://github.com/daggs1/simple_pkg_installer).
# Copyright (c) 2021 Dagg (daggs@gmx.com).
# 
# This program is free software: you can redistribute it and/or modify  
# it under the terms of the GNU General Public License as published by  
# the Free Software Foundation, version 2.
#
# This program is distributed in the hope that it will be useful, but 
# WITHOUT ANY WARRANTY; without even the implied warranty of 
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU 
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

# @version: 1.0

entries_to_pack=()
declare -A additiona_payload
post_install_exec=
work_path=
payload_prefix=">>>>> "
payload_suffix=" <<<<<"
payload_marker="payload"
utils_list="rm mktemp cp ln tar cat mv chmod echo cut basename grep printf bzip2"

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

which 2>&1 | grep -q Usage
if [ $? -ne 0 ]; then
	error which is needed but not found!
fi

for util in $(echo ${utils_list}); do
	which ${util} > /dev/null
	if [ $? -ne 0 ]; then
		error utils ${util} is needed but not found!
	fi
done

while getopts ":s:f:p:" opt; do
	case ${opt} in
		p)
			if [ ! -f "${OPTARG}" -o ! -x "${OPTARG}" ]; then
				error ${OPTARG} must be an executable file
			fi

			post_install_exec="${OPTARG}"
			entries_to_pack+=( ${post_install_exec} )
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

if [ ! -z "${post_install_exec}" ]; then
	ln -s $(basename ${post_install_exec}) post_install
	installer_content+=( post_install )
fi

tar -c ${installer_content[@]} | bzip2 > payload0
cp payload0 ${OLDPWD}
additiona_payload[0]=payload0
cat << EOF > ${final_installer_name}
#!/bin/bash

payload_start=()
payload_name=()
utils_list="rm mktemp mkdir egrep cut sed wc head tar echo bzip2"

which 2>&1 | egrep -q Usage
if [ \$? -ne 0 ]; then
	echo "which is needed but not found!"
	exit 1
fi

for util in \$(echo \${utils_list}); do
	which \${util} > /dev/null
	if [ \$? -ne 0 ]; then
		echo "utils \${util} is needed but not found!"
		exit 1
	fi
done

OLDIFS=\${IFS}
IFS=\$'\n'

work_path=\$(mktemp -d /tmp/tmp.XXXXXXXXXX)
mkdir -p \${work_path}/payloads
for ent in \$(egrep -an "^${payload_prefix}${payload_marker} [0-9]{3}${payload_suffix}\$" \$0 | sed "s/:${payload_prefix}/ /g;s/${payload_suffix}\$//g"); do
	payload_start+=( \$(echo \${ent} | cut -f 1 -d ' ') )
	payload_name+=( \$(echo \${ent} | cut -f 3 -d ' ') )
done

payload_start+=( \$((\$(wc -l \$0 | cut -f 1 -d ' ')+1)) )

for i in "\${!payload_name[@]}"; do
	next_idx=\$((\${i}+1))
	start=\$((\${payload_start[\${i}]}+1))
	end=\$((\${payload_start[\${next_idx}]}-1))
	dst=\${work_path}/payloads/\${payload_name[\${i}]}
	sed -n "\${start},\${end}p;\${end}q" \$0 | head -c -1 > \${dst}
done

bzip2 -dc \${work_path}/payloads/000 | tar -x -C \${work_path}
cd \${work_path}
if [ -e post_install ]; then
	./post_install
fi
cd - > /dev/null

rm -rf \${work_path}
exit 0
EOF

for pid in "${!additiona_payload[@]}"; do
	echo -e "\n${payload_prefix}${payload_marker} $(printf "%03d" ${pid})${payload_suffix}" >> ${final_installer_name}
	cat ${final_installer_name} ${additiona_payload[$pid]} >> ${final_installer_name}.tmp || error failed to append payload
	mv ${final_installer_name}.tmp ${final_installer_name}
done

echo >> ${final_installer_name}
chmod 755 ${final_installer_name}

cd - > /dev/null

rm -rf ${work_path}
