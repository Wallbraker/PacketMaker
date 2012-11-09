// Copyright © 2012, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/license.d.
module generator;

import packets : PacketGroup, Packet, Member, Constant;
import std.conv : to;
import std.stream : Stream, BufferedFile;
import std.string : format;
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
	bf.writePacketsHeader(packetsPkg);

	foreach(p; pg.allPackets)
		bf.writeStruct(pg, p, "");
	bf.close();


	// Proxy file.
	bf.create(marshallingFile);
	bf.writeHeader(marshallingPkg, [packetsPkg]);

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

	o.writefln();
	o.writefln("%svoid %sProxy(%s %s, %s %s, ubyte id)",
		indent,
		fromStr,
		pg.socketTypeStr,
		fromStr,
		pg.socketTypeStr,
		toStr);
	o.writefln("%s{", indent);
	o.writefln("%sswitch(id) {", extraIndent);

	foreach(p; pg.clientPackets)
		o.writeProxyCase(pg, p, extraIndent, fromStr, toStr);

	o.writefln("%sdefault:", extraIndent);
	o.writefln("%sthrow new Exception(\"invalid packet\");", extraIndent ~ pg.indentStr);
	o.writefln("%s}", extraIndent);
	o.writefln("%s}", indent);
}

void writeProxyCase(Stream o, PacketGroup pg, Packet p,
                    string indent, string fromStr, string toStr)
{
	o.writefln("%scase 0x%02s:", indent, to!string(p.id, 16));

	// All folowing statements on new indent.
	indent = indent ~ pg.indentStr;
	string extraIndent = indent ~ pg.indentStr;

	o.writefln("%s%s %s;", indent, p.structName, pg.packetNameStr);

	o.writefln();
	o.writefln("%s%s(%s, %s);",
		indent,
		p.readFuncName,
		fromStr,
		pg.packetNameStr);
	o.writefln("%s//writefln(\"%s -> %%s\", \"%s\");", indent, fromStr, p.structName);
	o.writefln("%s%s(%s, %s);",
		indent,
		p.writeFuncName,
		toStr,
		pg.packetNameStr);

	o.writefln("%sbreak;", indent);
}

void writeStruct(Stream o, PacketGroup pg, Packet p, string indent)
{
	string extraIndent = indent ~ pg.indentStr;

	o.writefln();

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
			o.writefln("%s%s %s;", extraIndent, type, m.name);
			return;
		case ValueArray:
			auto type = pg.getMemberArrayType(m.type);
			o.writefln("%s%s %s;", extraIndent, type, m.name);
			return;
		case StructArray:
			o.writefln("%s%s[] %s;", extraIndent, m.type, m.name);
			return;
		}
	}

	o.writefln("%sstruct %s", indent, p.structName);
	o.writefln("%s{", indent);

	o.writefln("%sconst ubyte %s = 0x%02s;", extraIndent, pg.idStr, to!string(p.id, 16));
	o.writefln("%sconst From %s = From.%s;", extraIndent, pg.fromStr, to!string(p.from));
	o.writefln();

	foreach(m; p.members)
		printMember(m);

	o.writefln("%s}", indent);
}

void writeReadFunction(Stream o, PacketGroup pg, Packet p, string indent)
{
	string extraIndent = indent ~ pg.indentStr;

	o.writefln();
	o.writefln("%svoid %s(%s %s, ref %s %s)",
		indent,
		p.readFuncName,
		pg.socketTypeStr,
		pg.socketNameStr,
		p.structName,
		pg.packetNameStr);

	o.writefln("%s{", indent);

	foreach(m; p.members)
		o.writeReadMember(pg, m, extraIndent);

	o.writefln("%s}", indent);
}

void writeReadMember(Stream o, PacketGroup pg, Member m, string indent)
{
	string extraIndent = indent ~ pg.indentStr;

	final switch(m.kind) with (Member.Kind) {
	case Value:
		o.writefln("%s%s.%s = %s.%s();",
			indent,
			pg.packetNameStr,
			m.name,
			pg.socketNameStr,
			pg.getReadFunc(m.type));
		break;
	case ValueAnon:
		o.writefln("%s%s.%s();",
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
			o.writefln("%suint %s = %s.%s();",
				indent,
				lengthField,
				pg.socketNameStr,
				pg.getReadFunc(m.lengthType));
		}

		o.writefln("%s%s.%s = %s.%s(%s);",
			indent,
			pg.packetNameStr,
			m.name,
			pg.socketNameStr,
			pg.getReadArrayFunc(m.type),
			lengthField);
		break;
	case CondMembers:
		o.writefln("%sif (%s %s %s) {",
			indent,
			pg.packetNameStr ~ "." ~ m.condField,
			m.condCmp,
			m.condValue.str);

		foreach(child; m.members)
			o.writeReadMember(pg, child, extraIndent);

		o.writefln("%s}", indent);
	}
}

