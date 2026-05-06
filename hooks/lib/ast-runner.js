#!/usr/bin/env node
// AST operations for TS/JS hooks. Invoked from hooks/ast-langs/ts_js.sh.
//
// Why TypeScript Compiler API rather than tree-sitter:
//   - Native parser handles every TS surface (generics, conditional types,
//     overloads, destructured params, satisfies-clauses) without a query DSL.
//   - Pure JS install — no native build step, no per-platform binary.
//   - Same parser tsc itself uses, so signatures match what reviewers see.
//
// Operations (argv[2]):
//   extract-signatures <file>
//     Emits JSON array of { name, owner, line, kind, params[], returnType }
//     for top-level functions, exported const arrow functions, and class
//     methods. `owner` is the class name for methods, null otherwise.
//
//   extract-enums <file>
//     Emits JSON array of { name, line, members: [{name, value}] } for
//     each `enum X { ... }` declaration. `value` is the textual
//     initializer (or null for auto-numbered numeric enums). Used by R12
//     (enum coverage gap detection).
//
//   extract-all <file>
//     Single-pass parse returning { signatures, enums } in one call.
//     Hooks consuming multiple kinds of AST data on the same file should
//     prefer this over multiple ops to avoid re-parsing.
//
//   diff-signatures <baseFile> <headFile>
//     Extracts signatures from both files and reports differences by
//     (owner, name). Emits JSON array of { name, owner, kind, line,
//     changes: [...], detail: string, severity }. `severity` is 'Major'
//     when an existing function was removed OR a required parameter was
//     added at the tail (silent breakage in JS / `// @ts-ignore`); 'Minor'
//     otherwise. Used by R3 C4 (signature change → caller-side update).
//
//   diff-enums <baseFile> <headFile>
//     Compares enum member sets by enum name. Emits JSON array of
//     { name, line, added: [], removed: [] } where `added` / `removed`
//     are member-name lists. Enums with no member changes are omitted.
//     Used by R12 C5 (enum member added → switch coverage gap).
//
// Output: JSON to stdout. Errors → stderr + non-zero exit so the caller can
// degrade gracefully (R3 regex categories continue to run).

const fs = require("fs");
const path = require("path");

let ts;
try {
  ts = require("typescript");
} catch (e) {
  console.error(
    "ast-runner: typescript module not found. Run install.sh to provision deps.",
  );
  process.exit(2);
}

const op = process.argv[2];
const args = process.argv.slice(3);

function paramShape(p, sf) {
  return {
    // Destructured params have no stable name; we use a placeholder so the
    // shape comparison still detects "added a param at position N".
    name: p.name && ts.isIdentifier(p.name) ? p.name.text : "<destructured>",
    type: p.type ? p.type.getText(sf) : null,
    optional: !!p.questionToken,
    rest: !!p.dotDotDotToken,
    hasDefault: !!p.initializer,
  };
}

function makeSig(node, sf, owner, kind, nameNode) {
  return {
    name: nameNode.text,
    owner,
    line: sf.getLineAndCharacterOfPosition(node.getStart(sf)).line + 1,
    kind,
    params: (node.parameters || []).map((p) => paramShape(p, sf)),
    returnType: node.type ? node.type.getText(sf) : null,
  };
}

function parseFile(file) {
  let source;
  try {
    source = fs.readFileSync(file, "utf8");
  } catch (e) {
    console.error(`ast-runner: cannot read ${file}: ${e.message}`);
    process.exit(3);
  }
  const ext = path.extname(file).toLowerCase();
  const scriptKind =
    ext === ".tsx" || ext === ".jsx" ? ts.ScriptKind.TSX : ts.ScriptKind.TS;
  const sf = ts.createSourceFile(
    file,
    source,
    ts.ScriptTarget.Latest,
    true,
    scriptKind,
  );
  return sf;
}

