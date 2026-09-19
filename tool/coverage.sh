#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
packages=("$@")
if [ "${#packages[@]}" -eq 0 ]; then
  packages=(engine_core engine_cli engine_flutter engine_platformer)
fi

for package in "${packages[@]}"; do
  case "$package" in
    engine_core|engine_cli|engine_flutter|engine_platformer) ;;
    *) printf 'Unknown package: %s\n' "$package" >&2; exit 2 ;;
  esac
  (
    cd "$repo_dir/packages/$package"
    case "$package" in
      engine_core|engine_cli)
        dart analyze --fatal-infos
        dart pub global run coverage:test_with_coverage
        python3 "$repo_dir/tool/check_coverage.py" .
        ;;
      engine_flutter)
        flutter analyze --fatal-infos
        flutter test --coverage --reporter expanded
        ENGINE_TEST_SHADER_ASSET=missing flutter test \
          test_support/gpu_light_shader_unavailable_test.dart \
          --coverage --coverage-path coverage/missing_shader.info --reporter expanded
        python3 "$repo_dir/tool/check_coverage.py" . \
          coverage/lcov.info coverage/missing_shader.info
        ;;
      engine_platformer)
        flutter analyze --fatal-infos
        flutter test --coverage --reporter expanded
        python3 "$repo_dir/tool/check_coverage.py" .
        ;;
    esac
  )
done
