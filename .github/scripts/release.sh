#!/usr/bin/env bash
set -euo pipefail

branch=${GITHUB_REF_NAME:?GITHUB_REF_NAME is required}
commit=${GITHUB_SHA:?GITHUB_SHA is required}
repository=${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}
temp_dir=${RUNNER_TEMP:?RUNNER_TEMP is required}

if [[ ! $branch =~ ^release/v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "Invalid release branch: expected release/vMAJOR.MINOR.PATCH with no leading zeroes" >&2
    exit 1
fi

version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
tag="v$version"
marker="<!-- online-ss-release-workflow:$branch -->"
archive="$temp_dir/upd_knutle_online_ss_pkg-$version.zip"
release_json="$temp_dir/online-ss-release.json"

if [[ $(git rev-parse HEAD) != "$commit" ]]; then
    echo "Checked-out commit does not match the workflow commit" >&2
    exit 1
fi

remote_branch=$(git ls-remote --refs origin "refs/heads/$branch")
if [[ ${remote_branch%%[[:space:]]*} != "$commit" ]]; then
    echo "Skipping stale release run: branch no longer points to $commit"
    exit 0
fi

for file in extensions/online-ss/daemon.sh extensions/online-ss/config/daemon.conf \
    extensions/online-ss/bin/fbink_hf; do
    if ! git cat-file -e "$commit:$file"; then
        echo "Required package file is missing: $file" >&2
        exit 1
    fi
done
if [[ $(git ls-tree "$commit" -- extensions/online-ss/bin/fbink_hf | cut -d ' ' -f 1) != 100755 ]]; then
    echo "The packaged FBInk binary must be executable" >&2
    exit 1
fi
if ! git ls-tree -r --name-only "$commit" -- documents | grep -q '^documents/knutle_online_ss_.*\.sh$'; then
    echo "No package scriptlets found in documents/" >&2
    exit 1
fi

git archive --format=zip --output="$archive" "$commit" documents extensions

remote_tag=$(git ls-remote --refs origin "refs/tags/$tag")
tag_commit=${remote_tag%%[[:space:]]*}

gh api "repos/$repository/releases?per_page=100" --paginate --slurp >"$release_json"
release_count=$(jq --arg tag "$tag" '[.[][] | select(.tag_name == $tag)] | length' "$release_json")
if [[ $release_count -gt 1 ]]; then
    echo "Multiple releases found for $tag; refusing to modify them" >&2
    exit 1
fi

if [[ $release_count -eq 1 ]]; then
    if ! jq -e --arg marker "$marker" \
        --arg tag "$tag" \
        '[.[][] | select(.tag_name == $tag)][0] |
         .draft == true and (.body | type == "string" and contains($marker))' \
        "$release_json" >/dev/null; then
        echo "Release $tag is published or not managed by this workflow; refusing to modify it" >&2
        exit 1
    fi
    if [[ -z $tag_commit ]]; then
        echo "Draft release $tag has no corresponding remote tag; refusing to modify it" >&2
        exit 1
    fi

    # The release is owned by this workflow; use a lease to avoid overwriting a concurrent tag change.
    if [[ $tag_commit != "$commit" ]]; then
        git push --force-with-lease="refs/tags/$tag:$tag_commit" origin "$commit:refs/tags/$tag"
    fi
    gh release upload "$tag" "$archive" --clobber --repo "$repository"
else
    if [[ -n $tag_commit ]]; then
        echo "Tag $tag already exists without a managed draft release; refusing to overwrite it" >&2
        exit 1
    fi

    # Push without force so a tag created concurrently cannot be overwritten.
    git push origin "$commit:refs/tags/$tag"
    if ! gh release create "$tag" "$archive" --verify-tag --draft --title "$tag" \
        --notes "$marker" --repo "$repository"; then
        echo "Release creation failed; tag $tag may need manual cleanup before retrying" >&2
        exit 1
    fi
fi
