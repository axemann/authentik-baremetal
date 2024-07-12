########

#Thanks to ChatGPT and good old fashioned trouble-shooting for getting the prereqs done!

#Now, as ROOT on Debian 12.x...

#apt update && apt upgrade -y

#apt install -y tee npm git pip wget build-essential postgresql postgresql-contrib libffi-dev libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev liblzma-dev

#systemctl start postgresql && systemctl enable postgresql 

#sudo -i -u postgres
#createuser authentik_user -P
#createdb authentik_db -O authentik_user
#exit

#apt install -y redis-server
#systemctl daemon-reload && systemctl enable redis-server.service && systemctl start redis-server.service

#psql -U authentik_user -d authentik_db -h localhost

########

# !/bin/bash

set -e
set -x

: "${ARCH:=amd64}"
BASE_DIR=$HOME
DOTLOCAL=$BASE_DIR/.local
BIN_DIR="${DOTLOCAL}/bin"
SRC_DIR=$BASE_DIR/src
THREADS=$(($(grep 'cpu cores' /proc/cpuinfo | uniq | awk '{print $4}')-1))

mkdir -p "$BIN_DIR"
PATH="${BIN_DIR}:${PATH}"

cd "$BASE_DIR"

apt update && \
# apt install -y \
#   software-properties-common
# apt remove python3 -y
add-apt-repository -yP ppa:deadsnakes/ppa && \
apt upgrade -y

apt install -y \
  python3-virtualenv \
  git \
  pip \
  wget \
  build-essential \
  redis-server \
  postgresql \
  postgresql-contrib \
  libffi-dev \
  libssl-dev \
  zlib1g-dev \
  libbz2-dev \
  libreadline-dev \
  libsqlite3-dev \
  wget \
  curl \
  llvm \
  libncurses5-dev \
  libncursesw5-dev \
  xz-utils \
  tk-dev \
  libxml2-dev \
  libxmlsec1-dev \
  liblzma-dev

if ! su - postgres bash -c "psql -c \"SELECT FROM pg_catalog.pg_roles WHERE rolname = 'authentik';\"" &> /dev/null
then
  su - postgres -c 'createuser authentik -P && createdb authentik -O authentik exit'
else
  echo "User 'authentik' already exists, skipping creation..."
fi

# if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 12, 1))' &>/dev/null
# then
# 	wget -qO- https://www.python.org/ftp/python/3.12.1/Python-3.12.1.tgz | tar -zxf -
# 	cd Python-3.12.1
# 	./configure --enable-optimizations --prefix="$DOTLOCAL"
# 	make -j $THREADS altinstall
# 	cd -
# 	rm -rf Python-3.12.1
# 	ln -s "${BIN_DIR}/python3.12" "${BIN_DIR}/python3"
# fi

if ! command -v yq &>/dev/null
then
  YQ_LATEST="$(wget -qO- "https://api.github.com/repos/mikefarah/yq/releases/latest" | grep -Po '"tag_name": "\K.*?(?=")')"
  wget "https://github.com/mikefarah/yq/releases/download/${YQ_LATEST}/yq_linux_${ARCH}" -qO "$DOTLOCAL"/bin/yq
	chmod +x "$DOTLOCAL"/bin/yq
fi

