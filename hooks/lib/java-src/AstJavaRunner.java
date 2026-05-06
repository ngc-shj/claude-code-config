import com.github.javaparser.JavaParser;
import com.github.javaparser.ParseResult;
import com.github.javaparser.ParserConfiguration;
import com.github.javaparser.Position;
import com.github.javaparser.ast.CompilationUnit;
import com.github.javaparser.ast.body.ClassOrInterfaceDeclaration;
import com.github.javaparser.ast.body.EnumConstantDeclaration;
import com.github.javaparser.ast.body.EnumDeclaration;
import com.github.javaparser.ast.body.MethodDeclaration;
import com.github.javaparser.ast.body.Parameter;
import com.github.javaparser.ast.body.RecordDeclaration;
import com.github.javaparser.ast.body.TypeDeclaration;

import java.io.IOException;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

public final class AstJavaRunner {
  private AstJavaRunner() {}

  private static final class ParamShape {
    final String name;
    final String type;
    final boolean optional;
    final boolean rest;
    final boolean hasDefault;

    ParamShape(String name, String type, boolean optional, boolean rest, boolean hasDefault) {
      this.name = name;
      this.type = type;
      this.optional = optional;
      this.rest = rest;
      this.hasDefault = hasDefault;
    }
  }

  private static final class Signature {
    final String name;
    final String owner;
    final int line;
    final String kind;
    final List<ParamShape> params;
    final String returnType;

    Signature(String name, String owner, int line, String kind, List<ParamShape> params, String returnType) {
      this.name = name;
      this.owner = owner;
      this.line = line;
      this.kind = kind;
      this.params = params;
      this.returnType = returnType;
    }
  }

  private static final class EnumMember {
    final String name;
    final String value;

    EnumMember(String name, String value) {
      this.name = name;
      this.value = value;
    }
  }

  private static final class EnumDecl {
    final String name;
    final int line;
    final List<EnumMember> members;

    EnumDecl(String name, int line, List<EnumMember> members) {
      this.name = name;
      this.line = line;
      this.members = members;
    }
  }

  private static CompilationUnit parseFile(String file) throws IOException {
    JavaParser parser = new JavaParser(new ParserConfiguration());
    ParseResult<CompilationUnit> result = parser.parse(Path.of(file));
    if (!result.isSuccessful() || result.getResult().isEmpty()) {
      throw new IOException("JavaParser could not parse " + file);
    }
    return result.getResult().get();
  }

  private static int lineOf(MethodDeclaration node) {
    return node.getBegin().map(p -> p.line).orElse(1);
  }

  private static List<ParamShape> paramShapes(MethodDeclaration decl) {
    List<ParamShape> out = new ArrayList<>();
    for (Parameter parameter : decl.getParameters()) {
      out.add(new ParamShape(
          parameter.getNameAsString(),
          parameter.getType().toString(),
          false,
          parameter.isVarArgs(),
          false));
    }
    return out;
  }

  private static Signature methodSignature(MethodDeclaration decl, String owner) {
    return new Signature(
        decl.getNameAsString(),
        owner,
        lineOf(decl),
        "method",
        paramShapes(decl),
        decl.getType().toString());
  }

  private static List<Signature> extractSignatures(String file) throws IOException {
    CompilationUnit unit = parseFile(file);
    List<Signature> out = new ArrayList<>();

    for (TypeDeclaration<?> type : unit.getTypes()) {
      if (type instanceof ClassOrInterfaceDeclaration classDecl) {
        for (MethodDeclaration method : classDecl.getMethods()) {
          out.add(methodSignature(method, classDecl.getNameAsString()));
        }
      } else if (type instanceof EnumDeclaration enumDecl) {
        for (MethodDeclaration method : enumDecl.getMethods()) {
          out.add(methodSignature(method, enumDecl.getNameAsString()));
        }
      } else if (type instanceof RecordDeclaration recordDecl) {
        for (MethodDeclaration method : recordDecl.getMethods()) {
          out.add(methodSignature(method, recordDecl.getNameAsString()));
        }
      }
    }

    return out;
  }

  private static List<EnumDecl> extractEnums(String file) throws IOException {
    CompilationUnit unit = parseFile(file);
    List<EnumDecl> out = new ArrayList<>();

    for (EnumDeclaration enumDecl : unit.findAll(EnumDeclaration.class)) {
      List<EnumMember> members = new ArrayList<>();
      for (EnumConstantDeclaration constant : enumDecl.getEntries()) {
        String value = constant.getArguments().isEmpty() ? null : constant.getArguments().toString();
        members.add(new EnumMember(constant.getNameAsString(), value));
      }
      out.add(new EnumDecl(
          enumDecl.getNameAsString(),
          enumDecl.getBegin().map(p -> p.line).orElse(1),
          members));
    }

    return out;
  }

  private static String jsonString(String value) {
    if (value == null) {
      return "null";
    }
    String escaped = value
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t");
    return "\"" + escaped + "\"";
  }

  private static String jsonForParams(List<ParamShape> params) {
    List<String> out = new ArrayList<>();
    for (ParamShape param : params) {
      out.add("{"
          + "\"name\":" + jsonString(param.name) + ","
          + "\"type\":" + jsonString(param.type) + ","
          + "\"optional\":" + param.optional + ","
          + "\"rest\":" + param.rest + ","
          + "\"hasDefault\":" + param.hasDefault
          + "}");
    }
    return "[" + String.join(",", out) + "]";
  }

  private static String jsonForSignatures(List<Signature> signatures) {
    List<String> out = new ArrayList<>();
    for (Signature sig : signatures) {
      out.add("{"
          + "\"name\":" + jsonString(sig.name) + ","
          + "\"owner\":" + jsonString(sig.owner) + ","
          + "\"line\":" + sig.line + ","
          + "\"kind\":" + jsonString(sig.kind) + ","
          + "\"params\":" + jsonForParams(sig.params) + ","
          + "\"returnType\":" + jsonString(sig.returnType)
          + "}");
    }
    return "[" + String.join(",", out) + "]";
  }

  private static String jsonForEnums(List<EnumDecl> enums) {
    List<String> out = new ArrayList<>();
    for (EnumDecl decl : enums) {
      List<String> members = new ArrayList<>();
      for (EnumMember member : decl.members) {
        members.add("{"
            + "\"name\":" + jsonString(member.name) + ","
            + "\"value\":" + jsonString(member.value)
            + "}");
      }
      out.add("{"
          + "\"name\":" + jsonString(decl.name) + ","
          + "\"line\":" + decl.line + ","
          + "\"members\":[" + String.join(",", members) + "]"
          + "}");
    }
    return "[" + String.join(",", out) + "]";
  }

  public static void main(String[] args) throws Exception {
    if (args.length != 2) {
      System.err.println("usage: AstJavaRunner <extract-signatures|extract-enums> <file>");
      System.exit(1);
    }

    String op = args[0];
    String file = args[1];
    if ("extract-signatures".equals(op)) {
      System.out.print(jsonForSignatures(extractSignatures(file)));
    } else if ("extract-enums".equals(op)) {
      System.out.print(jsonForEnums(extractEnums(file)));
    } else {
      System.err.println("unknown op: " + op);
      System.exit(1);
    }
  }
}
