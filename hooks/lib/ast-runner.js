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
//   find-references-batch <inputJsonFile>
//     Resolves cross-file references via TS LanguageService (true symbol
//     resolution, not text-grep). Input is a JSON array of queries:
//       [{declFile, name, owner?}, ...]
//     Output mirrors input with a `references` field added per entry:
//       [{declFile, name, owner, references: [{file, line, column, kind}]}, ...]
//     `kind` is one of 'import' (in import/export specifier), 'type-ref'
//     (in type position), or 'ref' (everything else — call sites,
//     property access, assignments). Consumers filter by kind: C4 wants
//     non-import to flag stale calls; R17 may want all references.
//     One process amortizes LanguageService creation across all queries
//     sharing a tsconfig.json. Discovery walks up from each declFile;
//     synthetic project is built from cwd when no tsconfig found.
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

// ----- find-references-batch -----
//
// Different cost model from extract-* / diff-* ops: those parse one file
// at a time via createSourceFile (cheap). LanguageService.findReferences
// requires a Program covering all source files that might reference the
// symbol. Program creation dominates wall time, so we batch queries
// sharing a tsconfig and reuse one LanguageService per group.

function findTsconfig(file) {
  let dir = path.dirname(path.resolve(file));
  // Bound the walk to filesystem root.
  while (true) {
    const candidate = path.join(dir, "tsconfig.json");
    try {
      if (fs.statSync(candidate).isFile()) return candidate;
    } catch (_) {
      /* not present */
    }
    const parent = path.dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

function loadProjectFiles(tsconfigPath) {
  // Returns { rootFiles, options } from tsconfig, or null if parse fails.
  const config = ts.readConfigFile(tsconfigPath, ts.sys.readFile);
  if (config.error) return null;
  const parsed = ts.parseJsonConfigFileContent(
    config.config,
    ts.sys,
    path.dirname(tsconfigPath),
  );
  // Project-side errors that are non-fatal for findReferences (missing
  // referenced project, etc.) are tolerated — we just need the file list
  // and compiler options.
  return { rootFiles: parsed.fileNames, options: parsed.options };
}

function syntheticProjectFiles(rootDir) {
  // Synthetic include: every TS/JS source file under rootDir, skipping
  // node_modules and dotfiles. Same extension list as ast-langs/ts_js.sh
  // so reachability matches what ast_lang_for_file would dispatch on.
  const exts = new Set([".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs"]);
  const out = [];
  function walk(d) {
    let entries;
    try {
      entries = fs.readdirSync(d, { withFileTypes: true });
    } catch (_) {
      return;
    }
    for (const entry of entries) {
      if (entry.name === "node_modules" || entry.name.startsWith(".")) continue;
      const full = path.join(d, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.isFile() && exts.has(path.extname(entry.name))) out.push(full);
    }
  }
  walk(rootDir);
  return {
    rootFiles: out,
    options: {
      target: ts.ScriptTarget.Latest,
      module: ts.ModuleKind.ESNext,
      moduleResolution: ts.ModuleResolutionKind.NodeJs,
      allowJs: true,
      jsx: ts.JsxEmit.Preserve,
      // Disable lib loading to avoid false errors / slow startup; we
      // only need cross-file symbol resolution within the project.
      noLib: true,
      skipLibCheck: true,
    },
  };
}

function createService(rootFiles, options) {
  // Minimal LanguageServiceHost: read from disk, version=1 (no incremental).
  const rootSet = new Set(rootFiles.map((f) => path.resolve(f)));
  const host = {
    getScriptFileNames: () => rootFiles,
    getScriptVersion: () => "1",
    getScriptSnapshot: (f) => {
      try {
        return ts.ScriptSnapshot.fromString(fs.readFileSync(f, "utf8"));
      } catch (_) {
        return undefined;
      }
    },
    getCurrentDirectory: () => process.cwd(),
    getCompilationSettings: () => options,
    getDefaultLibFileName: (o) => ts.getDefaultLibFilePath(o),
    fileExists: (f) => {
      try {
        return fs.statSync(f).isFile();
      } catch (_) {
        return false;
      }
    },
    readFile: (f) => {
      try {
        return fs.readFileSync(f, "utf8");
      } catch (_) {
        return undefined;
      }
    },
    readDirectory: ts.sys.readDirectory,
    directoryExists: (d) => {
      try {
        return fs.statSync(d).isDirectory();
      } catch (_) {
        return false;
      }
    },
    getDirectories: ts.sys.getDirectories,
  };
  return {
    service: ts.createLanguageService(host, ts.createDocumentRegistry()),
    rootSet,
  };
}

// Walks the SourceFile to find the declaration of `name` (and `owner` when
// given). Returns the position of the name identifier, or null. Uses the
// same matching rules as collectAll so what we resolve matches what
// extract-signatures would emit.
function findDeclarationPosition(sf, name, owner) {
  let pos = null;

  function visit(node, currentOwner) {
    if (pos !== null) return;
    let nameNode = null;
    if (
      ts.isFunctionDeclaration(node) &&
      node.name &&
      node.name.text === name &&
      currentOwner === owner
    ) {
      nameNode = node.name;
    } else if (
      ts.isMethodDeclaration(node) &&
      node.name &&
      ts.isIdentifier(node.name) &&
      node.name.text === name &&
      currentOwner === owner
    ) {
      nameNode = node.name;
    } else if (
      ts.isMethodSignature(node) &&
      node.name &&
      ts.isIdentifier(node.name) &&
      node.name.text === name &&
      currentOwner === owner
    ) {
      nameNode = node.name;
    } else if (ts.isVariableStatement(node) && currentOwner === owner) {
      for (const decl of node.declarationList.declarations) {
        if (
          decl.initializer &&
          (ts.isArrowFunction(decl.initializer) ||
            ts.isFunctionExpression(decl.initializer)) &&
          ts.isIdentifier(decl.name) &&
          decl.name.text === name
        ) {
          nameNode = decl.name;
          break;
        }
      }
    } else if (ts.isClassDeclaration(node) && node.name) {
      for (const m of node.members) visit(m, node.name.text);
      return;
    } else if (ts.isInterfaceDeclaration(node) && node.name) {
      for (const m of node.members) visit(m, node.name.text);
      return;
    }
    if (nameNode) {
      pos = nameNode.getStart(sf);
      return;
    }
    ts.forEachChild(node, (n) => visit(n, currentOwner));
  }

  // Owner is normalized: missing/null/'' all mean top-level.
  const ownerKey = owner || null;
  visit(sf, null);
  // Re-walk with normalized comparison if owner-key form differs.
  // (No-op when ownerKey is already null — covered by first walk.)
  return pos;
}

function findReferencesBatch(inputFile) {
  let queries;
  try {
    queries = JSON.parse(fs.readFileSync(inputFile, "utf8"));
  } catch (e) {
    console.error(`find-references-batch: cannot read input: ${e.message}`);
    process.exit(3);
  }
  if (!Array.isArray(queries)) {
    console.error("find-references-batch: input must be a JSON array");
    process.exit(1);
  }

  // Tag each query with its input position so output preserves order even
  // when groups are processed in tsconfig-discovery order (relevant when
  // a batch spans multiple monorepo packages).
  const indexed = queries.map((q, i) => ({ ...q, _seq: i }));

  // Group queries by tsconfig path so each LanguageService is built once.
  // null key = synthetic project rooted at cwd.
  const byConfig = new Map();
  for (const q of indexed) {
    const tsconfig = q.declFile ? findTsconfig(q.declFile) : null;
    const key = tsconfig || "<synthetic>";
    if (!byConfig.has(key)) byConfig.set(key, { tsconfig, queries: [] });
    byConfig.get(key).queries.push(q);
  }

  const out = [];
  for (const [, group] of byConfig) {
    const project = group.tsconfig
      ? loadProjectFiles(group.tsconfig)
      : syntheticProjectFiles(process.cwd());
    if (!project) {
      // tsconfig parse failed — skip this group with empty references.
      for (const q of group.queries) {
        out.push({ ...q, references: [] });
      }
      continue;
    }

    // Make sure each query's declFile is in the rootFiles set; if not,
    // append it so the LanguageService can resolve from it.
    for (const q of group.queries) {
      const abs = path.resolve(q.declFile);
      if (!project.rootFiles.includes(abs) && !project.rootFiles.includes(q.declFile)) {
        project.rootFiles.push(q.declFile);
      }
    }

    const { service } = createService(project.rootFiles, project.options);
    const program = service.getProgram();
    if (!program) {
      for (const q of group.queries) out.push({ ...q, references: [] });
      continue;
    }

    for (const q of group.queries) {
      const refs = resolveOne(service, program, q);
      out.push({ ...q, references: refs });
    }
  }

  // Restore input order, then strip the internal index from emitted JSON.
  out.sort((a, b) => a._seq - b._seq);
  for (const o of out) delete o._seq;

  process.stdout.write(JSON.stringify(out));
}

// Normalize file paths to be relative to cwd when they fall under it.
// Bash callers use git-root-relative paths in CHANGED/UNCHANGED file
// lists; matching absolute paths from path.resolve() against those would
// fail. Falling back to absolute for paths outside cwd (e.g., when the
// declFile is a sibling project file).
function relativizeIfUnderCwd(p) {
  const cwd = process.cwd();
  const abs = path.resolve(p);
  if (abs === cwd) return ".";
  if (abs.startsWith(cwd + path.sep)) return path.relative(cwd, abs);
  return abs;
}

function classifyRef(refSf, position) {
  // Walk up from the token at `position` to determine whether the
  // reference sits inside an import/export specifier (kind=import), a
  // type position (kind=type-ref), or anywhere else (kind=ref). Walking
  // is cheap — at most a handful of parent hops.
  let token;
  try {
    token = ts.getTokenAtPosition(refSf, position);
  } catch (_) {
    return "ref";
  }
  let p = token && token.parent;
  while (p) {
    if (
      ts.isImportDeclaration(p) ||
      ts.isImportClause(p) ||
      ts.isImportSpecifier(p) ||
      ts.isNamedImports(p) ||
      ts.isNamespaceImport(p) ||
      ts.isExportDeclaration(p) ||
      ts.isExportSpecifier(p)
    ) {
      return "import";
    }
    if (ts.isTypeReferenceNode(p) || ts.isTypeQueryNode(p)) {
      return "type-ref";
    }
    p = p.parent;
  }
  return "ref";
}

function resolveOne(service, program, q) {
  const sf =
    program.getSourceFile(q.declFile) ||
    program.getSourceFile(path.resolve(q.declFile));
  if (!sf) return [];
  const declPos = findDeclarationPosition(sf, q.name, q.owner || null);
  if (declPos === null) return [];
  const refGroups = service.findReferences(sf.fileName, declPos);
  if (!refGroups) return [];
  const out = [];
  for (const group of refGroups) {
    for (const ref of group.references) {
      // Skip the declaration site itself.
      if (
        ref.fileName === sf.fileName &&
        ref.textSpan.start === declPos
      )
        continue;
      // Skip declaration files (.d.ts) — typically lib refs, not callers.
      if (ref.fileName.endsWith(".d.ts")) continue;
      const refSf = program.getSourceFile(ref.fileName);
      if (!refSf) continue;
      const lc = refSf.getLineAndCharacterOfPosition(ref.textSpan.start);
      out.push({
        file: relativizeIfUnderCwd(ref.fileName),
        line: lc.line + 1,
        column: lc.character + 1,
        kind: classifyRef(refSf, ref.textSpan.start),
      });
    }
  }
  return out;
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
  case "find-references-batch":
    if (args.length !== 1) {
      console.error("usage: ast-runner find-references-batch <inputJsonFile>");
      process.exit(1);
    }
    findReferencesBatch(args[0]);
    break;
  default:
    console.error(`ast-runner: unknown op '${op}'`);
    process.exit(1);
}