// Single visitor that collects every supported AST shape in one pass.
// Per-op `extract-*` wrappers filter the result; `extract-all` returns it
// whole. Designed so adding a new collector (R12 enums today, R19 mocks
// later) does not multiply parser invocations.
function collectAll(sf) {
  const sigs = [];
  const enums = [];

  function visit(node, owner) {
    // --- signatures ---
    if (ts.isFunctionDeclaration(node) && node.name) {
      sigs.push(makeSig(node, sf, owner, "function", node.name));
    } else if (
      ts.isMethodDeclaration(node) &&
      node.name &&
      ts.isIdentifier(node.name)
    ) {
      sigs.push(makeSig(node, sf, owner, "method", node.name));
    } else if (
      ts.isMethodSignature(node) &&
      node.name &&
      ts.isIdentifier(node.name)
    ) {
      sigs.push(makeSig(node, sf, owner, "method-sig", node.name));
    } else if (ts.isVariableStatement(node)) {
      for (const decl of node.declarationList.declarations) {
        if (
          decl.initializer &&
          (ts.isArrowFunction(decl.initializer) ||
            ts.isFunctionExpression(decl.initializer)) &&
          ts.isIdentifier(decl.name)
        ) {
          sigs.push(makeSig(decl.initializer, sf, owner, "arrow", decl.name));
        }
      }
    } else if (ts.isClassDeclaration(node) && node.name) {
      const className = node.name.text;
      for (const member of node.members) visit(member, className);
      return;
    } else if (ts.isInterfaceDeclaration(node) && node.name) {
      const ifaceName = node.name.text;
      for (const member of node.members) visit(member, ifaceName);
      return;
    }
    // --- enums ---
    else if (ts.isEnumDeclaration(node) && node.name) {
      enums.push({
        name: node.name.text,
        line: sf.getLineAndCharacterOfPosition(node.getStart(sf)).line + 1,
        members: node.members.map((m) => ({
          // Member identifier — for computed enum members
          // (`[Symbol.iterator]` etc.) we fall back to the source text;
          // those are vanishingly rare in real enums.
          name:
            m.name && ts.isIdentifier(m.name)
              ? m.name.text
              : m.name
                ? m.name.getText(sf)
                : "<unknown>",
          // Initializer text (or null for auto-numbered numeric enums).
          // Comparing values is out of v1 scope — added/removed by name
          // is the C5 signal. Keeping the field for future use.
          value: m.initializer ? m.initializer.getText(sf) : null,
        })),
      });
      return;
    }
    ts.forEachChild(node, (n) => visit(n, owner));
  }

  visit(sf, null);
  return { signatures: sigs, enums };
}

// Backwards-compatible view over collectAll for the existing
// extract-signatures / diff-signatures consumers.
function collectSignatures(sf) {
  return collectAll(sf).signatures;
}

function collectEnums(sf) {
  return collectAll(sf).enums;
}

function extractSignatures(file) {
  const sf = parseFile(file);
  process.stdout.write(JSON.stringify(collectSignatures(sf)));
}

function extractEnums(file) {
  const sf = parseFile(file);
  process.stdout.write(JSON.stringify(collectEnums(sf)));
}

function extractAll(file) {
  const sf = parseFile(file);
  process.stdout.write(JSON.stringify(collectAll(sf)));
}

