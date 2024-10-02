#!/usr/bin/env bash

# TODO: gum prevents ctrl-c
# trap exit signals 2, 1, 15, 3
trap 'exit' SIGINT SIGHUP SIGTERM SIGQUIT

# Environment variables
USE_GUM=${USE_GUM:-true}
LOG=${LOG:-false}
LOG_DIR=${LOG_DIR:-/tmp}
LOG_FILE=${LOG_FILE:-git_heat_map.log}

# TODO: read from HELP.md
# * add to case statement for `-h` and `--help`
# Help function showing description
help() {
	cat <<- DESCRIPTION >&2
	Find out what files/directories have changed the most in a git repository.

	USAGE
		$(basename $0) [results]

	OPTIONS
		results  Number of results to display (default: 25)

	ENVIRONMENT VARIABLES
		USE_GUM  Use gum for styling (default: true)
		LOG      Log to stdout, log file, both, or false (default: false)
		LOG_DIR  Directory to store log file (default: /tmp)
		LOG_FILE Log file name (default: git_heat_map.log)

	DEPENDENCIES
		gum
	DESCRIPTION
}

# Check if a binary exists
check_bin() { command -v "$1" >/dev/null 2>&1; }

# Log messages
logger() {
	local level msg OPTIND log_file log_dir log_path
	level=""
	msg=""
	log_dir=${LOG_DIR}
	log_file=${LOG_FILE}
	log_path="${log_dir}/${log_file}"

	while getopts ":l:" opt; do
		case ${opt} in
			l )
				level=$OPTARG
				;;
			\? )
				echo "Invalid option: $OPTARG" 1>&2
				return 1
				;;
			: )
				echo "Invalid option: $OPTARG requires an argument" 1>&2
				return 1
				;;
		esac
	done
	shift $((OPTIND -1))

	msg="$1"

	# Define log_message function
	log_message() {
		local timestamp=$(date +'%d %b %y %H:%M %Z')
		if [ -n "$level" ]; then
			echo "$timestamp  $level  $msg"
		else
			echo "$timestamp  $msg"
		fi
	}

	# Function to log using gum
	gum_log() {
		local cmd
		cmd=(gum log --time rfc1123 --structured)
		case "$level" in
			"")
				cmd+=("$msg")
				;;
			"debug" | "info" | "warn" | "error" | "fatal")
				cmd+=("--level" "$level" "$msg")
				;;
			*)
				cmd+=("--level" "error" "Invalid log level: $level")
				;;
		esac
		"${cmd[@]}" 2>&1
	}

	# Check if gum is being used and set logging function
	if check_bin "gum" && [[ "$USE_GUM" = "true" ]]; then
		local_logger() { gum_log; }
	else
		local_logger() { log_message; }
	fi

	case "${LOG:-}" in
		stdout)
			local_logger
			;;
		log)
			local_logger >> "$log_path"
			;;
		both)
			local_logger | tee -a "$log_path"
			;;
		false|"")
			;;
		*)
			echo "Invalid LOG option: ${LOG}. Using 'none'." >&2
			;;
	esac
}

# Check if the current directory is a git repository
if [[ ! -d ".git" ]]; then
	echo "Not a git repository"
	exit 1
fi

# Set top-level git directory
git_dir=$(git rev-parse --show-toplevel)
logger -l info "Git repository detected at $git_dir"

# Set git icon
if fc-list | grep -qi "HackNerdFont"; then
	git_icon=''
else
	git_icon='🌱'
fi

# Style the text
gum_style() {
	gum style \
		--foreground 212 \
		--border-foreground 212 \
		--border normal \
		--margin "1 2" \
		--padding "2 3" \
		"${git_icon} git heat map" \
		'' \
		'Find out what files/directories' \
		'have changed the most.'
}

# Input placeholder and value
gum_input() {
	gum input \
		--placeholder "$1" \
		--value "$2"
}

# Confirm the input
gum_confirm() {
	local msg

	if [[ $# -ne 0 ]]; then
		msg=$1
	else
		msg='Is this correct?'
	fi

	gum confirm "$msg" \
		&& return 0 \
		|| return 1
}

# Prompt the user for input
gum_prompt() {
	local input

	# Display the styled text but discard its output
	gum_style >/dev/null

	input=$(gum_input "How many results?" "25")
	while ! gum_confirm "Is this correct?: $input"; do
		input=$(gum_input "How many results?" "25")
	done

	echo "$input"
}

# TODO: filter out removed files (i.e., 'git rm')
# Get the most changed files/directories
git_commits() {
	local results
	results="$1"

	git log --pretty=format: --name-only \
		| sed '/^$/d' \
		| sort \
		| uniq -c \
		| sort -rn \
		| head -n "$results"
}

# TODO: add newline before and after the output
# Format the output
format_output() {
	local use_gum results max_length header_changes
	local header_file separator file_length changes file

	use_gum="$1"
	results="$2"
	max_length=11

	# Calculate the maximum length of file/folder names
	while read -r line; do
		file=$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ *//')
		file_length=${#file}
		if (( file_length > max_length )); then
			max_length=$file_length
		fi
	done <<< "$results"

	# Create the header and separator
	header_changes="Changes"
	header_file="File/Folder"
	separator=$(printf '|-%s-|-%s-|\n' "$(printf -- '-%.0s' $(seq 1 7))" "$(printf -- '-%.0s' $(seq 1 $max_length))")

	if [ "$use_gum" = true ]; then
		{
			printf "## Git Heat Map Results\n\n"
			printf "| %-7s | %-${max_length}s |\n" "$header_changes" "$header_file"
			echo "$separator"
			while read -r line; do
				changes=$(echo "$line" | awk '{print $1}')
				file=$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ *//')
				printf "| %-7s | %-${max_length}s |\n" "$changes" "$file"
			done <<< "$results"
		} | gum format
	else
		printf "| %-7s | %-${max_length}s |\n" "$header_changes" "$header_file"
		echo "$separator"
		while read -r line; do
			changes=$(echo "$line" | awk '{print $1}')
			file=$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ *//')
			printf "| %-7s | %-${max_length}s |\n" "$changes" "$file"
		done <<< "$results"
	fi
}

main() {
	local results use_gum stdout

	use_gum="$USE_GUM"

	if [ "$use_gum" = true ] && ! check_bin "gum"; then
		logger -l warn "gum is not installed. Falling back to non-gum mode."
		use_gum=false
	fi

	if [[ $# -eq 1 ]]; then
		results=$1
	else
		if [ "$use_gum" = true ]; then
			results=$(gum_prompt)
		else
			echo "Error: Please provide a number (e.g., 25) of desired results"
			exit 1
		fi
	fi

	logger -l info "Fetching git commit data for $results results"
	stdout=$(git_commits "$results")

	logger -l info "Formatting output"
	format_output "$use_gum" "$stdout"

	logger -l info "Git heat map generation complete"
}

main "$@"
