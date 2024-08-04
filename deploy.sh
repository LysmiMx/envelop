#!/bin/sh
 
# Check if the required tools are installed
if ! command -v yq >/dev/null 2>&1; then
    echo "Required tool (yq) are not installed."
    exit 1
fi

exec 3>&1
output_stream="/proc/self/fd/3"
verbose_stream="/dev/null"

while [ "$#" -gt 0 ]; do
  case $1 in 
    -h|--help|help)
      HELP=1
      ;;                                   
    -v|--verbose)
      exec 4>&2
      verbose_stream="/proc/self/fd/4"
      ;;                                   
    --no-rsync)
      NO_RSYNC=1
      ;;
    -r|--recreate)
      RECREATE=1
      ;;
    -*)
      echo "Error: Unsupported flag $1" >&2
      return 1
      ;;                                  
    *)  # No more options                          
      break
      ;;                                                                                                  
  esac
  shift                     
done

# Display help information
if [ "$HELP" ]; then
  printf 'Usage: $(basename "$0") <ssh host> <folder>\n'
  printf 'Options:\n'
  printf '  -h --help       this message\n'
  printf '  -v --verbose    verbose mode\n'
  printf '  -r --recreate    recreate forlder on remote\n'
  exit 0
fi

host="${1-"$(
  printf 'error: host not provided\n use --help to read manual\n' >&2
  exit 1
)"}"

folder="${2-"$(
  printf 'error: forlde not provided\n use --help to read manual\n' >&2
  exit 1
)"}"

container_name="$(yq -r '.services | to_entries | .[0].value.container_name' docker-compose.yml)"

[ $? -eq 1 ] && printf 'error: yq error, try check verbose\n' >&2

if [ ! "$RECREATE" ]; then
ssh $host << EOF
rm -rf "${folder}"
docker stop "\$(docker ps -qf "name=${container_name}")"
docker rm "\$(docker ps -qf "name=${container_name}")"
EOF
fi

if [ ! "$NO_RSYNC" ]; then
  rsync_options="-avz --delete --delete-excluded --progress"
  if [ -f ".deployignore" ]; then
    rsync_options="$rsync_options --exclude-from=.deployignore"
  fi

  rsync $rsync_options ./* "$host:$folder" 1>$verbose_stream 2>&2
  
  [ $? -eq 1 ] && printf 'error: rsync error, try check verbose\n' >&2
else 
ssh $host << EOF
rm -rf "${folder}"
docker stop "\$(docker ps -qf "name=${container_name}")"
docker rm "\$(docker ps -qf "name=${container_name}")"
EOF

  echo "--no-rsynk work bad, if work" >$output_stream

  ARCHIVE_NAME="web-app.tar.gz";

  # safest code ever
  rm "$ARCHIVE_NAME" 2>&1 > /dev/null

  tar --exclude-from='.deployignore' -czf "$ARCHIVE_NAME" ./*

  scp "$ARCHIVE_NAME" "$host:/tmp/"

  rm "$ARCHIVE_NAME"

  exit 0

  ssh "$host" "tar -xzf /tmp/$ARCHIVE_NAME -C $folder; rm /tmp/$ARCHIVE_NAME" >/dev/null
  
fi

ssh $host >/dev/null << EOF
cd "${folder}"
docker compose up --build -d
EOF