function diffSignatures(baseFile, headFile) {
  const baseSigs = collectSignatures(parseFile(baseFile));
  const headSigs = collectSignatures(parseFile(headFile));
  const key = (s) => `${s.owner || ""}::${s.name}`;

  const baseByKey = new Map();
  for (const s of baseSigs) {
    // For overloads / duplicate names, keep the first; v1 limitation.
    if (!baseByKey.has(key(s))) baseByKey.set(key(s), s);
  }
  const headByKey = new Map();
  for (const s of headSigs) {
    if (!headByKey.has(key(s))) headByKey.set(key(s), s);
  }

  const out = [];

  for (const [k, base] of baseByKey) {
    const head = headByKey.get(k);
    if (!head) {
      // Removed: function existed at base, gone at head. Callers may be stale.
      out.push({
        name: base.name,
        owner: base.owner,
        kind: base.kind,
        line: base.line,
        changes: ["removed"],
        detail: `${formatLabel(base)} removed`,
        severity: "Major",
      });
      continue;
    }
    const changes = [];
    const details = [];
    let majorReason = null;
    if (base.params.length !== head.params.length) {
      changes.push("param-count");
      details.push(
        `params ${base.params.length} → ${head.params.length}`,
      );
      // A required tail parameter added is a silent breakage in JS / when
      // callers use `// @ts-ignore`. Optional / rest / default-valued
      // additions are non-breaking. Param removal is also non-Major (TS
      // catches extras at compile-time; runtime ignores them).
      if (head.params.length > base.params.length) {
        const newTail = head.params.slice(base.params.length);
        const requiredAddition = newTail.some(
          (p) => !p.optional && !p.hasDefault && !p.rest,
        );
        if (requiredAddition) majorReason = "required parameter added";
      }
    } else {
      // Same arity — compare per-position shape. Name changes alone are
      // not flagged (callers don't see param names at call sites in
      // positional calls). We flag type / optional / rest / default
      // because each can break callers.
      const shapeDiffs = [];
      for (let i = 0; i < base.params.length; i++) {
        const b = base.params[i];
        const h = head.params[i];
        const fields = [];
        if (b.type !== h.type) fields.push(`type ${b.type} → ${h.type}`);
        if (b.optional !== h.optional)
          fields.push(`optional ${b.optional} → ${h.optional}`);
        if (b.rest !== h.rest) fields.push(`rest ${b.rest} → ${h.rest}`);
        if (b.hasDefault !== h.hasDefault)
          fields.push(`default ${b.hasDefault} → ${h.hasDefault}`);
        if (fields.length > 0) shapeDiffs.push(`#${i + 1} ${fields.join(", ")}`);
      }
      if (shapeDiffs.length > 0) {
        changes.push("param-shape");
        details.push(shapeDiffs.join("; "));
      }
    }
    if (base.returnType !== head.returnType) {
      changes.push("return-type");
      details.push(`return ${base.returnType} → ${head.returnType}`);
    }
    if (changes.length > 0) {
      out.push({
        name: head.name,
        owner: head.owner,
        kind: head.kind,
        line: head.line,
        changes,
        detail: details.join("; "),
        severity: majorReason ? "Major" : "Minor",
      });
    }
  }

  process.stdout.write(JSON.stringify(out));
}

function diffEnums(baseFile, headFile) {
  const baseEnums = collectEnums(parseFile(baseFile));
  const headEnums = collectEnums(parseFile(headFile));
  const baseByName = new Map(baseEnums.map((e) => [e.name, e]));
  const headByName = new Map(headEnums.map((e) => [e.name, e]));

  const out = [];
  for (const [name, head] of headByName) {
    const base = baseByName.get(name);
    if (!base) continue; // brand-new enums have no callers to retrofit
    const baseMembers = new Set(base.members.map((m) => m.name));
    const headMembers = new Set(head.members.map((m) => m.name));
    const added = [...headMembers].filter((m) => !baseMembers.has(m));
    const removed = [...baseMembers].filter((m) => !headMembers.has(m));
    if (added.length === 0 && removed.length === 0) continue;
    out.push({ name, line: head.line, added, removed });
  }
  process.stdout.write(JSON.stringify(out));
}

function formatLabel(s) {
  return s.owner ? `${s.owner}.${s.name}` : s.name;
}

switch (op) {
  case "extract-signatures":
    if (args.length !== 1) {
      console.error("usage: ast-runner extract-signatures <file>");
      process.exit(1);
    }
    extractSignatures(args[0]);
    break;
  case "extract-enums":
    if (args.length !== 1) {
      console.error("usage: ast-runner extract-enums <file>");
      process.exit(1);
    }
    extractEnums(args[0]);
    break;
  case "extract-all":
    if (args.length !== 1) {
      console.error("usage: ast-runner extract-all <file>");
      process.exit(1);
    }
    extractAll(args[0]);
    break;
  case "diff-signatures":
    if (args.length !== 2) {
      console.error("usage: ast-runner diff-signatures <baseFile> <headFile>");
      process.exit(1);
    }
    diffSignatures(args[0], args[1]);
    break;
  case "diff-enums":
    if (args.length !== 2) {
      console.error("usage: ast-runner diff-enums <baseFile> <headFile>");
      process.exit(1);
    }
    diffEnums(args[0], args[1]);
    break;
  default:
    console.error(`ast-runner: unknown op '${op}'`);
    process.exit(1);
}
