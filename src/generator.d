// Copyright © 2012, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/license.d.
module generator;

import packets : PacketGroup, Packet, Member, Constant;
import std.stream : Stream;
import std.string : format;
import std.cstream : dout;


void output(PacketGroup pg)
{
	Stream o = dout;

	o.writeHeader(pg);

	o.writeInterface(pg, pg.clientListenerTypeStr, pg.clientPackets);
	o.writeInterface(pg, pg.serverListenerTypeStr, pg.serverPackets);

	o.writeStruct(pg, pg.clientPackets);
	o.writeStruct(pg, pg.serverPackets);

	foreach(p; pg.clientPackets) {
		o.writeReadFunction(pg, p);
	}

	foreach(p; pg.serverPackets) {
		o.writeReadFunction(pg, p);
	}
}

void writeStruct(Stream o, PacketGroup pg, Packet[] packets)
{
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
			o.writefln("%s%s %s;", pg.indentStr, type, m.name);
			return;
		case ValueArray:
			auto type = pg.getMemberArrayType(m.type);
			o.writefln("%s%s %s;", pg.indentStr, type, m.name);
			return;
		case StructArray:
			o.writefln("%s%s[] %s;", pg.indentStr, m.type, m.name);
			return;
		}
	}

	foreach(p; packets) {
		o.writefln("struct %s", p.structName);
		o.writefln("{");
		foreach(m; p.members)
			printMember(m);
		o.writefln("}");
		o.writefln();
	}
}

void writeReadFunction(Stream o, PacketGroup pg, Packet p)
{
	bool server = p.from == Packet.From.Server;
	string li = server ? pg.serverListenerTypeStr : pg.clientListenerTypeStr;

	o.writefln("void %s(%s %s, %s %s)",
		p.readFuncName,
		pg.socketTypeStr,
		pg.socketNameStr,
		li, pg.listenerNameStr);

	o.writefln("{");

	o.writefln("%s%s %s;", pg.indentStr, p.structName, pg.packetNameStr);
	o.writefln();

	foreach(m; p.members)
		o.writeMember(pg, m, pg.indentStr);

	o.writefln();
	o.writefln("%s%s.%s(%s);",
		pg.indentStr,
		pg.listenerNameStr,
		p.listenerName,
		pg.packetNameStr);

	o.writefln("}");
	o.writefln();
}

void writeMember(Stream o, PacketGroup pg, Member m, string indent)
{
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
			o.writeMember(pg, child, indent ~ pg.indentStr);

		o.writefln("%s}", pg.indentStr);
	}
}

void writeInterface(Stream o, PacketGroup pg, string name, Packet[] packets)
{
	o.writefln("interface %s", name);
	o.writefln("{");
	foreach(p; packets) {
		o.writefln("%svoid %s(ref %s);", pg.indentStr, p.listenerName, p.structName);
	}
	o.writefln("}");
	o.writefln();
}

void writeHeader(Stream o, PacketGroup pg)
{
	o.writefln("module packets;");
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
	o.writefln("}");
	o.writefln();
	o.writefln("struct Slot {}",);
	o.writefln();
	o.writefln("struct Meta {}");
	o.writefln();
	o.writefln("struct ChunkMeta {}");
	o.writefln();
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
