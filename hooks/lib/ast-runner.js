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
//   diff-signatures <baseFile> <headFile>
//     Extracts signatures from both files and reports differences by
//     (owner, name). Emits JSON array of { name, owner, kind, line,
//     changes: [...], detail: string } where changes is a subset of
//     ['param-count','param-shape','return-type','removed']. `line` refers
//     to the head file (or base file when removed). Used by R3 C4
//     (signature change → caller-side update detection).
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

function collectSignatures(sf) {
  const sigs = [];

  function visit(node, owner) {
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
    ts.forEachChild(node, (n) => visit(n, owner));
  }

  visit(sf, null);
  return sigs;
}

function extractSignatures(file) {
  const sf = parseFile(file);
  process.stdout.write(JSON.stringify(collectSignatures(sf)));
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
      });
      continue;
    }
    const changes = [];
    const details = [];
    if (base.params.length !== head.params.length) {
      changes.push("param-count");
      details.push(
        `params ${base.params.length} → ${head.params.length}`,
      );
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
      });
    }
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
  case "diff-signatures":
    if (args.length !== 2) {
      console.error("usage: ast-runner diff-signatures <baseFile> <headFile>");
      process.exit(1);
    }
    diffSignatures(args[0], args[1]);
    break;
  default:
    console.error(`ast-runner: unknown op '${op}'`);
    process.exit(1);
}
