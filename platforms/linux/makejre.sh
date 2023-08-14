#!/bin/bash -e
#===============================================================================
#
# Generates a Java runtime environment that may include JavaFX modules
#
# Parameters:
#
#   output-kind
#     The kind of archive that will be generated: one of { tar.gz, zip }.
#
#   output-directory
#     The location of the directory to which the JRE will be written.  The
#     pathname must include a parent directory.
#       Two JRE archives will be created from the output directory in the parent
#     directory of the output directory.  If <output-directory-name> is the name
#     of the output directory, the filenames of the two archives will be:
#         <output-directory-name>-linux.<output-kind>
#         <output-directory-name>-linux-src.<output-kind>
#     The output directory will be deleted after the two JRE archives are
#     successfully created.
#
#   jdk-archive
#     The location of the .tar.gz archive of the JDK that will provide modules,
#     the linker and the source archive.
#
#   javafx-jmods-archive | 'null'
#     The location of the .zip archive of the JavaFX JMOD files.  If this
#     argument has the value 'null', it will be ignored.
#
#   module-list-file
#     The location of the text file in which each non-empty line is the name of
#     a module that will be included in the JRE.
#
#   copy-list-file (optional)
#     The location of the text file in which each line specifies a file that
#     will be copied to a directory in the JRE.  A line must have the form:
#         <source-file>;<destination-directory>
#     The destination directory must be relative to the output directory (see
#     above).  Any whitespace before or after the ';' separator will be ignored.
#
#===============================================================================

# Output kind
if [ -z $1 ]; then
	echo "ERROR: no output kind was specified."
	exit 1
fi
if [ $1 != "tar.gz" ] && [ $1 != "zip" ]; then
	echo "ERROR: the output kind must be one of { tar.gz, zip }."
	exit 1
fi
outKind=$1

# Output directory
if [ -z $2 ]; then
	echo "ERROR: no output directory was specified."
	exit 1
fi
outDir=$2

# Parent of output directory
outParentDir="$(dirname "${outDir}")"
if [ ${outParentDir} == "." ]; then
	echo "ERROR: the pathname of the output directory must include a parent."
	exit 1
fi

# Name of output directory
outDirName="$(basename "${outDir}")"

# JDK archive
if [ -z $3 ]; then
	echo "ERROR: no JDK archive was specified."
	exit 1
fi
jdkArchive=$3
if [ ! -f ${jdkArchive} ]; then
	echo "ERROR: no JDK archive was found at ${jdkArchive}"
	exit 1
fi

# JavaFX JMODs archive
if [ -z $4 ]; then
	echo "ERROR: no JavaFX JMODs archive was specified."
	exit 1
fi
if [ $4 != "null" ]; then
	jfxJmodsArchive=$4
	if [ ! -f ${jfxJmodsArchive} ]; then
		echo "ERROR: no JavaFX JMODs archive was found at ${jfxJmodsArchive}"
		exit 1
	fi
fi

# Module-list file
if [ -z $5 ]; then
	echo "ERROR: no module-list file was specified."
	exit 1
fi
moduleList=$5
if [ ! -f ${moduleList} ]; then
	echo "ERROR: no module-list file was found at ${moduleList}"
	exit 1
fi

# Copy-list file
if [ $6 ]; then
	copyList=$6
	if [ ! -f ${copyList} ]; then
		echo "ERROR: no copy-list file was found at ${copyList}"
		exit 1
	fi
fi

# Create comma-separated list of modules from lines of module-list file
echo "Reading module list: ${moduleList}"
modules=$(cat ${moduleList} | tr '\n' ',' | sed 's/,\+/,/g' | sed 's/^,//' | sed 's/,$//')

# Create first temporary directory
temp1Dir="${outParentDir}/\$temp-jdk\$"
[ -d ${temp1Dir} ] && rm --recursive --force "${temp1Dir}"
echo "Creating temporary directory: ${temp1Dir}"
mkdir --parents "${temp1Dir}"

