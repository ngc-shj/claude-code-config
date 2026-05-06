package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"go/ast"
	"go/parser"
	"go/printer"
	"go/token"
	"os"
	"strings"
)

type Param struct {
	Name       string  `json:"name"`
	Type       *string `json:"type"`
	Optional   bool    `json:"optional"`
	Rest       bool    `json:"rest"`
	HasDefault bool    `json:"hasDefault"`
}

type Signature struct {
	Name       string  `json:"name"`
	Owner      *string `json:"owner"`
	Line       int     `json:"line"`
	Kind       string  `json:"kind"`
	Params     []Param `json:"params"`
	ReturnType *string `json:"returnType"`
}

type EnumMember struct {
	Name  string  `json:"name"`
	Value *string `json:"value"`
}

type EnumDecl struct {
	Name    string       `json:"name"`
	Line    int          `json:"line"`
	Members []EnumMember `json:"members"`
}

type enumGroup struct {
	Line    int
	Members []EnumMember
}

func exprString(fset *token.FileSet, expr ast.Expr) *string {
	if expr == nil {
		return nil
	}
	var buf bytes.Buffer
	if err := printer.Fprint(&buf, fset, expr); err != nil {
		return nil
	}
	s := buf.String()
	return &s
}

func receiverOwner(fset *token.FileSet, recv *ast.FieldList) *string {
	if recv == nil || len(recv.List) == 0 {
		return nil
	}
	text := exprString(fset, recv.List[0].Type)
	if text == nil {
		return nil
	}
	owner := strings.TrimPrefix(*text, "*")
	return &owner
}

func paramsForFieldList(fset *token.FileSet, fields *ast.FieldList) []Param {
	if fields == nil {
		return []Param{}
	}
	var params []Param
	for _, field := range fields.List {
		typeText := exprString(fset, field.Type)
		rest := false
		if _, ok := field.Type.(*ast.Ellipsis); ok {
			rest = true
		}
		names := field.Names
		if len(names) == 0 {
			names = []*ast.Ident{{Name: "<anonymous>"}}
		}
		for _, name := range names {
			params = append(params, Param{
				Name:       name.Name,
				Type:       typeText,
				Optional:   false,
				Rest:       rest,
				HasDefault: false,
			})
		}
	}
	return params
}

func resultString(fset *token.FileSet, results *ast.FieldList) *string {
	if results == nil || len(results.List) == 0 {
		return nil
	}
	var out []string
	for _, field := range results.List {
		typeText := exprString(fset, field.Type)
		if typeText == nil {
			continue
		}
		if len(field.Names) == 0 {
			out = append(out, *typeText)
			continue
		}
		for _, name := range field.Names {
			out = append(out, fmt.Sprintf("%s %s", name.Name, *typeText))
		}
	}
	if len(out) == 0 {
		return nil
	}
	text := strings.Join(out, ", ")
	if len(out) > 1 {
		text = "(" + text + ")"
	}
	return &text
}

func containsIota(expr ast.Expr) bool {
	found := false
	ast.Inspect(expr, func(node ast.Node) bool {
		if ident, ok := node.(*ast.Ident); ok && ident.Name == "iota" {
			found = true
			return false
		}
		return true
	})
	return found
}

func extractSignatures(file string) ([]Signature, error) {
	fset := token.NewFileSet()
	parsed, err := parser.ParseFile(fset, file, nil, parser.ParseComments)
	if err != nil {
		return nil, err
	}

	var out []Signature
	for _, decl := range parsed.Decls {
		fn, ok := decl.(*ast.FuncDecl)
		if !ok {
			continue
		}
		kind := "function"
		owner := (*string)(nil)
		if fn.Recv != nil {
			kind = "method"
			owner = receiverOwner(fset, fn.Recv)
		}
		out = append(out, Signature{
			Name:       fn.Name.Name,
			Owner:      owner,
			Line:       fset.Position(fn.Pos()).Line,
			Kind:       kind,
			Params:     paramsForFieldList(fset, fn.Type.Params),
			ReturnType: resultString(fset, fn.Type.Results),
		})
	}
	return out, nil
}

func extractEnums(file string) ([]EnumDecl, error) {
	fset := token.NewFileSet()
	parsed, err := parser.ParseFile(fset, file, nil, parser.ParseComments)
	if err != nil {
		return nil, err
	}

	groups := map[string]*enumGroup{}
	var order []string

	for _, decl := range parsed.Decls {
		gen, ok := decl.(*ast.GenDecl)
		if !ok || gen.Tok != token.CONST {
			continue
		}

		lastType := ""
		prevEnumLike := false
		for _, spec := range gen.Specs {
			valueSpec, ok := spec.(*ast.ValueSpec)
			if !ok {
				continue
			}

			typeName := lastType
			if valueSpec.Type != nil {
				if typeText := exprString(fset, valueSpec.Type); typeText != nil {
					typeName = *typeText
					lastType = typeName
				}
			}

			specHasIota := false
			var valueText *string
			for _, value := range valueSpec.Values {
				if containsIota(value) {
					specHasIota = true
				}
				if valueText == nil {
					valueText = exprString(fset, value)
				}
			}

			enumLike := typeName != "" && (specHasIota || (len(valueSpec.Values) == 0 && prevEnumLike))
			prevEnumLike = specHasIota || (len(valueSpec.Values) == 0 && prevEnumLike)
			if !enumLike {
				continue
			}

			group, exists := groups[typeName]
			if !exists {
				group = &enumGroup{Line: fset.Position(valueSpec.Pos()).Line}
				groups[typeName] = group
				order = append(order, typeName)
			}
			for _, name := range valueSpec.Names {
				group.Members = append(group.Members, EnumMember{
					Name:  name.Name,
					Value: valueText,
				})
			}
		}
	}

	var out []EnumDecl
	for _, name := range order {
		group := groups[name]
		out = append(out, EnumDecl{
			Name:    name,
			Line:    group.Line,
			Members: group.Members,
		})
	}
	return out, nil
}

func writeJSON(v any) {
	enc := json.NewEncoder(os.Stdout)
	if err := enc.Encode(v); err != nil {
		fmt.Fprintf(os.Stderr, "ast-go-runner: cannot encode JSON: %v\n", err)
		os.Exit(1)
	}
}

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: ast-go-runner <extract-signatures|extract-enums> <file>")
		os.Exit(1)
	}

	op := os.Args[1]
	file := os.Args[2]

	switch op {
	case "extract-signatures":
		sigs, err := extractSignatures(file)
		if err != nil {
			fmt.Fprintf(os.Stderr, "ast-go-runner: %v\n", err)
			os.Exit(1)
		}
		writeJSON(sigs)
	case "extract-enums":
		enums, err := extractEnums(file)
		if err != nil {
			fmt.Fprintf(os.Stderr, "ast-go-runner: %v\n", err)
			os.Exit(1)
		}
		writeJSON(enums)
	default:
		fmt.Fprintf(os.Stderr, "unknown op: %s\n", op)
		os.Exit(1)
	}
}
