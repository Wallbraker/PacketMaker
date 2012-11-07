// Copyright © 2012, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/license.d.
module generator;

import packets : PacketGroup, Packet, Member, Constant;
import std.stream : Stream;
import std.cstream : dout;

void output(PacketGroup pg)
{
	Stream o = dout;

	o.writeHeader(pg);
	o.writeStructs(pg);
	o.writeInterfaces(pg);
	o.writeReadFunctions(pg);

}

void writeHeader(Stream o, PacketGroup pg)
{
	o.writefln("module packets;");
	o.writefln();
	o.writefln("class %s", pg.socketTypeStr);
	o.writefln("{");
	o.writefln("}");
	o.writefln();
}

void writeStructs(Stream o, PacketGroup pg)
{
	foreach(p; pg.clientPackets) {
		o.writefln("struct %s", p.structName);

		o.writefln("{");
		o.writefln("}");
		o.writefln();
	}

	foreach(p; pg.serverPackets) {
		o.writefln("struct %s", p.structName);

		o.writefln("{");
		o.writefln("}");
		o.writefln();
	}
}

void writeReadFunctions(Stream o, PacketGroup pg)
{
	foreach(p; pg.clientPackets) {
		o.writefln("void %s(%s %s, %s %s)",
			p.readFuncName,
			pg.socketTypeStr,
			pg.socketNameStr,
			pg.clientListenerTypeStr,
			pg.listenerNameStr);

		o.writefln("{");
		o.writefln("}");
		o.writefln();
	}

	foreach(p; pg.serverPackets) {
		o.writefln("void %s(%s %s, %s %s)",
			p.readFuncName,
			pg.socketTypeStr,
			pg.socketNameStr,
			pg.serverListenerTypeStr,
			pg.listenerNameStr);

		o.writefln("{");
		o.writefln("}");
		o.writefln();
	}
}

void writeInterfaces(Stream o, PacketGroup pg)
{
	o.writefln("interface %s", pg.clientListenerTypeStr);
	o.writefln("{");
	foreach(p; pg.clientPackets) {
		o.writefln("\tvoid %s(ref %s);", p.listenerName, p.structName);
	}
	o.writefln("}");
	o.writefln();

	o.writefln("interface %s", pg.serverListenerTypeStr);
	o.writefln("{");
	foreach(p; pg.serverPackets) {
		o.writefln("\tvoid %s(ref %s);", p.listenerName, p.structName);
	}
	o.writefln("}");
	o.writefln();
}
