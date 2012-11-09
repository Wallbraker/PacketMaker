// Copyright © 2012, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/license.d.
module generator;

import packets : PacketGroup, Packet, Member, Constant;
import std.conv : to;
import std.stream : Stream, BufferedFile;
import std.string : format, xformat;
import std.cstream : dout;
import std.file : mkdir, exists;


void output(PacketGroup pg)
{
	string outDir = "output";
	string proxyFile = "output/proxy.d";
	string proxyPkg = "proxy";
	string packetsFile = "output/packets.d";
	string packetsPkg = "packets";
	string marshallingFile = "output/marshalling.d";
	string marshallingPkg = "marshalling";


	if (!exists(outDir))
		mkdir(outDir);

	BufferedFile bf = new BufferedFile();


	// Packets file.
	bf.create(packetsFile);
	bf.writePacketsHeader(pg, packetsPkg);

	foreach(p; pg.allPackets)
		bf.writeStruct(pg, p, "");
	bf.close();


	// Proxy file.
	bf.create(marshallingFile);
	bf.writeHeader(marshallingPkg, [packetsPkg]);
	bf.wfln();
	bf.writeMinecraftSocket(pg);

	foreach(p; pg.allPackets)
		bf.writeReadFunction(pg, p, "");

	foreach(p; pg.allPackets)
		bf.writeWriteFunction(pg, p, "");
	bf.close();


	// Proxy file.
	bf.create(proxyFile);
	bf.writeHeader(proxyPkg, [packetsPkg, marshallingPkg]);
	bf.writeProxyFunction(pg, pg.clientPackets, "", "client", "server");
	bf.writeProxyFunction(pg, pg.serverPackets, "", "server", "client");
	bf.close();
}

void writeProxyFunction(Stream o, PacketGroup pg, Packet[] packets,
                        string indent, string fromStr, string toStr)
{
	string extraIndent = indent ~ pg.indentStr;

	o.wfln();
	o.wfln("%svoid %sProxy(%s %s, %s %s, ubyte id)",
		indent,
		fromStr,
		pg.socketTypeStr,
		fromStr,
		pg.socketTypeStr,
		toStr);
	o.wfln("%s{", indent);
	o.wfln("%sswitch(id) {", extraIndent);

	foreach(p; pg.clientPackets)
		o.writeProxyCase(pg, p, extraIndent, fromStr, toStr);

	o.wfln("%sdefault:", extraIndent);
	o.wfln("%sthrow new Exception(\"invalid packet\");", extraIndent ~ pg.indentStr);
	o.wfln("%s}", extraIndent);
	o.wfln("%s}", indent);
}

void writeProxyCase(Stream o, PacketGroup pg, Packet p,
                    string indent, string fromStr, string toStr)
{
	o.wfln("%scase 0x%.2X:", indent, p.id);

	// All folowing statements on new indent.
	indent = indent ~ pg.indentStr;
	string extraIndent = indent ~ pg.indentStr;

	o.wfln("%s%s %s;", indent, p.structName, pg.packetNameStr);

	o.wfln();
	o.wfln("%s%s(%s, %s);",
		indent,
		p.readFuncName,
		fromStr,
		pg.packetNameStr);
	o.wfln("%s//wfln(\"%s -> %%s\", \"%s\");", indent, fromStr, p.structName);
	o.wfln("%s%s(%s, %s);",
		indent,
		p.writeFuncName,
		toStr,
		pg.packetNameStr);

	o.wfln("%sbreak;", indent);
}

void writeStruct(Stream o, PacketGroup pg, Packet p, string indent)
{
	string extraIndent = indent ~ pg.indentStr;

	o.wfln();

	void printMember(Member m) {
		final switch(m.kind) with(Member.Kind) {
		case ValueAnon:
			return;
		case CondMembers:
			foreach(child; m.members)
				printMember(child);
			return;
		case Value:
			auto type = pg.getMemberType(m.type);
			o.wfln("%s%s %s;", extraIndent, type, m.name);
			return;
		case ValueArray:
		case StructArray:
			auto type = pg.getMemberArrayType(m.type);
			o.wfln("%s%s %s;", extraIndent, type, m.name);
			return;
		}
	}

	o.wfln("%sstruct %s", indent, p.structName);
	o.wfln("%s{", indent);

	o.wfln("%sconst ubyte %s = 0x%.2X;", extraIndent, pg.idStr, p.id);
	o.wfln("%sconst From %s = From.%s;", extraIndent, pg.fromStr, to!string(p.from));
	o.wfln();

	foreach(m; p.members)
		printMember(m);

	o.wfln("%s}", indent);
}

