import std.stdio, std.algorithm, std.range, std.conv, std.process, std.file, std.string, std.regex;
import pegged.grammar;

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
		string[] delayedCommands = [];
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

				auto lang = func.children[1].children[0].parsedString.strip();
				auto fname = func.children[0].children[1].parsedString;

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
				delayedCommands ~= compilation.compileCommand.format(funcFileName ~ languages[lang].langExt, funcFileName ~ ".o");

				objectFiles ~= funcFileName ~ ".o";
			}
		}

		headerfile.close();
		
		foreach(cmd; delayedCommands)
		{
			cmd.execDisplayErrors;
		}

		auto fnameNoExt = arg.replaceAll(ctRegex!"\\..*", "");

		"ld -r %(%s%| %) -o %s".format(objectFiles, fnameNoExt~".o").execDisplayErrors;

		"gcc %s -o %s".format(fnameNoExt~".o", fnameNoExt).execDisplayErrors;
	}
}

void execDisplayErrors(string cmd)
{
	auto result = cmd.executeShell;
	if(result.status != 0)
	{
		writefln("Running \"%s\" resulted in failure:\n%s", cmd, result.output);
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
			return "#include \"%s\"\n\n" ~ parseTree.children[0].parsedString ~ "\n{\n%s}";
		}),
	"nasm":Compilation("nasm",".s","nasm %s -o %s -fELF64",
		(ParseTree pt) {
			return "[global %s]\n[bits 64]\n\n%s:;%s\n%s"
				.format(pt.children[0].children[1].parsedString,
						pt.children[0].children[1].parsedString, "%s", "%s");
		}),
	//The D compiler isn't fond of having a non-extension '.' in filenames
	"D":Compilation("D", ".d", "mv %1$s tmp___.d; dmd tmp___.d -of=%2$s -shared -L-fELF64 -c -betterC; mv tmp___.d %1$s",
		(ParseTree pt){
			return "//\"%1$s\"\nmodule %1$s;\nextern(C) export " ~ pt.children[0].parsedString ~ "\n{\n%2$s}"; 
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