if ! command -v node &>/dev/null
then
	wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
	export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
	[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
	nvm install v22
fi

if ! command -v go &>/dev/null
then
	GO_JSON=$(wget -qO- "https://golang.org/dl/?mode=json")
  GO_LATEST_VERSION=$(echo "$GO_JSON" | grep -Po '"version": "\K.*?(?=")' | head -1)
  GO_LATEST_URL=$(echo "$GO_JSON" | grep -Po '"filename": "\K.*?(?=")' | grep "linux-${ARCH}" | grep "$GO_LATEST_VERSION" | head -1)

  if [ -z "${GO_LATEST_URL}" ]
  then
    echo 'Golang install URL not found, please fix the script' >&2
    exit 1
  fi

  wget -qO- "https://golang.org/dl/${GO_LATEST_URL}" | tar -zxf -
  cp -prf go/* "${DOTLOCAL}"
  chmod -R u+w go
  rm -rf go
fi

if ! command -v pip &>/dev/null
then
	curl https://bootstrap.pypa.io/get-pip.py | python3
fi

if ! python3 -m virtualenv --version &>/dev/null
then
	python3 -m pip install virtualenv
fi

if [ ! -d "$SRC_DIR" ]
then
	cd "$BASE_DIR"
	git clone https://github.com/goauthentik/authentik.git "$SRC_DIR"
	cd "$SRC_DIR"
else
	cd "$SRC_DIR"
	git pull --ff-only
fi

if [ ! -d .venv ]
then
	python3 -m virtualenv ./.venv
fi

curl https://bootstrap.pypa.io/get-pip.py | ./.venv/bin/python3
# Without --no-hash-check it all goes wrong!
./.venv/bin/pip install --no-cache-dir poetry poetry-plugin-export
#./.venv/bin/pip install --no-cache-dir --no-hash-check -r requirements.txt -r requirements-dev.txt
./.venv/bin/poetry export -f requirements.txt --output requirements.txt
./.venv/bin/poetry export -f requirements.txt --with dev --output requirements-dev.txt
# Without --no-hash-check it all goes wrong!
#./.venv/bin/pip install --no-cache-dir -r requirements.txt -r requirements-dev.txt

####

# Define the file names
#FILES=("requirements.txt" "requirements-dev.txt")

# Pattern to match the django-tenants dependency
#PATTERN="django-tenants@ git+https://github.com/rissson/django-tenants.git@a7f37c53f62f355a00142473ff1e3451bb794eca"

# Loop through each file
for FILE in "${FILES[@]}"
do
    # Check if the file exists
    if [ -f "$FILE" ]; then
        echo "Processing $FILE..."

        # Create a backup of the original file
        cp "$FILE" "$FILE.bak"

        # Remove the django-tenants git dependency line
       sed -i '\|django-tenants@git+https://github.com/rissson/django-tenants.git@a7f37c53f62f355a00142473ff1e3451bb794eca|d' requirements.txt


        echo "Removed django-tenants from $FILE, original backed up as $FILE.bak"
    else
        echo "$FILE does not exist."
    fi
done

echo "Installing django-tenants package from Git repository..."
	# Install the django-tenants package separately
	./.venv/bin/pip install --no-cache-dir --no-deps git+https://github.com/rissson/django-tenants.git@a7f37c53f62f355a00142473ff1e3451bb794eca

echo "Reinstalling other requirements..."
	# Reinstall other requirements from the updated files
	sed -i 's|django-tenants@ git+https://github.com/rissson/django-tenants.git@a7f37c53f62f355a00142473ff1e3451bb794eca|# &|' requirements.txt
	sed -i 's|django-tenants@ git+https://github.com/rissson/django-tenants.git@a7f37c53f62f355a00142473ff1e3451bb794eca|# &|' requirements-dev.txt

echo "Installation complete."
#####

####

# Update npm to the latest version
npm install -g npm@10.8.2

# Navigate to the directory where package.json is located
cd "$SRC_DIR/web"

# Install dependencies and attempt to fix vulnerabilities
npm i
npm audit fix

# Run a detailed audit to review manually if needed
npm audit

# Continue with other build processes
npm run build
npm audit fix
# Ensure all steps are executed without errors
set -e

####

mkdir -p "$HOME"/.config/systemd/user

tee "$HOME"/.config/systemd/user/authentik-server.service > /dev/null << EOF
[Unit]
Description = Authentik Server (Web/API/SSO)

[Service]
ExecStart=/bin/bash -c 'source /root/src/.venv/bin/activate && python3 -m lifecycle.migrate && /root/src/authentik-server'
WorkingDirectory=/root/src

Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

tee "$HOME"/.config/systemd/user/authentik-worker.service > /dev/null << EOF
[Unit]
Description = Authentik Worker (background tasks)

[Service]
ExecStart=/bin/bash -c 'source /root/src/.venv/bin/activate && celery -A authentik.root.celery worker -Ofair --max-tasks-per-child=1 --autoscale 3,1 -E -B -s /tmp/celerybeat-schedule -Q authentik,authentik_scheduled,authentik_events'
WorkingDirectory=/root/src

Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

if ! [ -f /etc/systemd/system/authentik-server.service ]; then
  ln -s /root/.config/systemd/user/authentik-server.service /etc/systemd/system/authentik-server.service
fi

if ! [ -f /etc/systemd/system/authentik-worker.service ]; then
  ln -s /root/.config/systemd/user/authentik-worker.service /etc/systemd/system/authentik-worker.service
fi

mkdir -p "$BASE_DIR"/{templates,certs}

CONFIG_FILE=$SRC_DIR/.local.env.yml

cp "$SRC_DIR"/authentik/lib/default.yml "$CONFIG_FILE"
cp -r "$SRC_DIR"/blueprints "$BASE_DIR"/blueprints

yq -i ".secret_key = \"$(openssl rand -hex 32)\"" "$CONFIG_FILE"

yq -i ".error_reporting.enabled = false" "$CONFIG_FILE"
yq -i ".disable_update_check = true" "$CONFIG_FILE"
yq -i ".disable_startup_analytics = true" "$CONFIG_FILE"
#Done in orignal script. Left for information
#yq -i ".avatars = \"none\"" "$CONFIG_FILE"

yq -i ".email.template_dir = \"${BASE_DIR}/templates\"" "$CONFIG_FILE"
yq -i ".cert_discovery_dir = \"${BASE_DIR}/certs\"" "$CONFIG_FILE"
yq -i ".blueprints_dir = \"${BASE_DIR}/blueprints\"" "$CONFIG_FILE"
yq -i ".geoip = \"/var/lib/GeoIP/GeoLite2-City.mmdb\""  "$CONFIG_FILE"

# Reload systemd and enable/start authentik services
systemctl daemon-reload && \
systemctl enable authentik-server authentik-worker && \
systemctl start authentik-server authentik-worker