void writeReadFunction(Stream o, PacketGroup pg, Packet p, string indent)
{
	string extraIndent = indent ~ pg.indentStr;

	o.wfln();
	o.wfln("%svoid %s(%s %s, ref %s %s)",
		indent,
		p.readFuncName,
		pg.socketTypeStr,
		pg.socketNameStr,
		p.structName,
		pg.packetNameStr);

	o.wfln("%s{", indent);

	foreach(m; p.members)
		o.writeReadMember(pg, m, extraIndent);

	o.wfln("%s}", indent);
}

void writeReadMember(Stream o, PacketGroup pg, Member m, string indent)
{
	string extraIndent = indent ~ pg.indentStr;

	final switch(m.kind) with (Member.Kind) {
	case Value:
		o.wfln("%s%s.%s = %s.%s();",
			indent,
			pg.packetNameStr,
			m.name,
			pg.socketNameStr,
			pg.getReadFunc(m.type));
		break;
	case ValueAnon:
		o.wfln("%s%s.%s();",
			indent,
			pg.socketNameStr,
			pg.getReadFunc(m.type));
		break;
	case ValueArray:
	case StructArray:
		string lengthField;
		if (m.times !is null) {
			lengthField = pg.packetNameStr ~ "." ~ m.times;
		} else {
			lengthField = m.name ~ pg.lengthSuffixStr;
			o.wfln("%suint %s = %s.%s();",
				indent,
				lengthField,
				pg.socketNameStr,
				pg.getReadFunc(m.lengthType));
		}

		o.wfln("%s%s.%s = %s.%s(%s);",
			indent,
			pg.packetNameStr,
			m.name,
			pg.socketNameStr,
			pg.getReadArrayFunc(m.type),
			lengthField);
		break;
	case CondMembers:
		o.wfln("%sif (%s %s %s) {",
			indent,
			pg.packetNameStr ~ "." ~ m.condField,
			m.condCmp,
			m.condValue.str);

		foreach(child; m.members)
			o.writeReadMember(pg, child, extraIndent);

		o.wfln("%s}", indent);
	}
}

void writeWriteFunction(Stream o, PacketGroup pg, Packet p, string indent)
{
	string extraIndent = indent ~ pg.indentStr;

	o.wfln();
	o.wfln("%svoid %s(%s %s, ref %s %s)",
		indent,
		p.writeFuncName,
		pg.socketTypeStr,
		pg.socketNameStr,
		p.structName,
		pg.packetNameStr);

	o.wfln("%s{", indent);

	o.wfln("%s%s.%s(%s.%s);",
		extraIndent,
		pg.socketNameStr,
		pg.getWriteFunc("ubyte"),
		p.structName,
		pg.idStr);

	foreach(m; p.members)
		o.writeWriteMember(pg, m, extraIndent);

	o.wfln("%s}", indent);
}

void writeWriteMember(Stream o, PacketGroup pg, Member m, string indent)
{
	string extraIndent = indent ~ pg.indentStr;

	final switch(m.kind) with (Member.Kind) {
	case Value:
		o.wfln("%s%s.%s(%s.%s);",
			indent,
			pg.socketNameStr,
			pg.getWriteFunc(m.type),
			pg.packetNameStr,
			m.name);
		break;
	case ValueAnon:
		o.wfln("%s%s.%s(%s);",
			indent,
			pg.socketNameStr,
			pg.getWriteFunc(m.type),
			m.def.str);
		break;
	case ValueArray:
		if (m.times !is null)
			goto case StructArray;
		if (pg.getMemberArrayType(m.type)[$-1] == '*')
			throw new Exception(format(
				"Can't write pointer arrays without length (%s)",
				m.name));

		o.wfln("%s%s.%s(cast(%s)(%s.%s.%s));",
				indent,
				pg.socketNameStr,
				pg.getWriteFunc(m.lengthType),
				pg.getMemberType(m.lengthType),
				pg.packetNameStr,
				m.name,
				pg.lengthStr);

		o.wfln("%s%s.%s(%s.%s);",
			indent,
			pg.socketNameStr,
			pg.getWriteArrayFunc(m.type),
			pg.packetNameStr,
			m.name);
		break;
	case StructArray:
		if (pg.getMemberArrayType(m.type)[$-1] == '*')
			o.wfln("%s%s.%s(%s.%s, %s.%s);",
				indent,
				pg.socketNameStr,
				pg.getWriteArrayFunc(m.type),
				pg.packetNameStr,
				m.name,
				pg.packetNameStr,
				m.times);
		else
			o.wfln("%s%s.%s(%s.%s);",
				indent,
				pg.socketNameStr,
				pg.getWriteArrayFunc(m.type),
				pg.packetNameStr,
				m.name);
		break;
	case CondMembers:
		o.wfln("%sif (%s.%s %s %s) {",
			indent,
			pg.packetNameStr,
			m.condField,
			m.condCmp,
			m.condValue.str);

		foreach(child; m.members)
			o.writeReadMember(pg, child, extraIndent);

		o.wfln("%s}", indent);
	}
}

