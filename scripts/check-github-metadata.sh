#!/usr/bin/env bash
set -euo pipefail

REPO=""
METADATA_FILE=".github/repo-metadata.json"
TOPIC_LIST_FILE=""
LABEL_LIST_FILE=""
JSON_OUTPUT=0

usage() {
  cat <<'USAGE'
Usage: scripts/check-github-metadata.sh [--repo owner/name] [--metadata path]
                                        [--topic-list-file path]
                                        [--label-list-file path] [--json]

Verifies that GitHub repository topics and labels match .github/repo-metadata.json.
Fixture files are useful for tests and should use gh JSON shapes:
  gh repo view OWNER/REPO --json repositoryTopics > topics.json
  gh label list --repo OWNER/REPO --limit 500 --json name,color,description > labels.json
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --metadata)
      METADATA_FILE="${2:-}"
      shift 2
      ;;
    --topic-list-file)
      TOPIC_LIST_FILE="${2:-}"
      shift 2
      ;;
    --label-list-file)
      LABEL_LIST_FILE="${2:-}"
      shift 2
      ;;
    --json)
      JSON_OUTPUT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [ ! -f "$METADATA_FILE" ]; then
  echo "Metadata file not found: $METADATA_FILE" >&2
  exit 66
fi

if [ -z "$REPO" ]; then
  REPO="$(ruby -rjson -e 'metadata = JSON.parse(File.read(ARGV.fetch(0))); puts metadata.fetch("repository", "")' "$METADATA_FILE")"
fi

if [ -z "$REPO" ]; then
  echo "Repository was not provided and metadata.repository is empty" >&2
  exit 64
fi

TMPDIR_CREATED=""
cleanup() {
  if [ -n "$TMPDIR_CREATED" ] && [ -d "$TMPDIR_CREATED" ]; then
    rm -rf "$TMPDIR_CREATED"
  fi
}
trap cleanup EXIT

if [ -z "$TOPIC_LIST_FILE" ] || [ -z "$LABEL_LIST_FILE" ]; then
  TMPDIR_CREATED="$(mktemp -d)"
fi

if [ -z "$TOPIC_LIST_FILE" ]; then
  TOPIC_LIST_FILE="$TMPDIR_CREATED/topics.json"
  gh repo view "$REPO" --json repositoryTopics > "$TOPIC_LIST_FILE"
fi

if [ -z "$LABEL_LIST_FILE" ]; then
  LABEL_LIST_FILE="$TMPDIR_CREATED/labels.json"
  gh label list --repo "$REPO" --limit 500 --json name,color,description > "$LABEL_LIST_FILE"
fi

ruby -rjson -e '
metadata_path, topics_path, labels_path, repo, json_output = ARGV
metadata = JSON.parse(File.read(metadata_path))
topic_payload = JSON.parse(File.read(topics_path))
label_payload = JSON.parse(File.read(labels_path))

actual_topics = if topic_payload.is_a?(Hash)
  topic_payload.fetch("repositoryTopics", []).map { |topic| topic.fetch("name") }
else
  topic_payload.map { |topic| topic.fetch("name") }
end

actual_labels = if label_payload.is_a?(Hash)
  label_payload.fetch("labels", [])
else
  label_payload
end
labels_by_name = actual_labels.each_with_object({}) do |label, result|
  result[label.fetch("name")] = label
end

required_topics = metadata.fetch("requiredTopics")
required_labels = metadata.fetch("labels")
missing_topics = required_topics.reject { |topic| actual_topics.include?(topic) }
missing_labels = required_labels.map { |label| label.fetch("name") }.reject { |name| labels_by_name.key?(name) }

mismatched_labels = []
required_labels.each do |expected|
  actual = labels_by_name[expected.fetch("name")]
  next unless actual

  expected_color = expected.fetch("color").upcase
  actual_color = actual.fetch("color", "").upcase
  if actual_color != expected_color
    mismatched_labels << {
      "name" => expected.fetch("name"),
      "field" => "color",
      "expected" => expected_color,
      "actual" => actual_color
    }
  end

  expected_description = expected.fetch("description")
  actual_description = actual.fetch("description", "")
  if actual_description != expected_description
    mismatched_labels << {
      "name" => expected.fetch("name"),
      "field" => "description",
      "expected" => expected_description,
      "actual" => actual_description
    }
  end
end

checks = []
if missing_topics.empty?
  checks << {
    "name" => "topics",
    "status" => "passed",
    "message" => "Required GitHub topics are present."
  }
else
  checks << {
    "name" => "topics",
    "status" => "blocked",
    "message" => "Missing required GitHub topics: #{missing_topics.join(", ")}"
  }
end

if missing_labels.empty? && mismatched_labels.empty?
  checks << {
    "name" => "labels",
    "status" => "passed",
    "message" => "Required GitHub labels are present with expected colors and descriptions."
  }
else
  label_messages = []
  label_messages << "missing labels: #{missing_labels.join(", ")}" unless missing_labels.empty?
  unless mismatched_labels.empty?
    label_messages << "mismatched labels: #{mismatched_labels.map { |entry| "#{entry["name"]}.#{entry["field"]}" }.join(", ")}"
  end
  checks << {
    "name" => "labels",
    "status" => "blocked",
    "message" => label_messages.join("; ")
  }
end

blocked = checks.any? { |check| check.fetch("status") == "blocked" }
summary = {
  "schemaVersion" => 1,
  "repository" => repo,
  "status" => blocked ? "blocked" : "passed",
  "checks" => checks,
  "missingTopics" => missing_topics,
  "missingLabels" => missing_labels,
  "mismatchedLabels" => mismatched_labels
}

if json_output == "1"
  puts JSON.pretty_generate(summary)
else
  if blocked
    checks.each do |check|
      next unless check.fetch("status") == "blocked"
      warn check.fetch("message")
    end
  else
    puts "GitHub metadata OK for #{repo}: #{required_topics.count} topics and #{required_labels.count} labels"
  end
end

exit(blocked ? 1 : 0)
' "$METADATA_FILE" "$TOPIC_LIST_FILE" "$LABEL_LIST_FILE" "$REPO" "$JSON_OUTPUT"
