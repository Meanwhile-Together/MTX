| Feature / flow / logic | ✓ |
|------------------------|---|
| Check node installed (exit 1 if not) | ✓ |
| Check npm installed (exit 1 if not) | ✓ |
| NODE_MAJOR from node -v | ✓ |
| Echo Node/npm versions | ✓ |
| Check jq (warn; install during deploy) | ✓ |
| ROOT_DIR from script dir, cd ROOT_DIR | |
| ENV_FILE path, load .env if exists | ✓ |
| usage() | ✓ |
| CLI --project-name &lt;name&gt; | |
| CLI --package-id &lt;id&gt; | |
| CLI --npm-scope &lt;scope&gt; | |
| CLI --root-name &lt;name&gt; | |
| CLI --cap-platforms &lt;list&gt; | |
| CLI --sync &lt;yes\|no&gt; | |
| CLI --non-interactive / -y | |
| CLI --all | |
| CLI --even-keys | |
| CLI --setup-deployment | ✓ |
| CLI --skip-deployment | ✓ |
| CLI --force-backend | ✓ |
| CLI -h / --help | ✓ |
| CLI -v / --verbose | ✓ |
| VERBOSE → set -x | ✓ |
| ask() with NON_INTERACTIVE | ✓ |
| File path vars (ROOT_PKG, CLIENT_PKG, …) | ✓ |
| ensure_file() | ✓ |
| sed_inplace() (darwin vs linux) | ✓ |
| read_json_field() | ✓ |
| write_json_field() | ✓ |
| update_pkg_scope_json() | ✓ |
| replace_text_scope() find + sed | ✓ |
| slugify() | ✓ |
| get_app_slug() from app.json | ✓ |
| save_env_var() | ✓ |
| clear_env_var() | ✓ |
| prompt_token() hidden input, save to .env | ✓ |
| has_token() | ✓ |
| is_repo_setup() deploy.json platform length | ✓ |
| is_project_configured() app.json name or package description monorepo | ✓ |
| read_existing_config() app.json, capacitor, shared pkg, root pkg | ✓ |
| install_jq() brew/apt/yum | ✓ |
| install_terraform() brew/apt/hashicorp | ✓ |
| install_railway_cli() curl install.sh | ✓ |
| get_railway_project_info() GraphQL workspace/project | ✓ |
| get_railway_service_id() by name | ✓ |
| discover_services_for_project() backend/app staging/production | ✓ |
| get_railway_environments() | ✓ |
| create_railway_environment() | ✓ |
| ensure_railway_environments() production + staging | ✓ |
| prompt_railway_project_tokens() STAGING_JUST_CREATED clear | ✓ |
| init_railway() get project, create if missing, ensure envs, prompt tokens, discover services | ✓ |
| rediscover_railway_services() | ✓ |
| init_terraform() terraform init | ✓ |
| apply_terraform() deploy.json, app name, TF vars, apply.sh or terraform apply | ✓ |
| Main: echo Project Setup & Configuration | ✓ |
| read_existing_config at start | ✓ |
| is_project_configured → IS_CONFIGURED, RECONFIGURE_ALL/EVEN_KEYS messaging | ✓ |
| Prompt project name (or use existing) | ✓ |
| Prompt owner (or use existing) | ✓ |
| WEB_NAME DESKTOP_PRODUCT_NAME MOBILE_APP_NAME = PROJECT_NAME | ✓ |
| Prompt package ID (or use existing) | ✓ |
| SCOPE_OLD discovery (node shared then root) | ✓ |
| Prompt scope (or use existing) | ✓ |
| ROOT_NAME_OLD discovery, prompt root package name (or use existing) | ✓ |
| Capacitor platforms prompt (or skip if already android) | ✓ |
| npm install (first time) | ✓ |
| write root package description + name | ✓ |
| write app.json name owner slug (node block) | ✓ |
| write client package description | ✓ |
| write desktop package productName appId | ✓ |
| write electron-builder appId productName | ✓ |
| write Capacitor appId appName sed | ✓ |
| update_pkg_scope_json all known package.json files | ✓ |
| replace_text_scope | ✓ |
| npm install if scope changed | ✓ |
| add_platform_if_needed() | ✓ |
| NODE_MAJOR >= 20: RECONFIGURE_ALL → cap remove android/ios | |
| Parse CAP_PLATFORMS_RAW, add_platform_if_needed android\|ios | ✓ |
| SYNC_ARG → DO_SYNC yes/no | ✓ |
| DO_SYNC yes: build:packages, mobile build, cap sync | ✓ |
| Node < 20 skip Capacitor message | ✓ |
| npm run build | ✓ |
| Deployment block: SETUP_DEPLOYMENT or !SKIP && !NON_INTERACTIVE | ✓ |
| install_jq in deploy | ✓ |
| Create .env if not exists | ✓ |
| .env in .gitignore | ✓ |
| is_repo_setup → initial repo setup (deploy.json, app.json) | ✓ |
| Create deploy.json platform railway | ✓ |
| Create/update app.json (full or jq) in deploy | ✓ |
| Platforms from deploy.json, HAS_RAILWAY → prompt RAILWAY_ACCOUNT_TOKEN | ✓ |
| install_terraform, install_railway_cli in deploy | ✓ |
| get_railway_project_info (railway_project_name from owner) | ✓ |
| NOT_AUTHORIZED → clear token re-prompt | ✓ |
| save RAILWAY_WORKSPACE_ID/PROJECT_ID, ensure_railway_environments, prompt_railway_project_tokens | ✓ |
| init_terraform, apply_terraform | ✓ |
| init_railway (deploy step) | ✓ |
| Echo setup complete / next steps | ✓ |
