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
	o.writefln("\tabstract bool readBool();");
	o.writefln("\tabstract byte readByte();");
	o.writefln("\tabstract ubyte readUbyte();");
	o.writefln("\tabstract short readShort();");
	o.writefln("\tabstract ushort readUshort();");
	o.writefln("\tabstract int readInt();");
	o.writefln("\tabstract uint readUint();");
	o.writefln("\tabstract long readLong();");
	o.writefln("\tabstract ulong readUlong();");
	o.writefln("\tabstract float readFloat();");
	o.writefln("\tabstract double readDouble();");
	o.writefln("\tabstract string readUSC();");
	o.writefln("\tabstract Meta* readMeta();");
	o.writefln("\tabstract Slot* readSlot();");
	o.writefln();
	o.writefln("\tabstract bool[] readBoolArray(uint);");
	o.writefln("\tabstract byte[] readByteArray(uint);");
	o.writefln("\tabstract ubyte[] readUbyteArray(uint);");
	o.writefln("\tabstract short[] readShortArray(uint);");
	o.writefln("\tabstract ushort[] readUshortArray(uint);");
	o.writefln("\tabstract int[] readIntArray(uint);");
	o.writefln("\tabstract uint[] readUintArray(uint);");
	o.writefln("\tabstract long[] readLongArray(uint);");
	o.writefln("\tabstract ulong[] readUlongArray(uint);");
	o.writefln("\tabstract float[] readFloatArray(uint);");
	o.writefln("\tabstract double[] readDoubleArray(uint);");
	o.writefln("\tabstract Meta* readMetaArray(uint);");
	o.writefln("\tabstract Slot* readSlotArray(uint);");
	o.writefln("\tabstract ChunkMeta[] readChunkMetaArray(uint);");
	o.writefln("}");
	o.writefln();
	o.writefln("struct Slot {}",);
	o.writefln();
	o.writefln("struct Meta {}");
	o.writefln();
	o.writefln("struct ChunkMeta {}");
	o.writefln();
}

string getReadFunc(PacketGroup pg, string type)
{
	switch(type) {
	// Primitive
	case "bool": return "readBool";
	case "byte": return "readByte";
	case "ubyte": return "readUbyte";
	case "int": return "readInt";
	case "uint": return "readUint";
	case "short": return "readShort";
	case "ushort": return "readUshort";
	case "long": return "readLong";
	case "ulong": return "readUlong";
	case "float": return "readFloat";
	case "double": return "readDouble";
	case "string": return "readUSC";
	// Meta
	case "slot": return "readSlot";
	case "meta": return "readMeta";
	default:
		throw new Exception(format("Unhandled type (%s)", type));
	}
}

string getReadArrayFunc(PacketGroup pg, string type)
{
	switch(type) {
	// Primitive
	case "bool": return "readBoolArray";
	case "byte": return "readByteArray";
	case "ubyte": return "readUbyteArray";
	case "int": return "readIntArray";
	case "uint": return "readUintArray";
	case "short": return "readShortArray";
	case "ushort": return "readUshortArray";
	case "long": return "readLongArray";
	case "ulong": return "readUlongArray";
	case "float": return "readFloatArray";
	case "double": return "readDoubleArray";
	// Meta
	case "slot": return "readSlotArray";
	case "meta": return "readMetaArray";
	case "ChunkMeta": return "readChunkMetaArray";
	default:
		throw new Exception(format("Unhandled type (%s)", type));
	}
}

string getMemberType(PacketGroup pg, string type)
{
	switch(type) {
	// Primitive
	case "bool": return "bool";
	case "byte": return "byte";
	case "ubyte": return "ubyte";
	case "int": return "int";
	case "uint": return "uint";
	case "short": return "short";
	case "ushort": return "ushort";
	case "long": return "long";
	case "ulong": return "ulong";
	case "float": return "float";
	case "double": return "double";
	case "string": return "string";
	// Meta
	case "slot": return "Slot*";
	case "meta": return "Meta*";
	case "ChunkMeta": return "ChunkMeta";
	default:
		throw new Exception(format("Unhandled type (%s)", type));
	}
}

string getMemberArrayType(PacketGroup pg, string type)
{
	switch(type) {
	// Primitive
	case "bool": return "bool[]";
	case "byte": return "byte[]";
	case "ubyte": return "ubyte[]";
	case "int": return "int[]";
	case "uint": return "uint[]";
	case "short": return "short[]";
	case "ushort": return "ushort[]";
	case "long": return "long[]";
	case "ulong": return "ulong[]";
	case "float": return "float[]";
	case "double": return "double[]";
	case "string": return "string[]";
	// Meta
	case "slot": return "Slot*";
	case "meta": return "Meta*";
	case "ChunkMeta": return "ChunkMeta[]";
	default:
		throw new Exception(format("Unhandled type (%s)", type));
	}
}