# Extract JDK
echo "Extracting JDK from ${jdkArchive} to ${temp1Dir}"
tar --extract --directory="${temp1Dir}" --file="${jdkArchive}"

# JDK directory
jdkDir=${temp1Dir}/$(ls -1 ${temp1Dir})

# Module path
modulePath="${jdkDir}/jmods"

# Extract JavaFX JMODs
if [ -v jfxJmodsArchive ]; then
	# Create second temporary directory
	temp2Dir="${outParentDir}/\$temp-jfx\$"
	[ -d ${temp2Dir} ] && rm --recursive --force "${temp2Dir}"
	echo "Creating temporary directory: ${temp2Dir}"
	mkdir --parents "${temp2Dir}"

	# Extract JavaFX JMODs
	echo "Extracting JavaFX JMODs from ${jfxJmodsArchive} to ${temp2Dir}"
	unzip -q -d "${temp2Dir}" "${jfxJmodsArchive}"

	# JavaFX JMODs directory
	jfxJmodsDir=${temp2Dir}/$(ls -1 ${temp2Dir})

	# Append to module path
	modulePath="${modulePath}:${jfxJmodsDir}"
fi

# Location of jlink tool
linker="${jdkDir}/bin/jlink"

# Delete output directory
[ -d ${outDir} ] && rm --recursive --force "${outDir}"

# Generate JRE
echo "Writing JRE to ${outDir}"
"${linker}" --output="${outDir}" --module-path="${modulePath}" --add-modules=${modules}

# Copy files to JRE
if [ -v copyList ]; then
	IFS=$";"
	while read -r source dest
	do
		if [ -z ${dest} ]; then
			echo "ERROR: malformed line in copy list: ${source}"
			exit 1
		fi
		source="$(echo "${source}" | tr -d '[:space:]')"
		dest="${outDir}/$(echo "${dest}" | tr -d '[:space:]')"
		echo "Copying ${source} to ${dest}"
		cp "${source}" "${dest}"
	done < "${copyList}"
fi

# Delete archive, no source
archiveName="${outDirName}-linux.${outKind}"
archive="${outParentDir}/${archiveName}"
[ -f ${archive} ] && rm --force "${archive}"

# Create archive, no source
echo "Creating JRE archive: ${archive}"
if [ ${outKind} == "tar.gz" ]; then
	tar --create --directory="${outParentDir}" --file="${archive}" --owner=0 --group=0 --gzip "${outDirName}"
else
	pushd "${outParentDir}" > /dev/null
	zip --quiet --recurse-paths "${archiveName}" "${outDirName}"
	popd > /dev/null
fi

# Copy source archive to JRE
cp "${jdkDir}/lib/src.zip" "${outDir}/lib"

# Delete archive, source
archiveName="${outDirName}-linux-src.${outKind}"
archive="${outParentDir}/${archiveName}"
[ -f ${archive} ] && rm --force "${archive}"

# Create archive, source
echo "Creating JRE archive: ${archive}"
if [ ${outKind} == "tar.gz" ]; then
	tar --create --directory="${outParentDir}" --file="${archive}" --owner=0 --group=0 --gzip "${outDirName}"
else
	pushd "${outParentDir}" > /dev/null
	zip --quiet --recurse-paths "${archiveName}" "${outDirName}"
	popd > /dev/null
fi

# Delete temporary directories and output directory
echo "Deleting temporary directory: ${temp1Dir}"
rm --recursive --force "${temp1Dir}"
if [ ${temp2Dir} ] && [ -d ${temp2Dir} ]; then
	echo "Deleting temporary directory: ${temp2Dir}"
	rm --recursive --force "${temp2Dir}"
fi
echo "Deleting output directory: ${outDir}"
rm --recursive --force "${outDir}"

#-------------------------------------------------------------------------------
