#!/usr/bin/env bash
#
# Release a new version to the GitLab flow production branch.
#
# For a new major/minor version, bump version on the main branch, and then merge into the production branch.
#
# For a patch version, bump the version number on the patch branch, then merge that branch into the main branch
# and production branch.
#
#
# Usage: run on main branch or the patch branch
#
# Requires: Git, NPM and RubyGems

set -eu

opt_pre=false # preview mode option

working_branch="$(git branch --show-current)"

STAGING_BRANCH="$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')"

PROD_BRANCH="production"

GEM_SPEC="jekyll-theme-chirpy.gemspec"

NODE_CONFIG="package.json"

FILES=(
  "_sass/jekyll-theme-chirpy-clarkezone.scss"
  "_javascript/copyright"
  "$GEM_SPEC"
  "$NODE_CONFIG"
)

TOOLS=(
  "git"
  "npm"
  "standard-version"
  "gem"
)

help() {
  echo "A tool to release new version Chirpy gem"
  echo
  echo "Usage:"
  echo-clarkezone
  echo "   bash ./tools/release.sh [options]"
  echo
  echo "Options:"
  echo "     -p, --preview            Enable preview mode, only package, and will not modify the branches"
  echo "     -h, --help               Print this information."
}

_check_git() {
  # ensure nothing is uncommitted
  if [[ -n $(git status . -s) ]]; then
    echo "Abort: Commit the staged files first, and then run this tool again."
    exit 1
  fi

  # ensure the working branch is the main/patch branch
  if [[ $working_branch != "$STAGING_BRANCH" && $working_branch != hotfix/* ]]; then
    echo "Abort: Please run on the main branch or patch branches."
    exit 1
  fi
}

_check_src() {
  if [[ ! -f $1 && ! -d $1 ]]; then
    echo -e "Error: Missing file \"$1\"!\n"
    exit 1
  fi
}

_check_command() {
  if ! command -v "$1" &>/dev/null; then
    echo "Command '$1' not found"
    exit 1
  fi
}

_check_node_packages() {
  if [[ ! -d node_modules || "$(du node_modules | awk '{print $1}')" == "0" ]]; then
    npm i
  fi
}

check() {
  _check_git

  for i in "${!FILES[@]}"; do
    _check_src "${FILES[$i]}"
  done

  for i in "${!TOOLS[@]}"; do
    _check_command "${TOOLS[$i]}"
  done

  _check_node_packages
}

_bump_file() {
  for i in "${!FILES[@]}"; do
    sed -i "s/v[[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+/v$1/" "${FILES[$i]}"
  done

  npx gulp
}

_bump_gemspec() {
  sed -i "s/[[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+/$1/" "$GEM_SPEC"
}

# 1. Bump latest version number to the following files:
#
#   - _sass/jekyll-theme-chirpy-clarkezone.scss
#   - _javascript/copyright
#   - assets/js/dist/*.js (will be built by gulp later)
#   - jekyll-theme-chirpy.gemspec
#
# 2. Create a commit to save the changes.
bump() {
  _bump_file "$1"
  _bump_gemspec "$1"

  if [[ $opt_pre = false && -n $(git status . -s) ]]; then
    git add .
    git commit -m "chore(release): $1"
  fi
}

## Remove unnecessary theme settings
cleanup_config() {
  cp _config.yml _config.yml.bak
  sed -i "s/^img_cdn:.*/img_cdn:/;s/^avatar:.*/avatar:/" _config.yml
}

resume_config() {
  mv _config.yml.bak _config.yml
}

# build a gem package
build_gem() {
  echo -e "Build the gem package for v$_version\n"
  cleanup_config
  rm -f ./*.gem
  gem build "$GEM_SPEC"
  resume_config
}

# Update the git branch graph, tag, and then build the gem package.
release() {
  _version="$1" # X.Y.Z

  # Create a new tag on working branch
  echo -e "Create tag v$_version\n"
  git tag "v$_version"

  git checkout "$PROD_BRANCH"
  git merge --no-ff --no-edit "$working_branch"

  # merge from patch branch to the staging branch
  # NOTE: This may break due to merge conflicts, so it may need to be resolved manually.
  if [[ $working_branch == hotfix/* ]]; then
    git checkout "$STAGING_BRANCH"
    git merge --no-ff --no-edit "$working_branch"
    git branch -D "$working_branch"
  fi
}

main() {
  check

  # auto-generate a new version number to the file 'package.json'
  if $opt_pre; then
    standard-version --prerelease rc
  else
    standard-version
  fi

  _version="$(grep '"version":' package.json | sed 's/.*: "//;s/".*//')"

  echo -e "Bump version number to $_version\n"
  bump "$_version"

  build_gem

  if [[ $opt_pre = true ]]; then
    # Undo all changes on Git
    git reset --hard && git clean -fd
  else
    release "$_version"
  fi
}

while (($#)); do
  opt="$1"
  case $opt in
  -p | --preview)
    opt_pre=true
    shift
    ;;
  -h | --help)
    help
    exit 0
    ;;
  *)
    # unknown option
    help
    exit 1
    ;;
  esac
done

main