void writeInterface(Stream o, PacketGroup pg, string name, Packet[] packets, string indent)
{
	string extraIndent = indent ~ pg.indentStr;

	o.wfln();
	o.wfln("%sinterface %s", name, indent);
	o.wfln("%s{", indent);
	foreach(p; packets) {
		o.wfln("%svoid %s(ref %s);", extraIndent, p.listenerName, p.structName);
	}
	o.wfln("%s}", indent);
}

void writeHeader(Stream o, string name, string[] imports)
{
	o.wfln("module %s;", name);
	o.wfln();
	foreach(i; imports) {
		o.wfln("import %s;", i);
	}
	o.wfln();
}

void writePacketsHeader(Stream o, PacketGroup pg, string name)
{
	o.writeHeader(name, null);

	o.wfln();
	o.wfln();
	o.wfln("enum From {");
	o.wfln("%sClient,", pg.indentStr);
	o.wfln("%sServer,", pg.indentStr);
	o.wfln("%sBoth", pg.indentStr);
	o.wfln("}");
	o.wfln();
	o.wfln("struct Slot {}");
	o.wfln();
	o.wfln("struct Meta {}");
	o.wfln();
	o.wfln("struct ChunkMeta {}");
}

void writeMinecraftSocket(Stream o, PacketGroup pg)
{
	o.wfln();
	o.wfln("class %s", pg.socketTypeStr);
	o.wfln("{");
	foreach(t; pg.readFuncs.keys) {
		o.wfln("%sabstract %s %s();",
			pg.indentStr,
			pg.typeMap[t],
			pg.readFuncs[t]);
	}
	o.wfln();
	foreach(t; pg.readArrayFuncs.keys) {
		o.wfln("%sabstract %s %s(uint);",
			pg.indentStr,
			pg.typeArrayMap[t],
			pg.readArrayFuncs[t]);
	}
	o.wfln();
	foreach(t; pg.writeFuncs.keys) {
		o.wfln("%sabstract void %s(%s);",
			pg.indentStr,
			pg.writeFuncs[t],
			pg.typeMap[t]);
	}
	o.wfln();
	foreach(t; pg.writeArrayFuncs.keys) {
		if (pg.typeArrayMap[t][$-1] == '*')
			o.wfln("%sabstract void %s(%s, uint);",
				pg.indentStr,
				pg.writeArrayFuncs[t],
				pg.typeArrayMap[t]);
		else
			o.wfln("%sabstract void %s(%s);",
				pg.indentStr,
				pg.writeArrayFuncs[t],
				pg.typeArrayMap[t]);
	}
	o.wfln("}");
}


/*
 *
 * Silly accessor helpers.
 *
 */


void wfln()(Stream o)
{
	o.writefln();
}

void wfln(Args...)(Stream o, string fmt, Args args)
{
	o.writefln("%s", xformat!char(fmt, args));
}

string getMemberType(PacketGroup pg, string type)
{
	try {
		return pg.typeMap[type];
	} catch (Exception e) {
		throw new Exception(format("Unhandled type (%s)", type));
	}
}

string getMemberArrayType(PacketGroup pg, string type)
{
	try {
		return pg.typeArrayMap[type];
	} catch (Exception e) {
		throw new Exception(format("Unhandled type (%s)", type));
	}
}

string getReadFunc(PacketGroup pg, string type)
{
	try {
		return pg.readFuncs[type];
	} catch (Exception e) {
		throw new Exception(format("Unhandled type (%s)", type));
	}
}

string getReadArrayFunc(PacketGroup pg, string type)
{
	try {
		return pg.readArrayFuncs[type];
	} catch (Exception e) {
		throw new Exception(format("Unhandled type (%s)", type));
	}
}

string getWriteFunc(PacketGroup pg, string type)
{
	try {
		return pg.writeFuncs[type];
	} catch (Exception e) {
		throw new Exception(format("Unhandled type (%s)", type));
	}
}

string getWriteArrayFunc(PacketGroup pg, string type)
{
	try {
		return pg.writeArrayFuncs[type];
	} catch (Exception e) {
		throw new Exception(format("Unhandled type (%s)", type));
	}
}
