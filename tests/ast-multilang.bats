#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
AST_LIB="$REPO_ROOT/hooks/lib/ast-signature.sh"

setup() {
  WORK="$(mktemp -d)"
}

teardown() {
  rm -rf "$WORK"
}

run_ast() {
  local op="$1"
  local file_a="$2"
  local file_b="${3:-}"
  bash -lc "
    set -euo pipefail
    source '$AST_LIB'
    case '$op' in
      extract-signatures) ast_extract_signatures '$file_a' ;;
      diff-signatures) ast_diff_signatures '$file_a' '$file_b' ;;
      extract-enums) ast_extract_enums '$file_a' ;;
      diff-enums) ast_diff_enums '$file_a' '$file_b' ;;
    esac
  "
}

@test "go AST plugin: extract-signatures and diff-signatures smoke" {
  command -v go >/dev/null 2>&1 || skip "go not on PATH"

  cat > "$WORK/base.go" <<'EOF'
package demo

func Compute(id string) string { return id }

type Repo struct{}
func (r *Repo) Find(id string) string { return id }
EOF
  cat > "$WORK/head.go" <<'EOF'
package demo

func Compute(id string, verbose bool) string { return id }

type Repo struct{}
func (r *Repo) Find(id string) string { return id }
EOF

  run run_ast extract-signatures "$WORK/base.go"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name":"Compute"'* ]]
  [[ "$output" == *'"owner":"Repo"'* ]]

  run run_ast diff-signatures "$WORK/base.go" "$WORK/head.go"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"param-count"'* ]]
  [[ "$output" == *'"severity":"Major"'* ]]
}

@test "go AST plugin: extract-enums and diff-enums smoke" {
  command -v go >/dev/null 2>&1 || skip "go not on PATH"

  cat > "$WORK/base.go" <<'EOF'
package demo

type Status int
const (
  StatusActive Status = iota
  StatusInactive
)
EOF
  cat > "$WORK/head.go" <<'EOF'
package demo

type Status int
const (
  StatusActive Status = iota
  StatusInactive
  StatusArchived
)
EOF

  run run_ast extract-enums "$WORK/base.go"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name":"Status"'* ]]
  [[ "$output" == *'"name":"StatusActive"'* ]]

  run run_ast diff-enums "$WORK/base.go" "$WORK/head.go"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"added":["StatusArchived"]'* ]]
}

@test "python AST plugin: extract-signatures and diff-signatures smoke" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not on PATH"

  cat > "$WORK/base.py" <<'EOF'
def compute(a: int) -> str:
    return str(a)

class Repo:
    def find(self, key: str) -> str:
        return key
EOF
  cat > "$WORK/head.py" <<'EOF'
def compute(a: int, b: str = "") -> str:
    return str(a) + b

class Repo:
    def find(self, key: str) -> str:
        return key
EOF

  run run_ast extract-signatures "$WORK/base.py"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name":"compute"'* ]]
  [[ "$output" == *'"owner":"Repo"'* ]]

  run run_ast diff-signatures "$WORK/base.py" "$WORK/head.py"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"param-count"'* ]]
  [[ "$output" == *'"severity":"Minor"'* ]]
}

@test "python AST plugin: extract-enums and diff-enums smoke" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not on PATH"

  cat > "$WORK/base.py" <<'EOF'
import enum

class Status(enum.Enum):
    ACTIVE = "a"
    INACTIVE = "i"
EOF
  cat > "$WORK/head.py" <<'EOF'
import enum

class Status(enum.Enum):
    ACTIVE = "a"
    INACTIVE = "i"
    ARCHIVED = "x"
EOF

  run run_ast extract-enums "$WORK/base.py"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name":"Status"'* ]]
  [[ "$output" == *'"name":"ACTIVE"'* ]]

  run run_ast diff-enums "$WORK/base.py" "$WORK/head.py"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"added":["ARCHIVED"]'* ]]
}

@test "java AST plugin: extract-signatures plus diff-enums smoke" {
  run bash -lc "source '$AST_LIB'; ast_java_available"
  [ "$status" -eq 0 ] || skip "java AST runtime not provisioned"

  cat > "$WORK/Base.java" <<'EOF'
enum Status { ACTIVE, INACTIVE }
class Repo {
  String find(String id) { return id; }
}
EOF
  cat > "$WORK/Head.java" <<'EOF'
enum Status { ACTIVE, INACTIVE, ARCHIVED }
class Repo {
  String find(String id, String tenant) { return id + tenant; }
}
EOF

  run run_ast extract-signatures "$WORK/Base.java"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"name":"find"'* ]]
  [[ "$output" == *'"owner":"Repo"'* ]]

  run run_ast diff-enums "$WORK/Base.java" "$WORK/Head.java"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"added":["ARCHIVED"]'* ]]
}
