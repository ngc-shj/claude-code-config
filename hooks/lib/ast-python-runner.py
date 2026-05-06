#!/usr/bin/env python3
import ast
import json
import sys


ENUM_BASE_NAMES = {"Enum", "IntEnum", "StrEnum", "Flag", "IntFlag"}


def source_segment(source, node):
    segment = ast.get_source_segment(source, node)
    return segment if segment is not None else None


def build_optional_map(args):
    out = {}
    positional = list(args.posonlyargs) + list(args.args)
    positional_defaults = [None] * (len(positional) - len(args.defaults)) + list(args.defaults)
    for arg, default in zip(positional, positional_defaults):
        out[id(arg)] = default is not None
    for arg, default in zip(args.kwonlyargs, args.kw_defaults):
        out[id(arg)] = default is not None
    return out


def params_from_args(source, args):
    optional_map = build_optional_map(args)
    params = []

    for arg in list(args.posonlyargs) + list(args.args):
        params.append(
            {
                "name": arg.arg,
                "type": source_segment(source, arg.annotation),
                "optional": optional_map.get(id(arg), False),
                "rest": False,
                "hasDefault": optional_map.get(id(arg), False),
            }
        )

    if args.vararg is not None:
        params.append(
            {
                "name": args.vararg.arg,
                "type": source_segment(source, args.vararg.annotation),
                "optional": True,
                "rest": True,
                "hasDefault": False,
            }
        )

    for arg in args.kwonlyargs:
        params.append(
            {
                "name": arg.arg,
                "type": source_segment(source, arg.annotation),
                "optional": optional_map.get(id(arg), False),
                "rest": False,
                "hasDefault": optional_map.get(id(arg), False),
            }
        )

    if args.kwarg is not None:
        params.append(
            {
                "name": args.kwarg.arg,
                "type": source_segment(source, args.kwarg.annotation),
                "optional": True,
                "rest": True,
                "hasDefault": False,
            }
        )

    return params


def is_enum_base(base):
    if isinstance(base, ast.Attribute) and isinstance(base.value, ast.Name):
        return base.value.id == "enum" and base.attr in ENUM_BASE_NAMES
    return isinstance(base, ast.Name) and base.id in ENUM_BASE_NAMES


class Collector(ast.NodeVisitor):
    def __init__(self, source):
        self.source = source
        self.signatures = []
        self.enums = []

    def add_signature(self, node, owner):
        kind = "method" if owner else "function"
        self.signatures.append(
            {
                "name": node.name,
                "owner": owner,
                "line": node.lineno,
                "kind": kind,
                "params": params_from_args(self.source, node.args),
                "returnType": source_segment(self.source, node.returns),
            }
        )

    def visit_FunctionDef(self, node):
        self.add_signature(node, None)

    def visit_AsyncFunctionDef(self, node):
        self.add_signature(node, None)

    def visit_ClassDef(self, node):
        if any(is_enum_base(base) for base in node.bases):
            members = []
            for item in node.body:
                if isinstance(item, ast.Assign):
                    for target in item.targets:
                        if isinstance(target, ast.Name):
                            members.append(
                                {
                                    "name": target.id,
                                    "value": source_segment(self.source, item.value),
                                }
                            )
                elif (
                    isinstance(item, ast.AnnAssign)
                    and isinstance(item.target, ast.Name)
                    and item.value is not None
                ):
                    members.append(
                        {
                            "name": item.target.id,
                            "value": source_segment(self.source, item.value),
                        }
                    )
            self.enums.append({"name": node.name, "line": node.lineno, "members": members})

        for item in node.body:
            if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)):
                self.add_signature(item, node.name)


def parse_file(path):
    with open(path, "r", encoding="utf-8") as handle:
        source = handle.read()
    return source, ast.parse(source, filename=path)


def extract_signatures(path):
    source, tree = parse_file(path)
    collector = Collector(source)
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            collector.visit(node)
    return collector.signatures


def extract_enums(path):
    source, tree = parse_file(path)
    collector = Collector(source)
    for node in tree.body:
        if isinstance(node, ast.ClassDef):
            collector.visit_ClassDef(node)
    return collector.enums


def main():
    if len(sys.argv) != 3:
        print("usage: ast-python-runner.py <extract-signatures|extract-enums> <file>", file=sys.stderr)
        sys.exit(1)

    op = sys.argv[1]
    path = sys.argv[2]

    if op == "extract-signatures":
        json.dump(extract_signatures(path), sys.stdout, separators=(",", ":"))
    elif op == "extract-enums":
        json.dump(extract_enums(path), sys.stdout, separators=(",", ":"))
    else:
        print(f"unknown op: {op}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
