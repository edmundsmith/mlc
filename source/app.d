import std.stdio, std.algorithm, std.range, std.conv, std.process, std.file, std.string, std.regex;
import pegged.grammar;

enum testStr = "
void add(int x, int y) lang C
{
    return x + y;
}

void sub(int x, int y) lang nasm
{
    mov eax, ecx
    sub eax, edx
    ret
}
";

mixin(`
FDecl:
	Code < Func+
	Func < CType LangDecl BBody / CInclude
	BBody < "{" Body "}"
	Body <~ (Inner ("{" Body "}")?)*
	Inner <- (space / !"{" !"}" .)
	TName < "struct"? identifier "*"*
	FName < identifier
	AName < identifier
	Arg < TName AName
	Args < Arg ("," Arg)*
	LangName < identifier
	CType < TName FName "(" Args ")"
	LangDecl < "lang" LangName
	CInclude < "#include \"" identifier ".h"? "\""
	
`.grammar);

void main(string[] args)
{
    foreach(i, arg; args[1..$])
	{
		auto src = arg.readText;
		auto headerfile = File(arg~".h", "w");
		auto parsed = src.FDecl.children[0];

		string[] objectFiles = [];
		foreach(fi, func; parsed.children)
		{
			if(func.children[0].name == "FDecl.CInclude")
			{
				headerfile.writeln(func.parsedString);
				continue;
			}
			else
			{
				headerfile.writeln(headerise(func), ";");

				writeln(func.children);
				auto lang = func.children[1].children[0].parsedString.strip();
				writeln(lang);

				auto fname = func.children[0].children[1].parsedString;
				writeln(fname);
				if(lang !in languages)
				{
					stderr.writeln("Error: language ", lang, " not understood");
					continue;
				}
				Compilation compilation = languages[lang];
				auto funcFileName = (arg ~ "." ~ fname);
				{
					auto funcFile = (funcFileName ~ languages[lang].langExt).File("w");
					funcFile.writeln(compilation.genBody(func).format(arg~".h", func.children[2].children[0].parsedString));
				}
				writefln("Running \"%s\"", compilation.compileCommand.format(funcFileName ~ languages[lang].langExt, funcFileName ~ ".o"));
				compilation.compileCommand.format(funcFileName ~ languages[lang].langExt, funcFileName ~ ".o").executeShell;
				objectFiles ~= funcFileName ~ ".o";
			}
		}
		"ld -r %(%s%| %) -o %s".format(objectFiles, arg~".o").writeln;
		"ld -r %(%s%| %) -o %s".format(objectFiles, arg~".o").executeShell;

		"gcc %s -o %s".format(arg~".o", arg.replaceAll(ctRegex!"\\..*", "")).writeln;
		"gcc %s -o %s".format(arg~".o", arg.replaceAll(ctRegex!"\\..*", "")).executeShell;
	}
}

struct Compilation
{
	string langName;
	string langExt;
	string compileCommand;
	string function(ParseTree) genBody;

}

enum languages = [
	"C":Compilation("C", ".c", "gcc -m64 %s -c -o %s",
		(ParseTree parseTree) {
			return "#include \"%s\"\n\n" ~ parseTree.children[0].parsedString ~ "\n{%s}";
		}),
	"nasm":Compilation("nasm",".s","nasm %s -o %s -fELF64",
		(ParseTree pt) {
			return "[global %s]\n[bits 64]\n\n%s:;%s\n%s"
				.format(pt.children[0].children[1].parsedString,
						pt.children[0].children[1].parsedString, "%s", "%s");
		})
	];

string parsedString(PT)(PT parsed)
{
	with(parsed) return input[begin..end];
}

string headerise(PT)(PT parsed)
{
	with(parsed.children[0]) return input[begin..end];
}