void writeWriteFunction(Stream o, PacketGroup pg, Packet p, string indent)
{
	string extraIndent = indent ~ pg.indentStr;

	o.writefln();
	o.writefln("%svoid %s(%s %s, ref %s %s)",
		indent,
		p.writeFuncName,
		pg.socketTypeStr,
		pg.socketNameStr,
		p.structName,
		pg.packetNameStr);

	o.writefln("%s{", indent);

	o.writefln("%s%s.%s(%s.%s);",
		extraIndent,
		pg.socketNameStr,
		pg.getWriteFunc("ubyte"),
		p.structName,
		pg.idStr);

	foreach(m; p.members)
		o.writeWriteMember(pg, m, extraIndent);

	o.writefln("%s}", indent);
}

void writeWriteMember(Stream o, PacketGroup pg, Member m, string indent)
{
	string extraIndent = indent ~ pg.indentStr;

	final switch(m.kind) with (Member.Kind) {
	case Value:
		o.writefln("%s%s.%s(%s.%s);",
			indent,
			pg.socketNameStr,
			pg.getWriteFunc(m.type),
			pg.packetNameStr,
			m.name);
		break;
	case ValueAnon:
		o.writefln("%s%s.%s(%s);",
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

		o.writefln("%s%s.%s(cast(%s)(%s.%s.%s));",
				indent,
				pg.socketNameStr,
				pg.getWriteFunc(m.lengthType),
				pg.getMemberType(m.lengthType),
				pg.packetNameStr,
				m.name,
				pg.lengthStr);

		o.writefln("%s%s.%s(%s.%s);",
			indent,
			pg.socketNameStr,
			pg.getWriteArrayFunc(m.type),
			pg.packetNameStr,
			m.name);
		break;
	case StructArray:
		if (pg.getMemberArrayType(m.type)[$-1] == '*')
			o.writefln("%s%s.%s(%s.%s, %s.%s);",
				indent,
				pg.socketNameStr,
				pg.getWriteArrayFunc(m.type),
				pg.packetNameStr,
				m.name,
				pg.packetNameStr,
				m.times);
		else
			o.writefln("%s%s.%s(%s.%s);",
				indent,
				pg.socketNameStr,
				pg.getWriteArrayFunc(m.type),
				pg.packetNameStr,
				m.name);
		break;
	case CondMembers:
		o.writefln("%sif (%s.%s %s %s) {",
			indent,
			pg.packetNameStr,
			m.condField,
			m.condCmp,
			m.condValue.str);

		foreach(child; m.members)
			o.writeReadMember(pg, child, extraIndent);

		o.writefln("%s}", indent);
	}
}

void writeInterface(Stream o, PacketGroup pg, string name, Packet[] packets, string indent)
{
	string extraIndent = indent ~ pg.indentStr;

	o.writefln();
	o.writefln("%sinterface %s", name, indent);
	o.writefln("%s{", indent);
	foreach(p; packets) {
		o.writefln("%svoid %s(ref %s);", extraIndent, p.listenerName, p.structName);
	}
	o.writefln("%s}", indent);
}

void writeHeader(Stream o, string name, string[] imports)
{
	o.writefln("module %s;", name);
	o.writefln();
	foreach(i; imports) {
		o.writefln("import %s;", i);
	}
	o.writefln();
}

void writePacketsHeader(Stream o, string name)
{
	o.writeHeader(name, null);

	o.writefln();
	o.writefln();
	o.writefln("struct Slot {}",);
	o.writefln();
	o.writefln("struct Meta {}");
	o.writefln();
	o.writefln("struct ChunkMeta {}");
}

void writeMinecraftSocket(Stream o, PacketGroup pg)
{
	o.writefln();
	o.writefln("class %s", pg.socketTypeStr);
	o.writefln("{");
	foreach(t; pg.readFuncs.keys) {
		o.writefln("%sabstract %s %s();",
			pg.indentStr,
			pg.typeMap[t],
			pg.readFuncs[t]);
	}
	o.writefln();
	foreach(t; pg.readArrayFuncs.keys) {
		o.writefln("%sabstract %s %s(uint);",
			pg.indentStr,
			pg.typeArrayMap[t],
			pg.readArrayFuncs[t]);
	}
	o.writefln();
	foreach(t; pg.writeFuncs.keys) {
		o.writefln("%sabstract void %s(%s);",
			pg.indentStr,
			pg.writeFuncs[t],
			pg.typeMap[t]);
	}
	o.writefln();
	foreach(t; pg.writeArrayFuncs.keys) {
		if (pg.typeArrayMap[t][$-1] == '*')
			o.writefln("%sabstract void %s(%s, uint);",
				pg.indentStr,
				pg.writeArrayFuncs[t],
				pg.typeArrayMap[t]);
		else
			o.writefln("%sabstract void %s(%s);",
				pg.indentStr,
				pg.writeArrayFuncs[t],
				pg.typeArrayMap[t]);
	}
	o.writefln("}");
}


/*
 *
 * Silly accessor helpers.
 *
 */


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
